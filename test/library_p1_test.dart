import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:manhua_reader/models/comic_book.dart';
import 'package:manhua_reader/models/library_settings.dart';
import 'package:manhua_reader/services/app_paths.dart';
import 'package:manhua_reader/services/library_repository.dart';
import 'package:manhua_reader/services/pdf_password_cache.dart';
import 'package:path/path.dart' as p;

ComicBook _book({
  required String id,
  required String title,
  required String originalName,
  required String filePath,
  ComicFormat format = ComicFormat.pdf,
  int pageCount = 20,
  int fileSize = 100,
  DateTime? addedAt,
  String? coverPath,
}) {
  return ComicBook(
    id: id,
    title: title,
    originalName: originalName,
    filePath: filePath,
    format: format,
    pageCount: pageCount,
    fileSize: fileSize,
    addedAt: addedAt ?? DateTime(2026, 11, 1),
    coverPath: coverPath,
  );
}

void main() {
  late Directory temp;
  late AppPaths paths;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('manhua_p1_test_');
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

  test('persists bookshelf view and sort preferences', () async {
    final repository = LibraryRepository(paths);
    await repository.load();
    expect(repository.librarySettings.view, LibraryViewMode.grid);
    expect(repository.librarySettings.sort, LibrarySort.recentRead);

    repository.setLibraryView(LibraryViewMode.list);
    repository.setLibrarySort(LibrarySort.title);
    await repository.flush();
    repository.dispose();

    final decoded = jsonDecode(
      await paths.libraryFile.readAsString(),
    ) as Map<String, dynamic>;
    expect(decoded['version'], 3);
    expect(decoded['stats'], isA<Map<String, dynamic>>());
    expect(decoded['library'], {'view': 'list', 'sort': 'title'});

    final reloaded = LibraryRepository(paths);
    await reloaded.load();
    expect(reloaded.librarySettings.view, LibraryViewMode.list);
    expect(reloaded.librarySettings.sort, LibrarySort.title);
    reloaded.dispose();
  });

  test('renames a book with normalised whitespace and persists it', () async {
    final seeded = _book(
      id: 'rename',
      title: '旧名字',
      originalName: 'rename.pdf',
      filePath: p.join(temp.path, 'rename.pdf'),
    );
    await seedLibrary([seeded]);

    final repository = LibraryRepository(paths);
    await repository.load();
    final book = repository.books.single;

    repository.renameBook(book, '  海边   的   咖啡馆  ');
    expect(book.title, '海边 的 咖啡馆');

    repository.renameBook(book, '   ');
    expect(book.title, '海边 的 咖啡馆');
    repository.renameBook(book, 'x' * 101);
    expect(book.title, '海边 的 咖啡馆');

    repository.renameBook(book, '最终名字');
    await repository.flush();
    repository.dispose();

    final reloaded = LibraryRepository(paths);
    await reloaded.load();
    expect(reloaded.books.single.title, '最终名字');
    reloaded.dispose();
  });

  test('reports referenced and orphaned storage, then cleans it', () async {
    final keepBook = File(p.join(paths.booksDir.path, 'keep.pdf'));
    await keepBook.writeAsBytes(List<int>.filled(100, 1));
    final keepCover = File(p.join(paths.coversDir.path, 'keep.png'));
    await keepCover.writeAsBytes(List<int>.filled(10, 1));

    final orphanBook = File(p.join(paths.booksDir.path, 'orphan.pdf'));
    await orphanBook.writeAsBytes(List<int>.filled(50, 1));
    final orphanCover = File(p.join(paths.coversDir.path, 'orphan.png'));
    await orphanCover.writeAsBytes(List<int>.filled(20, 1));
    final cacheFile = File(p.join(paths.cacheDir.path, 'nested', 'page.bin'));
    await cacheFile.parent.create(recursive: true);
    await cacheFile.writeAsBytes(List<int>.filled(30, 1));

    await seedLibrary([
      _book(
        id: 'keep',
        title: '保留',
        originalName: 'keep.pdf',
        filePath: keepBook.path,
        coverPath: keepCover.path,
      ),
    ]);

    final repository = LibraryRepository(paths);
    await repository.load();
    final report = await repository.storageReport();
    expect(report.bookBytes, 100);
    expect(report.coverBytes, 10);
    expect(report.cacheBytes, 30);
    expect(report.orphanBytes, 70);
    expect(report.orphanFiles, 2);
    expect(report.totalBytes, 110);
    expect(report.reclaimableBytes, 100);

    final freed = await repository.cleanupStorage();
    expect(freed, 100);
    expect(await keepBook.exists(), isTrue);
    expect(await keepCover.exists(), isTrue);
    expect(await orphanBook.exists(), isFalse);
    expect(await orphanCover.exists(), isFalse);
    expect(await cacheFile.exists(), isFalse);

    final after = await repository.storageReport();
    expect(after.orphanBytes, 0);
    expect(after.orphanFiles, 0);
    expect(after.cacheBytes, 0);
    expect(after.bookBytes, 100);
    expect(after.coverBytes, 10);
    repository.dispose();
  });

  test('marks selected books as read', () async {
    final first = _book(
      id: 'read-first',
      title: '第一本',
      originalName: 'first.pdf',
      filePath: p.join(paths.booksDir.path, 'first.pdf'),
      pageCount: 30,
    );
    final second = _book(
      id: 'read-second',
      title: '第二本',
      originalName: 'second.pdf',
      filePath: p.join(paths.booksDir.path, 'second.pdf'),
      pageCount: 1,
    );
    await seedLibrary([first, second]);

    final repository = LibraryRepository(paths);
    await repository.load();
    final books = repository.books;

    final changed = repository.markBooksRead(books);
    expect(changed, 2);
    for (final book in books) {
      expect(book.lastReadAt, isNotNull);
      expect(book.lastPage, book.pageCount - 1);
      expect(book.progress, 1);
    }
    expect(repository.markBooksRead(books), 0);

    await repository.flush();
    repository.dispose();
    final reloaded = LibraryRepository(paths);
    await reloaded.load();
    expect(reloaded.books.every((book) => book.progress == 1), isTrue);
    reloaded.dispose();
  });

  test('deletes several books, their files and cached passwords', () async {
    final firstFile = File(p.join(paths.booksDir.path, 'first.pdf'));
    final secondFile = File(p.join(paths.booksDir.path, 'second.mobi'));
    final firstCover = File(p.join(paths.coversDir.path, 'first.png'));
    final secondCover = File(p.join(paths.coversDir.path, 'second.png'));
    for (final file in [firstFile, secondFile, firstCover, secondCover]) {
      await file.writeAsBytes([1, 2, 3]);
    }

    final first = _book(
      id: 'first',
      title: '第一本',
      originalName: 'first.pdf',
      filePath: firstFile.path,
      coverPath: firstCover.path,
    );
    final second = _book(
      id: 'second',
      title: '第二本',
      originalName: 'second.mobi',
      filePath: secondFile.path,
      format: ComicFormat.mobi,
      coverPath: secondCover.path,
    );
    await seedLibrary([first, second]);

    final repository = LibraryRepository(paths);
    await repository.load();
    PdfPasswordCache.put(firstFile.path, 'secret-1');
    PdfPasswordCache.put(secondFile.path, 'secret-2');

    await repository.deleteBooks([
      repository.books.first,
      repository.books.last,
    ]);

    expect(repository.books, isEmpty);
    expect(await firstFile.exists(), isFalse);
    expect(await secondFile.exists(), isFalse);
    expect(await firstCover.exists(), isFalse);
    expect(await secondCover.exists(), isFalse);
    expect(PdfPasswordCache.get(firstFile.path), isNull);
    expect(PdfPasswordCache.get(secondFile.path), isNull);

    await repository.flush();
    repository.dispose();
    final reloaded = LibraryRepository(paths);
    await reloaded.load();
    expect(reloaded.books, isEmpty);
    reloaded.dispose();
  });

  test('failed imports leave no partial files behind', () async {
    final corrupt = File(p.join(temp.path, 'broken.mobi'));
    await corrupt.writeAsBytes([1, 2, 3, 4]);

    final repository = LibraryRepository(paths);
    await repository.load();

    await expectLater(
      repository.importFile(corrupt.path),
      throwsA(isA<ImportException>()),
    );
    expect(repository.books, isEmpty);
    expect(await paths.booksDir.list().toList(), isEmpty);
    expect(
      (await paths.booksDir.list().toList()).where(
        (entry) => entry.path.endsWith('.part'),
      ),
      isEmpty,
    );

    await repository.flush();
    repository.dispose();
  });
}
