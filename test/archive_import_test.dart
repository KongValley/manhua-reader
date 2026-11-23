import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:manhua_reader/models/comic_book.dart';
import 'package:manhua_reader/services/app_paths.dart';
import 'package:manhua_reader/services/library_repository.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late AppPaths paths;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('manhua_cbz_import_test_');
    paths = await AppPaths.create(temp);
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('imports a CBZ with a cover and restores it from disk', () async {
    final repository = LibraryRepository(paths);
    await repository.load();
    addTearDown(repository.dispose);

    final source = File(p.join(temp.path, '海边的漫画.cbz'));
    await source.writeAsBytes(
      _zip({
        'chapter-1/001.jpg': _jpeg(120, 180),
        'chapter-1/002.jpg': _jpeg(120, 180),
        'chapter-2/001.jpg': _jpeg(120, 180),
      }),
    );

    final book = await repository.importFile(source.path);
    expect(book.format, ComicFormat.cbz);
    expect(book.pageCount, 3);
    expect(book.originalName, '海边的漫画.cbz');
    expect(p.extension(book.filePath), '.cbz');
    expect(await File(book.filePath).exists(), isTrue);
    expect(book.coverPath, isNotNull);
    expect(await File(book.coverPath!).exists(), isTrue);
    expect(repository.books, hasLength(1));

    await repository.flush();
    final reloaded = LibraryRepository(paths);
    await reloaded.load();
    addTearDown(reloaded.dispose);
    expect(reloaded.books, hasLength(1));
    expect(reloaded.books.first.format, ComicFormat.cbz);
    expect(reloaded.books.first.pageCount, 3);
  });

  test('external opens reuse only byte-identical library files', () async {
    final repository = LibraryRepository(paths);
    await repository.load();
    addTearDown(repository.dispose);

    final page = _png(90, 120);
    final original = _zip({'001.png': page});
    final different = _zip({'002.png': page});
    expect(different, hasLength(original.length));

    final source = File(p.join(temp.path, 'book.cbz'));
    await source.writeAsBytes(original);
    final first = await repository.importFile(source.path);
    final renamed = File(p.join(temp.path, 'renamed.cbz'));
    await renamed.writeAsBytes(original);
    expect(
      await repository.importFile(renamed.path, reuseIdenticalBook: true),
      same(first),
    );

    await source.writeAsBytes(different);
    final second = await repository.importFile(
      source.path,
      reuseIdenticalBook: true,
    );
    expect(second.id, isNot(first.id));
    expect(repository.books, hasLength(2));

    await File(first.filePath).delete();
    final replacement = await repository.importFile(
      renamed.path,
      reuseIdenticalBook: true,
    );
    expect(replacement.id, isNot(first.id));
    expect(repository.fileExists(replacement), isTrue);
    await repository.flush();
  });

  test('accepts CBZ but not plain ZIP extensions', () {
    expect(ComicFormat.allExtensions, ['pdf', 'mobi', 'cbz']);
    expect(ComicFormat.fromExtension('.cbz'), ComicFormat.cbz);
    expect(ComicFormat.fromExtension('.zip'), isNull);
  });

  test('rejects plain .zip files', () async {
    final repository = LibraryRepository(paths);
    await repository.load();
    addTearDown(repository.dispose);

    final source = File(p.join(temp.path, 'scanned.zip'));
    await source.writeAsBytes(_zip({'001.png': _png(90, 120)}));

    await expectLater(
      repository.importFile(source.path),
      throwsA(
        isA<ImportException>().having(
          (error) => error.message,
          'message',
          contains('仅支持 PDF、MOBI、CBZ'),
        ),
      ),
    );
    expect(repository.books, isEmpty);
  });

  test('rejects an archive without images', () async {
    final repository = LibraryRepository(paths);
    await repository.load();
    addTearDown(repository.dispose);

    final source = File(p.join(temp.path, 'empty.cbz'));
    await source.writeAsBytes(
      _zip({'readme.txt': Uint8List.fromList('hello'.codeUnits)}),
    );

    await expectLater(
      repository.importFile(source.path),
      throwsA(
        isA<ImportException>().having(
          (error) => error.message,
          'message',
          contains('没有可显示的图片'),
        ),
      ),
    );
    expect(repository.books, isEmpty);
  });
}

Uint8List _zip(Map<String, Uint8List> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    archive.add(ArchiveFile.bytes(entry.key, entry.value));
  }
  return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
}

Uint8List _jpeg(int width, int height) {
  final picture = image.Image(width: width, height: height);
  image.fill(picture, color: image.ColorRgb8(220, 220, 220));
  return Uint8List.fromList(image.encodeJpg(picture, quality: 85));
}

Uint8List _png(int width, int height) {
  final picture = image.Image(width: width, height: height);
  image.fill(picture, color: image.ColorRgb8(20, 40, 60));
  return Uint8List.fromList(image.encodePng(picture));
}
