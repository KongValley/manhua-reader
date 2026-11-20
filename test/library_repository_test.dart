import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:manhua_reader/models/comic_book.dart';
import 'package:manhua_reader/models/reader_settings.dart';
import 'package:manhua_reader/services/app_paths.dart';
import 'package:manhua_reader/services/library_repository.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;
  late AppPaths paths;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('manhua_repository_test_');
    paths = await AppPaths.create(temp);
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('loads an empty library', () async {
    final repository = LibraryRepository(paths);
    await repository.load();
    expect(repository.isLoaded, isTrue);
    expect(repository.books, isEmpty);
    repository.dispose();
  });

  test('restores books, settings and progress from disk', () async {
    final addedAt = DateTime(2026, 11, 1, 10, 30);
    final seeded = ComicBook(
      id: 'book-1',
      title: '海边的咖啡馆',
      originalName: 'volume-1.pdf',
      filePath: '${temp.path}/volume-1.pdf',
      format: ComicFormat.pdf,
      pageCount: 40,
      fileSize: 123456,
      addedAt: addedAt,
    );

    await paths.libraryFile.writeAsString(
      jsonEncode({
        'version': 1,
        'settings': {'mode': 'vertical', 'rightToLeft': true},
        'books': [seeded.toJson()],
      }),
    );

    final repository = LibraryRepository(paths);
    await repository.load();
    expect(repository.books, hasLength(1));
    expect(repository.books.first.title, '海边的咖啡馆');
    expect(repository.settings.mode, ReadingMode.vertical);
    expect(repository.settings.rightToLeft, isTrue);

    repository.updateProgress(repository.books.first, 9);
    await repository.flush();
    repository.dispose();

    final reloaded = LibraryRepository(paths);
    await reloaded.load();
    expect(reloaded.books.first.lastPage, 9);
    expect(reloaded.books.first.progress, closeTo(0.25, 0.0001));
    expect(reloaded.books.first.lastReadAt, isNotNull);
    expect(reloaded.books.first.hasStarted, isTrue);
    reloaded.dispose();
  });

  test(
    'relocates stale absolute paths after the app container moves',
    () async {
      const bookId = 'old-book';
      final bookFile = File(p.join(paths.booksDir.path, '$bookId.pdf'));
      await bookFile.writeAsBytes([1, 2, 3]);
      final coverFile = File(p.join(paths.coversDir.path, '$bookId.png'));
      await coverFile.writeAsBytes([1, 2, 3]);

      final seeded = ComicBook(
        id: bookId,
        title: '搬家的漫画',
        originalName: 'moved.pdf',
        filePath: '/old/container/books/$bookId.pdf',
        coverPath: '/old/container/covers/$bookId.png',
        format: ComicFormat.pdf,
        pageCount: 10,
        fileSize: 3,
        addedAt: DateTime(2026, 11, 1),
      );
      await paths.libraryFile.writeAsString(
        jsonEncode({
          'version': 1,
          'settings': {},
          'books': [seeded.toJson()],
        }),
      );

      final repository = LibraryRepository(paths);
      await repository.load();
      expect(repository.books.single.filePath, bookFile.path);
      expect(repository.books.single.coverPath, coverFile.path);
      expect(repository.fileExists(repository.books.single), isTrue);
      repository.dispose();
    },
  );

  test('toggles and persists bookmarks', () async {
    final seeded = ComicBook(
      id: 'bookmarks',
      title: '书签测试',
      originalName: 'bookmarks.pdf',
      filePath: p.join(temp.path, 'missing.pdf'),
      format: ComicFormat.pdf,
      pageCount: 20,
      fileSize: 1,
      addedAt: DateTime(2026, 11, 1),
    );
    await paths.libraryFile.writeAsString(
      jsonEncode({
        'version': 1,
        'settings': {},
        'books': [seeded.toJson()],
      }),
    );

    final repository = LibraryRepository(paths);
    await repository.load();
    final book = repository.books.single;
    expect(book.bookmarks, isEmpty);

    repository.toggleBookmark(book, 5);
    repository.toggleBookmark(book, 2);
    expect(book.bookmarks.map((entry) => entry.page).toList(), [2, 5]);
    expect(repository.isBookmarked(book, 2), isTrue);
    await repository.flush();
    repository.dispose();

    final reloaded = LibraryRepository(paths);
    await reloaded.load();
    expect(
      reloaded.books.single.bookmarks.map((entry) => entry.page).toList(),
      [2, 5],
    );
    reloaded.removeBookmark(reloaded.books.single, 2);
    expect(
      reloaded.books.single.bookmarks.map((entry) => entry.page).toList(),
      [5],
    );
    await reloaded.flush();
    reloaded.dispose();
  });

  test('persists bookmark names and notes', () async {
    final seeded = ComicBook(
      id: 'named-bookmarks',
      title: '命名书签',
      originalName: 'named-bookmarks.pdf',
      filePath: p.join(temp.path, 'missing.pdf'),
      format: ComicFormat.pdf,
      pageCount: 20,
      fileSize: 1,
      addedAt: DateTime(2026, 11, 1),
    );
    await paths.libraryFile.writeAsString(
      jsonEncode({
        'version': 1,
        'settings': {},
        'books': [seeded.toJson()],
      }),
    );

    final repository = LibraryRepository(paths);
    await repository.load();
    final book = repository.books.single;

    repository.setBookmark(book, 3, label: '  第一章高潮  ', note: '  这里的分镜很精彩  ');
    var bookmark = book.bookmarkAt(3)!;
    expect(bookmark.title, '第一章高潮');
    expect(bookmark.note, '这里的分镜很精彩');

    repository.setBookmark(book, 3, label: null, note: '仅备注');
    bookmark = book.bookmarkAt(3)!;
    expect(bookmark.title, '第 4 页');
    expect(bookmark.note, '仅备注');

    repository.setBookmark(book, 8, label: '改名', note: null);
    expect(book.bookmarkAt(8)!.title, '改名');
    expect(book.bookmarkAt(8)!.note, isNull);
    await repository.flush();
    repository.dispose();

    final reloaded = LibraryRepository(paths);
    await reloaded.load();
    final loadedBook = reloaded.books.single;
    expect(loadedBook.bookmarks.map((entry) => entry.page).toList(), [3, 8]);
    expect(loadedBook.bookmarkAt(3)!.title, '第 4 页');
    expect(loadedBook.bookmarkAt(3)!.note, '仅备注');
    expect(loadedBook.bookmarkAt(8)!.title, '改名');
    expect(loadedBook.bookmarkAt(8)!.note, isNull);
    reloaded.dispose();
  });

  test('falls back to defaults for a corrupt library file', () async {
    await paths.libraryFile.writeAsString('{not json');
    final repository = LibraryRepository(paths);
    await repository.load();
    expect(repository.books, isEmpty);
    expect(repository.settings.mode, ReadingMode.horizontal);
    repository.dispose();
  });
}
