import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:manhua_reader/formats/album/album_store.dart';
import 'package:manhua_reader/models/comic_book.dart';
import 'package:manhua_reader/services/app_paths.dart';
import 'package:manhua_reader/services/library_repository.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late Directory appDir;
  late Directory albumDir;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('manhua_album_test_');
    appDir = Directory(p.join(temp.path, 'app'));
    albumDir = Directory(p.join(temp.path, 'images', '海边相册'));
    await _write(albumDir, '001.jpg', _jpeg(120, 180));
    await _write(albumDir, '002.jpg', _jpeg(120, 180));
    await _write(albumDir, 'chapter-2/001.png', _png(90, 120));
  });

  tearDown(() async {
    try {
      if (await temp.exists()) await temp.delete(recursive: true);
    } on FileSystemException {
      // Windows may keep a decoded image or scanner handle briefly.
      // Windows 可能短暂保留解码图片或扫描器句柄。
    }
  });

  test('imports an album without copying images and reloads it', () async {
    final paths = await AppPaths.create(appDir);
    final repository = LibraryRepository(paths);
    await repository.load();
    addTearDown(repository.dispose);

    final book = await repository.importAlbumDirectory(albumDir);
    expect(book.format, ComicFormat.album);
    expect(book.pageCount, 3);
    expect(book.title, '海边相册');
    expect(book.filePath, albumDir.path);
    expect(book.coverPath, isNotNull);
    expect(await File(book.coverPath!).exists(), isTrue);
    expect(await _filesIn(paths.booksDir), isEmpty);
    expect(await albumDir.exists(), isTrue);
    expect(repository.fileExists(book), isTrue);
    final report = await repository.storageReport();
    expect(report.bookBytes, 0);
    expect(report.coverBytes, greaterThan(0));

    await repository.flush();
    final reloaded = LibraryRepository(paths);
    await reloaded.load();
    addTearDown(reloaded.dispose);
    expect(reloaded.books.single.format, ComicFormat.album);
    expect(reloaded.books.single.filePath, albumDir.path);
    expect(reloaded.books.single.pageCount, 3);
  });

  test('rejects the same album twice', () async {
    final paths = await AppPaths.create(appDir);
    final repository = LibraryRepository(paths);
    await repository.load();
    addTearDown(repository.dispose);

    await repository.importAlbumDirectory(albumDir);
    await expectLater(
      repository.importAlbumDirectory(albumDir),
      throwsA(isA<ImportException>()),
    );
    expect(repository.books, hasLength(1));
  });

  test('deleting an album keeps the source folder', () async {
    final paths = await AppPaths.create(appDir);
    final repository = LibraryRepository(paths);
    await repository.load();
    addTearDown(repository.dispose);

    final book = await repository.importAlbumDirectory(albumDir);
    final cover = book.coverPath!;
    await repository.deleteBook(book);
    expect(repository.books, isEmpty);
    expect(await albumDir.exists(), isTrue);
    expect(await File(cover).exists(), isFalse);
  });

  test('relinks an album and keeps progress', () async {
    final paths = await AppPaths.create(appDir);
    final repository = LibraryRepository(paths);
    await repository.load();
    addTearDown(repository.dispose);

    final book = await repository.importAlbumDirectory(albumDir);
    repository.updateProgress(book, 1);
    final moved = Directory(p.join(temp.path, 'images', '搬家后的相册'));
    await albumDir.rename(moved.path);

    await repository.relinkAlbum(book, source: moved.path);
    expect(book.filePath, moved.path);
    expect(book.pageCount, 3);
    expect(book.lastPage, 1);
    expect(await moved.exists(), isTrue);
    expect(repository.fileExists(book), isTrue);
  });

  test('sorting remaps progress and bookmarks by image path', () async {
    final paths = await AppPaths.create(appDir);
    final repository = LibraryRepository(paths);
    await repository.load();
    addTearDown(repository.dispose);

    final book = await repository.importAlbumDirectory(albumDir);
    final oldKeys = (await FileAlbumStore(
      albumDir.path,
    ).list()).map((image) => image.relativePath).toList();
    repository.setBookmark(book, 0, label: '第一张', note: '保留备注');
    repository.updateProgress(book, 2);

    final newKeys = [oldKeys[2], oldKeys[0], oldKeys[1]];
    final dropped = repository.setAlbumSort(
      book,
      AlbumSortField.modified,
      true,
      oldKeys: oldKeys,
      newKeys: newKeys,
    );
    expect(dropped, 0);
    expect(book.lastPage, 0);
    expect(book.bookmarks.single.page, 1);
    expect(book.bookmarks.single.label, '第一张');
    expect(book.bookmarks.single.note, '保留备注');
    expect(book.albumSort, AlbumSortField.modified);
    expect(book.albumSortDescending, isTrue);

    await repository.flush();
    final reloaded = LibraryRepository(paths);
    await reloaded.load();
    addTearDown(reloaded.dispose);
    expect(reloaded.books.single.albumSort, AlbumSortField.modified);
    expect(reloaded.books.single.albumSortDescending, isTrue);
    expect(reloaded.books.single.bookmarks.single.page, 1);
  });

  test('backs up album metadata without embedding images', () async {
    final paths = await AppPaths.create(appDir);
    final repository = LibraryRepository(paths);
    await repository.load();
    addTearDown(repository.dispose);

    final book = await repository.importAlbumDirectory(albumDir);
    await repository.flush();
    final archiveFile = await repository.createBackupArchive();
    addTearDown(() async {
      if (await archiveFile.exists()) await archiveFile.delete();
    });
    final bytes = await archiveFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    expect(
      archive.files.where((entry) => entry.name.startsWith('books/')),
      isEmpty,
    );
    final manifest = archive.findFile('manifest.json');
    expect(manifest, isNotNull);
    final decoded =
        jsonDecode(utf8.decode(manifest!.readBytes()!)) as Map<String, dynamic>;
    final manifestBooks = decoded['books'] as List<dynamic>;
    expect(manifestBooks.single['filePath'], book.filePath);
    final fileList = decoded['fileList'] as List<dynamic>;
    expect(fileList.single['external'], isTrue);

    final restoredPaths = await AppPaths.create(
      Directory(p.join(temp.path, 'restored')),
    );
    final restored = LibraryRepository(restoredPaths);
    await restored.load();
    addTearDown(restored.dispose);
    final result = await restored.restoreBackupBytes(bytes);
    expect(result.imported, 1);
    expect(restored.books.single.format, ComicFormat.album);
    expect(restored.books.single.filePath, albumDir.path);
    expect(restored.books.single.coverPath, isNotNull);
    expect(result.booksWithoutFiles, 0);
  });

  test('restores a JSON backup of an external album', () async {
    final paths = await AppPaths.create(appDir);
    final repository = LibraryRepository(paths);
    await repository.load();
    addTearDown(repository.dispose);

    final book = await repository.importAlbumDirectory(albumDir);
    final bytes = repository.exportBackupJson();

    final restoredPaths = await AppPaths.create(
      Directory(p.join(temp.path, 'json-restored')),
    );
    final restored = LibraryRepository(restoredPaths);
    await restored.load();
    addTearDown(restored.dispose);
    final result = await restored.restoreBackupBytes(bytes);
    expect(result.imported, 1);
    expect(restored.books.single.filePath, book.filePath);
    expect(restored.books.single.format, ComicFormat.album);
  });
}

Future<void> _write(Directory root, String relative, Uint8List bytes) async {
  final file = File(p.join(root.path, relative));
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes, flush: true);
}

Future<List<FileSystemEntity>> _filesIn(Directory directory) async {
  if (!await directory.exists()) return const [];
  return directory.list().toList();
}

Uint8List _jpeg(int width, int height) {
  final picture = image.Image(width: width, height: height);
  image.fill(picture, color: image.ColorRgb8(220, 220, 220));
  return Uint8List.fromList(image.encodeJpg(picture, quality: 85));
}

Uint8List _png(int width, int height) {
  final picture = image.Image(width: width, height: height);
  image.fill(picture, color: image.ColorRgb8(30, 60, 90));
  return Uint8List.fromList(image.encodePng(picture));
}
