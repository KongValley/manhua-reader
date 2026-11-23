import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:manhua_reader/models/comic_book.dart';
import 'package:manhua_reader/models/reader_settings.dart';
import 'package:manhua_reader/models/reading_stats.dart';
import 'package:manhua_reader/services/app_paths.dart';
import 'package:manhua_reader/services/library_repository.dart';
import 'package:manhua_reader/utils/pagination.dart';
import 'package:path/path.dart' as p;

ComicBook _book({
  required String id,
  String title = 'Untitled',
  String? series,
  List<String> tags = const [],
}) {
  return ComicBook(
    id: id,
    title: title,
    originalName: '$id.pdf',
    filePath: p.join('books', '$id.pdf'),
    format: ComicFormat.pdf,
    pageCount: 20,
    fileSize: 3,
    addedAt: DateTime(2026, 11, 1),
    series: series,
    tags: tags,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late AppPaths paths;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('manhua_p3_test_');
    paths = await AppPaths.create(temp);
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  Future<void> seedLibrary(List<ComicBook> books) async {
    await paths.libraryFile.writeAsString(
      jsonEncode({
        'version': 5,
        'settings': <String, Object?>{},
        'library': <String, Object?>{},
        'books': books.map((book) => book.toJson()).toList(),
      }),
    );
  }

  /// Flushes pending writes before teardown removes the temporary folder.
  /// 在测试清理临时目录之前，先落盘未完成的写入。
  Future<void> close(LibraryRepository repository) async {
    await repository.flush();
    repository.dispose();
  }

  Future<void> waitFor(bool Function() condition) async {
    for (var i = 0; i < 100 && !condition(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  test('moves books between folders', () async {
    await seedLibrary([_book(id: 'a'), _book(id: 'b'), _book(id: 'c')]);
    final repository = LibraryRepository(paths);
    await repository.load();
    final [a, b, c] = repository.books;
    final folder = repository.ensureFolder('热血');

    expect(repository.moveBooksToFolder([a, b, a], folder.id), 2);
    expect(repository.folderCounts[folder.id], 2);
    expect(repository.moveBooksToFolder([a], folder.id), 0);
    expect(repository.moveBooksToFolder([c], 'missing-folder'), 0);
    expect(repository.moveBooksToFolder([b], null), 1);
    expect(repository.folderCounts[folder.id], 1);

    await repository.flush();
    await close(repository);
    final reloaded = LibraryRepository(paths);
    await reloaded.load();
    expect(
      {for (final book in reloaded.books) book.id: book.folderId},
      {'a': folder.id, 'b': null, 'c': null},
    );
    await close(reloaded);
  });

  test('sets series and tags in bulk', () async {
    await seedLibrary([
      _book(id: 'a', tags: ['冒险']),
      _book(id: 'b'),
      _book(id: 'c', series: '其他'),
    ]);
    final repository = LibraryRepository(paths);
    await repository.load();
    final [a, b, c] = repository.books;

    expect(repository.setBooksSeries([a, b, a], ' 进击的巨人 '), 2);
    expect(a.series, '进击的巨人');
    expect(repository.seriesCounts['进击的巨人'], 2);
    expect(repository.seriesCounts['其他'], 1);
    expect(repository.setBooksSeries([a], ''), 1);
    expect(a.series, isNull);
    expect(repository.setBooksSeries([b], '进击的巨人'), 0);

    expect(repository.addBooksTags([a, b], ['热血', '热血', ' ', '冒险']), 2);
    expect(a.tags, ['冒险', '热血']);
    expect(b.tags, ['热血', '冒险']);
    expect(repository.tagNames, ['冒险', '热血']);
    expect(repository.addBooksTags([a], ['热血']), 0);
    expect(repository.removeBooksTags([a, b], ['热血']), 2);
    expect(a.tags, ['冒险']);
    expect(b.tags, ['冒险']);
    expect(repository.removeBooksTags([b], ['热血']), 0);
    expect(repository.tagNames, ['冒险']);
    await close(repository);
  });

  test('marks books unread without touching bookmarks', () async {
    await seedLibrary([_book(id: 'a'), _book(id: 'b')]);
    final repository = LibraryRepository(paths);
    await repository.load();
    final [a, b] = repository.books;
    a
      ..lastPage = 7
      ..lastReadAt = DateTime(2026, 1, 1);
    repository.toggleBookmark(a, 3);

    expect(repository.markBooksUnread([a, b]), 1);
    expect(a.lastPage, 0);
    expect(a.hasStarted, false);
    expect(a.isBookmarked(3), isTrue);
    expect(repository.markBooksUnread([a, b]), 0);
    await close(repository);
  });

  test('keeps deleted books restorable until the undo window ends', () async {
    final file = File(p.join(paths.booksDir.path, 'a.pdf'));
    final cover = File(p.join(paths.coversDir.path, 'a.png'));
    await file.writeAsBytes([1, 2, 3]);
    await cover.writeAsBytes([4]);
    final seedA = ComicBook(
      id: 'a',
      title: 'A',
      originalName: 'a.pdf',
      filePath: file.path,
      format: ComicFormat.pdf,
      pageCount: 20,
      fileSize: 3,
      addedAt: DateTime(2026, 11, 1),
      coverPath: cover.path,
    );
    final bFile = File(p.join(paths.booksDir.path, 'b.pdf'));
    await bFile.writeAsBytes([1, 2, 3]);
    final seedB = ComicBook(
      id: 'b',
      title: 'B',
      originalName: 'b.pdf',
      filePath: bFile.path,
      format: ComicFormat.pdf,
      pageCount: 20,
      fileSize: 3,
      addedAt: DateTime(2026, 11, 1),
    );
    await seedLibrary([seedA, seedB]);
    final repository = LibraryRepository(paths);
    await repository.load();
    final [a, b] = repository.books;

    expect(
      repository.deleteBooksLater([a], undoWindow: const Duration(minutes: 1)),
      1,
    );
    expect(repository.books.map((book) => book.id), ['b']);
    expect(await file.exists(), isTrue);
    // Files waiting for an undo are neither reported nor cleaned as orphans.
    // 等待撤销的文件既不算无引用文件，也不会被清理。
    final report = await repository.storageReport();
    expect(report.orphanFiles, 0);
    expect(await repository.cleanupStorage(), 0);
    expect(await file.exists(), isTrue);

    expect(repository.undoPendingDeletion(), 1);
    expect(repository.books.length, 2);
    expect(repository.pendingDeletionCount, 0);

    expect(
      repository.deleteBooksLater([
        a,
        b,
      ], undoWindow: const Duration(minutes: 1)),
      2,
    );
    await repository.commitPendingDeletion();
    expect(await file.exists(), isFalse);
    expect(await bFile.exists(), isFalse);
    expect(await cover.exists(), isFalse);
    expect(repository.undoPendingDeletion(), 0);
    await close(repository);
  });

  test('deletes files automatically when the undo window expires', () async {
    final file = File(p.join(paths.booksDir.path, 'a.pdf'));
    await file.writeAsBytes([1, 2, 3]);
    final seedA = ComicBook(
      id: 'a',
      title: 'A',
      originalName: 'a.pdf',
      filePath: file.path,
      format: ComicFormat.pdf,
      pageCount: 20,
      fileSize: 3,
      addedAt: DateTime(2026, 11, 1),
    );
    await seedLibrary([seedA]);
    final repository = LibraryRepository(paths);
    await repository.load();
    final a = repository.books.single;

    expect(
      repository.deleteBooksLater([
        a,
      ], undoWindow: const Duration(milliseconds: 20)),
      1,
    );
    expect(await file.exists(), isTrue);
    await waitFor(() => !file.existsSync());
    expect(await file.exists(), isFalse);
    expect(repository.pendingDeletionCount, 0);
    await close(repository);
  });

  test('finds the next volume in natural order', () async {
    await seedLibrary([
      _book(id: 'v1', title: '海贼王 第1卷', series: '海贼王'),
      _book(id: 'v10', title: '海贼王 第10卷', series: '海贼王'),
      _book(id: 'v2', title: '海贼王 第2卷', series: '海贼王'),
      _book(id: 'solo', title: '单行本'),
    ]);
    final repository = LibraryRepository(paths);
    await repository.load();
    ComicBook byId(String id) => repository.books.firstWhere((b) => b.id == id);

    expect(repository.nextVolumeInSeries(byId('v1'))?.id, 'v2');
    expect(repository.nextVolumeInSeries(byId('v2'))?.id, 'v10');
    expect(repository.nextVolumeInSeries(byId('v10')), isNull);
    expect(repository.nextVolumeInSeries(byId('solo')), isNull);
    await close(repository);
  });

  test(
    'stores reading preferences per book and keeps global defaults',
    () async {
      await seedLibrary([_book(id: 'a'), _book(id: 'b')]);
      var repository = LibraryRepository(paths);
      await repository.load();
      final [a, b] = repository.books;

      repository
        ..setBookReadingMode(a, ReadingMode.vertical)
        ..setBookRightToLeft(a, true)
        ..setBookDoublePage(a, true)
        ..setSpreadOffset(0, book: a);
      expect(repository.settings.mode, ReadingMode.horizontal);
      expect(repository.settings.rightToLeft, isFalse);
      expect(repository.settings.spreadOffset, 1);
      expect(b.readingMode, isNull);
      repository
        ..setSpreadOffset(99)
        ..setTapZoneWidth(TapZoneWidth.wide)
        ..setAutoCrop(true);
      expect(repository.settings.spreadOffset, maxSpreadOffset);

      await repository.flush();
      await close(repository);
      repository = LibraryRepository(paths);
      await repository.load();
      final [a2, b2] = repository.books;
      expect(a2.readingMode, ReadingMode.vertical);
      expect(a2.rightToLeft, isTrue);
      expect(a2.doublePage, isTrue);
      expect(a2.spreadOffset, 0);
      expect(b2.readingMode, isNull);
      expect(repository.settings.spreadOffset, maxSpreadOffset);
      expect(repository.settings.tapZoneWidth, TapZoneWidth.wide);
      expect(repository.settings.autoCrop, isTrue);

      repository.clearBookReadingPrefs(a2);
      expect(a2.readingMode, isNull);
      expect(a2.spreadOffset, isNull);
      await close(repository);
    },
  );

  test('counts reading time separately from pages', () async {
    // 2026-11-16 is a Monday, so one week later starts a new weekly bucket.
    // 2026-11-16 是周一，八天后已经进入下一周。
    final now = DateTime(2026, 11, 16);
    final stats = ReadingStats();
    stats
      ..addSeconds(90, now)
      ..addSeconds(30, now.add(const Duration(hours: 1)))
      ..addSeconds(0, now);

    expect(stats.totalSeconds, 120);
    expect(stats.secondsToday(now), 120);
    expect(stats.pagesToday(now), 0);
    expect(stats.currentStreak(now), 1);
    // A day with time but no page turns still counts as a reading day.
    // 只有时长、没有翻页的日期同样算作阅读日。
    stats.addSeconds(10, now.add(const Duration(days: 1)));
    expect(stats.currentStreak(now.add(const Duration(days: 1))), 2);
    expect(stats.longestStreak(), 2);
    stats.addPages(5, now.add(const Duration(days: 8)));
    final nextWeek = now.add(const Duration(days: 8));
    expect(stats.secondsThisWeek(nextWeek), 0);
    expect(stats.pagesThisWeek(nextWeek), 5);
    expect(stats.totalSeconds, 130);

    final restored = ReadingStats.fromJson(stats.toJson());
    expect(restored.totalSeconds, 130);
    expect(restored.dailySeconds[ReadingStats.dateKey(now)], 120);
    final other = ReadingStats();
    other.addSeconds(200, now);
    restored.merge(other);
    expect(restored.secondsOn(now), 200);
    expect(
      ReadingStats.fromJson({
        'dailyPages': {'2026-11-16': 3},
      }).totalSeconds,
      0,
    );

    await seedLibrary([_book(id: 'a')]);
    final repository = LibraryRepository(paths);
    await repository.load();
    repository.addReadingTime(45);
    expect(repository.stats.totalSeconds, 45);
    repository.addReadingTime(0);
    expect(repository.stats.totalSeconds, 45);
    await close(repository);
  });

  test('pairs spreads with an offset', () {
    expect(buildSpreads(7), [
      [0],
      [1, 2],
      [3, 4],
      [5, 6],
    ]);
    expect(buildSpreads(7, offset: 0), [
      [0, 1],
      [2, 3],
      [4, 5],
      [6],
    ]);
    expect(buildSpreads(7, offset: 2), [
      [0],
      [1],
      [2, 3],
      [4, 5],
      [6],
    ]);
    expect(buildSpreads(7, offset: 99), buildSpreads(7, offset: 2));
    expect(buildSpreads(0, offset: 0), isEmpty);
    for (final spreads in [
      buildSpreads(9, offset: 0),
      buildSpreads(9, offset: 2),
    ]) {
      final pages = spreads.expand((spread) => spread).toList();
      expect(pages, List.generate(9, (index) => index));
      expect(spreads.every((spread) => spread.length <= 2), isTrue);
    }
  });

  test('reads the new book and reader fields leniently', () {
    final legacy = ComicBook.fromJson({
      'id': 'a',
      'title': 'A',
      'filePath': 'a.pdf',
      'format': 'pdf',
      'pageCount': 20,
    });
    expect(legacy.readingMode, isNull);
    expect(legacy.rightToLeft, isNull);
    expect(legacy.doublePage, isNull);
    expect(legacy.spreadOffset, isNull);

    final invalid = ComicBook.fromJson({
      ...legacy.toJson(),
      'readingMode': 'diagonal',
      'spreadOffset': 7,
    });
    expect(invalid.readingMode, isNull);
    expect(invalid.spreadOffset, isNull);

    final modern = ComicBook.fromJson({
      ...legacy.toJson(),
      'readingMode': 'vertical',
      'rightToLeft': true,
      'doublePage': true,
      'spreadOffset': 2,
    });
    expect(modern.readingMode, ReadingMode.vertical);
    expect(modern.rightToLeft, isTrue);
    expect(modern.doublePage, isTrue);
    expect(modern.spreadOffset, 2);
    final copied = modern.copyWith(title: 'Renamed');
    expect(copied.readingMode, ReadingMode.vertical);
    expect(copied.spreadOffset, 2);

    final oldSettings = ReaderSettings.fromJson({'mode': 'vertical'});
    expect(oldSettings.spreadOffset, 1);
    expect(oldSettings.tapZoneWidth, TapZoneWidth.medium);
    expect(oldSettings.autoCrop, isFalse);
    final newSettings = ReaderSettings.fromJson({
      'spreadOffset': 2,
      'tapZoneWidth': 'narrow',
      'autoCrop': true,
    });
    expect(newSettings.spreadOffset, 2);
    expect(newSettings.tapZoneWidth, TapZoneWidth.narrow);
    expect(newSettings.autoCrop, isTrue);
    expect(TapZoneWidth.narrow.fraction, lessThan(TapZoneWidth.wide.fraction));
    expect(
      ReaderSettings.fromJson(newSettings.toJson()).toJson(),
      newSettings.toJson(),
    );
  });
}
