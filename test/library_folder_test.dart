import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:manhua_reader/models/comic_book.dart';
import 'package:manhua_reader/services/app_paths.dart';
import 'package:manhua_reader/services/library_repository.dart';
import 'package:path/path.dart' as p;

ComicBook _book({
  required String id,
  required String filePath,
  String? folderId,
}) {
  return ComicBook(
    id: id,
    title: id,
    originalName: '$id.pdf',
    filePath: filePath,
    format: ComicFormat.pdf,
    pageCount: 10,
    fileSize: 3,
    addedAt: DateTime(2026, 11, 1),
    folderId: folderId,
  );
}

void main() {
  late Directory temp;
  late AppPaths paths;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('manhua_folder_repo_');
    paths = await AppPaths.create(temp);
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  Future<void> seed({
    required List<ComicBook> books,
    List<Map<String, Object?>> folders = const [],
    int version = 4,
  }) async {
    await paths.libraryFile.writeAsString(
      jsonEncode({
        'version': version,
        'settings': <String, Object?>{},
        'library': <String, Object?>{},
        'folders': folders,
        'books': books.map((book) => book.toJson()).toList(),
      }),
    );
  }

  test('creates, reuses and renames shelf folders', () async {
    final firstFile = File(p.join(paths.booksDir.path, 'first.pdf'));
    final secondFile = File(p.join(paths.booksDir.path, 'second.pdf'));
    await firstFile.writeAsBytes([1]);
    await secondFile.writeAsBytes([1]);
    await seed(
      books: [
        _book(id: 'first', filePath: firstFile.path, folderId: 'folder-1'),
        _book(id: 'second', filePath: secondFile.path),
      ],
      folders: [
        {
          'id': 'folder-1',
          'name': '原始文件夹',
          'createdAt': '2026-11-01T00:00:00.000',
        },
      ],
    );

    final repository = LibraryRepository(paths);
    await repository.load();
    expect(repository.folders.single.name, '原始文件夹');
    expect(repository.folderCounts['folder-1'], 1);

    final reused = repository.ensureFolder('  原始文件夹  ');
    expect(reused.id, 'folder-1');
    final created = repository.ensureFolder('新文件夹');
    expect(created.name, '新文件夹');
    expect(repository.folders, hasLength(2));

    expect(repository.renameFolder(created, ' 改名后的文件夹 '), isTrue);
    expect(created.name, '改名后的文件夹');
    expect(repository.renameFolder(created, '原始文件夹'), isFalse);

    await repository.flush();
    repository.dispose();

    final reloaded = LibraryRepository(paths);
    await reloaded.load();
    expect(
      reloaded.folders.map((folder) => folder.name),
      containsAll(['原始文件夹', '改名后的文件夹']),
    );
    expect(reloaded.books.first.folderId, 'folder-1');
    reloaded.dispose();
  });

  test('deletes a folder but keeps its books', () async {
    final file = File(p.join(paths.booksDir.path, 'book.pdf'));
    await file.writeAsBytes([1]);
    await seed(
      books: [_book(id: 'book', filePath: file.path, folderId: 'folder-1')],
      folders: [
        {
          'id': 'folder-1',
          'name': '文件夹',
          'createdAt': '2026-11-01T00:00:00.000',
        },
      ],
    );

    final repository = LibraryRepository(paths);
    await repository.load();
    final folder = repository.folders.single;
    await repository.deleteFolder(folder);
    expect(repository.folders, isEmpty);
    expect(repository.books.single.folderId, isNull);
    expect(await File(file.path).exists(), isTrue);
    repository.dispose();
  });

  test('restores folders and book assignments from backup', () async {
    final file = File(p.join(paths.booksDir.path, 'book.pdf'));
    await file.writeAsBytes([1, 2, 3]);
    await seed(
      books: [_book(id: 'book', filePath: file.path, folderId: 'folder-1')],
      folders: [
        {
          'id': 'folder-1',
          'name': '备份文件夹',
          'createdAt': '2026-11-01T00:00:00.000',
        },
      ],
    );

    final source = LibraryRepository(paths);
    await source.load();
    final bytes = source.exportBackupJson();
    final manifest = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    expect((manifest['folders'] as List), hasLength(1));
    source.dispose();

    final restoreRoot = await Directory.systemTemp.createTemp(
      'manhua_folder_restore_',
    );
    addTearDown(() async {
      if (await restoreRoot.exists()) await restoreRoot.delete(recursive: true);
    });
    final restorePaths = await AppPaths.create(restoreRoot);
    final restored = LibraryRepository(restorePaths);
    await restored.load();
    final result = await restored.restoreBackupBytes(bytes);
    expect(result.imported, 1);
    expect(restored.folders.single.name, '备份文件夹');
    final book = restored.books.single;
    expect(book.folderId, restored.folders.single.id);
    expect(restored.folderCounts[book.folderId], 1);
    restored.dispose();
  });

  test('migrates v3 data without folders to schema v4', () async {
    final file = File(p.join(paths.booksDir.path, 'legacy.pdf'));
    await file.writeAsBytes([1]);
    await seed(
      version: 3,
      books: [_book(id: 'legacy', filePath: file.path)],
    );

    final repository = LibraryRepository(paths);
    await repository.load();
    expect(repository.folders, isEmpty);
    expect(repository.books.single.folderId, isNull);
    await repository.flush();
    repository.dispose();

    final decoded = jsonDecode(
      await paths.libraryFile.readAsString(),
    ) as Map<String, dynamic>;
    expect(decoded['version'], 4);
    expect(decoded['folders'], isEmpty);
  });
}
