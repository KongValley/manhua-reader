import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:manhua_reader/models/comic_book.dart';
import 'package:manhua_reader/models/reader_settings.dart';
import 'package:manhua_reader/services/app_paths.dart';
import 'package:manhua_reader/services/library_repository.dart';
import 'package:path/path.dart' as p;

ComicBook _book({
  required String id,
  required String title,
  required String filePath,
  String? series,
  List<String> tags = const [],
  bool favorite = false,
  bool pinned = false,
  String? coverPath,
}) {
  return ComicBook(
    id: id,
    title: title,
    originalName: '$id.pdf',
    filePath: filePath,
    format: ComicFormat.pdf,
    pageCount: 20,
    fileSize: 3,
    addedAt: DateTime(2026, 11, 1),
    coverPath: coverPath,
    series: series,
    tags: tags,
    favorite: favorite,
    pinned: pinned,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late AppPaths paths;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('manhua_p2_test_');
    paths = await AppPaths.create(temp);
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  Future<void> seedLibrary(List<ComicBook> books) async {
    await paths.libraryFile.writeAsString(
      jsonEncode({
        'version': 2,
        'settings': <String, Object?>{},
        'library': <String, Object?>{},
        'books': books.map((book) => book.toJson()).toList(),
      }),
    );
  }

  test('migrates v2 libraries and derives series names', () async {
    final file = File(p.join(paths.booksDir.path, 'vol.pdf'));
    await file.writeAsBytes([1, 2, 3]);
    await seedLibrary([
      _book(id: 'vol', title: 'VOL.001', filePath: file.path),
    ]);

    final repository = LibraryRepository(paths);
    await repository.load();
    final book = repository.books.single;
    expect(book.series, 'VOL');
    expect(repository.seriesCounts['VOL'], 1);

    await repository.flush();
    repository.dispose();

    final decoded = jsonDecode(
      await paths.libraryFile.readAsString(),
    ) as Map<String, dynamic>;
    expect(decoded['version'], 4);
    expect(decoded['stats'], isA<Map>());
    final stored = (decoded['books'] as List).single as Map;
    expect(stored['series'], 'VOL');
  });

  test('persists organization, favorites and pinned ordering', () async {
    final firstFile = File(p.join(paths.booksDir.path, 'first.pdf'));
    final secondFile = File(p.join(paths.booksDir.path, 'second.pdf'));
    await firstFile.writeAsBytes([1]);
    await secondFile.writeAsBytes([1]);
    await seedLibrary([
      _book(id: 'first', title: '第一本', filePath: firstFile.path),
      _book(id: 'second', title: '第二本', filePath: secondFile.path),
    ]);

    final repository = LibraryRepository(paths);
    await repository.load();
    final first = repository.books.firstWhere((book) => book.id == 'first');
    final second = repository.books.firstWhere((book) => book.id == 'second');

    repository.setBookOrganization(
      first,
      series: '  测试系列  ',
      tags: ['  科幻 ', '科幻', '冒险'],
    );
    repository.toggleFavorite(first);
    repository.togglePinned(second);

    expect(first.series, '测试系列');
    expect(first.tags, ['科幻', '冒险']);
    expect(repository.seriesCounts['测试系列'], 1);
    expect(repository.tagNames, ['冒险', '科幻']);
    expect(repository.books.first.id, 'second');
    expect(repository.books.first.pinned, isTrue);

    await repository.flush();
    repository.dispose();

    final reloaded = LibraryRepository(paths);
    await reloaded.load();
    final loadedFirst = reloaded.books.firstWhere((book) => book.id == 'first');
    expect(loadedFirst.series, '测试系列');
    expect(loadedFirst.tags, ['科幻', '冒险']);
    expect(loadedFirst.favorite, isTrue);
    expect(reloaded.books.first.id, 'second');
    reloaded.dispose();
  });

  test('records forward reading pages and restores them', () async {
    final file = File(p.join(paths.booksDir.path, 'stats.pdf'));
    await file.writeAsBytes([1]);
    await seedLibrary([_book(id: 'stats', title: '统计', filePath: file.path)]);

    final repository = LibraryRepository(paths);
    await repository.load();
    final book = repository.books.single;
    repository.updateProgress(book, 5);
    repository.updateProgress(book, 9);
    expect(repository.stats.pagesToday(), 9);
    expect(repository.stats.totalPages, 9);

    await repository.flush();
    repository.dispose();

    final reloaded = LibraryRepository(paths);
    await reloaded.load();
    expect(reloaded.stats.totalPages, 9);
    reloaded.dispose();
  });

  test('sets a custom cover and rejects invalid image data', () async {
    final file = File(p.join(paths.booksDir.path, 'cover.pdf'));
    await file.writeAsBytes([1]);
    await seedLibrary([_book(id: 'cover', title: '封面', filePath: file.path)]);

    final repository = LibraryRepository(paths);
    await repository.load();
    final book = repository.books.single;
    final png = image.encodePng(image.Image(width: 8, height: 12));
    expect(await repository.setCustomCover(book, png), isTrue);
    expect(book.customCover, isTrue);
    expect(book.coverPath, isNotNull);
    expect(await File(book.coverPath!).exists(), isTrue);
    expect(await repository.setCustomCover(book, Uint8List(0)), isFalse);

    await repository.flush();
    repository.dispose();
  });

  test('exports JSON and full ZIP backups and restores both', () async {
    final firstFile = File(p.join(paths.booksDir.path, 'first.pdf'));
    final secondFile = File(p.join(paths.booksDir.path, 'second.pdf'));
    await firstFile.writeAsBytes([1, 2, 3, 4]);
    await secondFile.writeAsBytes([5, 6, 7]);
    final cover = File(p.join(paths.coversDir.path, 'first.png'));
    await cover.writeAsBytes(image.encodePng(image.Image(width: 4, height: 4)));

    final first = _book(
      id: 'first',
      title: '系列 第1卷',
      filePath: firstFile.path,
      series: '系列',
      tags: ['标签'],
      favorite: true,
      coverPath: cover.path,
    );
    final second = _book(
      id: 'second',
      title: '第二本',
      filePath: secondFile.path,
      pinned: true,
    );
    await seedLibrary([first, second]);

    final source = LibraryRepository(paths);
    await source.load();
    source.setReadingMode(ReadingMode.vertical);
    source.updateProgress(source.books.firstWhere((b) => b.id == 'first'), 4);
    await source.flush();

    final jsonBytes = source.exportBackupJson();
    final decoded = jsonDecode(utf8.decode(jsonBytes)) as Map<String, dynamic>;
    expect(decoded['format'], LibraryRepository.backupFormat);
    expect(decoded['includeFiles'], isFalse);
    expect((decoded['books'] as List), hasLength(2));
    expect((decoded['fileList'] as List), hasLength(2));
    expect(decoded['stats'], isA<Map>());

    final archive = await source.createBackupArchive();
    final zipBytes = await archive.readAsBytes();
    expect(zipBytes.length, greaterThan(100));
    await archive.delete();
    source.dispose();

    final jsonPaths = await AppPaths.create(
      await Directory.systemTemp.createTemp('manhua_p2_json_restore_'),
    );
    addTearDown(() async {
      if (await jsonPaths.root.exists()) {
        await jsonPaths.root.delete(recursive: true);
      }
    });
    final jsonRepo = LibraryRepository(jsonPaths);
    await jsonRepo.load();
    final jsonResult = await jsonRepo.restoreBackupBytes(jsonBytes);
    expect(jsonResult.imported, 2);
    expect(jsonResult.booksWithoutFiles, 2);
    expect(jsonRepo.books, hasLength(2));
    final restoredFirst = jsonRepo.books.firstWhere((b) => b.id == 'first');
    expect(restoredFirst.series, '系列');
    expect(restoredFirst.tags, ['标签']);
    expect(restoredFirst.favorite, isTrue);
    expect(restoredFirst.pageCount, 20);
    expect(restoredFirst.lastPage, 4);
    expect(jsonRepo.settings.mode, ReadingMode.vertical);
    expect(jsonRepo.stats.totalPages, 4);
    jsonRepo.dispose();

    final zipPaths = await AppPaths.create(
      await Directory.systemTemp.createTemp('manhua_p2_zip_restore_'),
    );
    addTearDown(() async {
      if (await zipPaths.root.exists()) {
        await zipPaths.root.delete(recursive: true);
      }
    });
    final zipRepo = LibraryRepository(zipPaths);
    await zipRepo.load();
    final zipResult = await zipRepo.restoreBackupBytes(zipBytes);
    expect(zipResult.imported, 2);
    expect(zipResult.booksWithoutFiles, 0);
    final fileBacked = zipRepo.books.firstWhere((b) => b.id == 'first');
    expect(await File(fileBacked.filePath).exists(), isTrue);
    expect(await File(fileBacked.coverPath!).exists(), isTrue);
    expect(await File(fileBacked.filePath).readAsBytes(), [1, 2, 3, 4]);

    final duplicateResult = await zipRepo.restoreBackupBytes(zipBytes);
    expect(duplicateResult.imported, 0);
    expect(duplicateResult.skipped, 2);

    await expectLater(
      zipRepo.restoreBackupBytes(Uint8List.fromList([1, 2, 3])),
      throwsA(isA<ImportException>()),
    );
    zipRepo.dispose();
  });
}
