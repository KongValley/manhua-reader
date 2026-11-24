import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manhua_reader/app.dart';
import 'package:manhua_reader/models/comic_book.dart';
import 'package:manhua_reader/models/reading_stats.dart';
import 'package:manhua_reader/services/app_paths.dart';
import 'package:manhua_reader/services/library_repository.dart';
import 'package:manhua_reader/theme/app_theme.dart';
import 'package:manhua_reader/utils/adaptive_layout.dart';
import 'package:path/path.dart' as p;

Future<LibraryRepository> _createTestRepository(
  Directory temp, {
  String viewMode = 'list',
}) async {
  final paths = await AppPaths.create(temp);
  final now = DateTime.now();
  final stats = ReadingStats(dailyGoalMinutes: 15)
    ..addSeconds(
      300,
      DateTime(now.year, now.month, now.day, 20),
      bookId: 'b1',
      bookTitle: '测试连载',
    );

  final file1 = File(p.join(paths.booksDir.path, 'b1.pdf'))..writeAsBytesSync([1]);
  final file2 = File(p.join(paths.booksDir.path, 'b2.pdf'))..writeAsBytesSync([1]);
  final books = [
    ComicBook(
      id: 'b1',
      title: '测试连载',
      originalName: 'b1.pdf',
      filePath: file1.path,
      format: ComicFormat.pdf,
      pageCount: 20,
      fileSize: 1,
      addedAt: DateTime(2026, 11, 1),
      lastPage: 5,
      lastReadAt: now,
    ),
    ComicBook(
      id: 'b2',
      title: '第二部漫画',
      originalName: 'b2.pdf',
      filePath: file2.path,
      format: ComicFormat.pdf,
      pageCount: 30,
      fileSize: 1,
      addedAt: DateTime(2026, 11, 2),
    ),
  ];

  await paths.libraryFile.writeAsString(
    jsonEncode({
      'version': 5,
      'settings': <String, Object?>{},
      'library': <String, Object?>{'view': viewMode},
      'stats': stats.toJson(),
      'books': books.map((book) => book.toJson()).toList(),
    }),
  );

  final repository = LibraryRepository(paths);
  await repository.load();
  return repository;
}

void main() {
  test('AdaptiveLayout breakpoints adapt cleanly across screen widths', () {
    expect(AdaptiveLayout.classify(390), ScreenClass.compact);
    expect(AdaptiveLayout.classify(680), ScreenClass.medium);
    expect(AdaptiveLayout.classify(1000), ScreenClass.expanded);

    expect(AdaptiveLayout.bookColumns(390), 2);
    expect(AdaptiveLayout.bookColumns(560), 3);
    expect(AdaptiveLayout.bookColumns(760), 4);
    expect(AdaptiveLayout.bookColumns(1000), 5);
    expect(AdaptiveLayout.bookColumns(1280), 6);

    expect(AdaptiveLayout.seriesColumns(390), 2);
    expect(AdaptiveLayout.seriesColumns(640), 3);
    expect(AdaptiveLayout.seriesColumns(900), 4);
    expect(AdaptiveLayout.seriesColumns(1200), 5);

    expect(AdaptiveLayout.horizontalPadding(390), 20);
    expect(AdaptiveLayout.horizontalPadding(700), 24);
    expect(AdaptiveLayout.horizontalPadding(1024), 32);
  });

  testWidgets('AdaptiveSheetShell constrains width on tablets and allows barrier dismiss', (
    tester,
  ) async {
    Future<void> pumpSheetAt(Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () {
                    showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => const AdaptiveSheetShell(
                        maxWidth: 600,
                        child: SizedBox(
                          key: ValueKey('adaptive_sheet_body'),
                          height: 240,
                          child: Center(child: Text('自适应面板')),
                        ),
                      ),
                    );
                  },
                  child: const Text('打开面板'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开面板'));
      await tester.pumpAndSettle();
    }

    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await pumpSheetAt(const Size(1000, 800));
    final tabletSize = tester.getSize(
      find.byKey(const ValueKey('adaptive_sheet_body')),
    );
    expect(tabletSize.width, lessThanOrEqualTo(600));
    expect(tabletSize.width, greaterThan(400));

    // Barrier outside the centered maxWidth shell remains tappable to dismiss.
    await tester.tapAt(const Offset(50, 200));
    await tester.pumpAndSettle();
    expect(find.text('自适应面板'), findsNothing);

    await pumpSheetAt(const Size(420, 800));
    final phoneSize = tester.getSize(
      find.byKey(const ValueKey('adaptive_sheet_body')),
    );
    expect(phoneSize.width, greaterThan(400));
  });

  testWidgets(
    'LibraryScreen and ReadingStatsSheet adapt between tablet and phone viewports',
    (tester) async {
      Future<void> verifyAtViewport(Size size, {required bool expectWide}) async {
        late Directory temp;
        late LibraryRepository repository;

        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;

        await tester.runAsync(() async {
          temp = await Directory.systemTemp.createTemp('manhua_adaptive_');
          repository = await _createTestRepository(temp);
        });

        try {
          await tester.pumpWidget(ManhuaApp(repository: repository));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));

          final dailyRect = tester.getRect(find.text('今日已看 5 分钟').first);
          final continueRect = tester.getRect(find.text('继续阅读').first);
          final book1Rect = tester.getRect(find.text('测试连载').last);
          final book2Rect = tester.getRect(find.text('第二部漫画').first);

          if (expectWide) {
            // Wide hero row aligns Continue Reading and Daily Strip horizontally.
            expect((dailyRect.center.dy - continueRect.center.dy).abs(), lessThan(40));
            expect((dailyRect.center.dx - continueRect.center.dx).abs(), greaterThan(200));
            // 2-column list view places books side-by-side.
            expect((book1Rect.center.dy - book2Rect.center.dy).abs(), lessThan(25));
            expect((book1Rect.center.dx - book2Rect.center.dx).abs(), greaterThan(200));
          } else {
            // Phone layout stacks hero cards and single-column list items vertically.
            expect((dailyRect.center.dy - continueRect.center.dy).abs(), greaterThan(40));
            expect((book1Rect.center.dy - book2Rect.center.dy).abs(), greaterThan(50));
            expect((book1Rect.center.dx - book2Rect.center.dx).abs(), lessThan(20));
          }

          await tester.tap(find.text('今日已看 5 分钟'));
          await tester.pumpAndSettle();

          final todayCard = tester.getCenter(find.text('今日阅读').first);
          final weekCard = tester.getCenter(find.text('本周阅读').first);
          final streakCard = tester.getCenter(find.text('连续阅读').first);
          final totalCard = tester.getCenter(find.text('累计阅读').first);

          if (expectWide) {
            expect((todayCard.dy - weekCard.dy).abs(), lessThan(4));
            expect((todayCard.dy - streakCard.dy).abs(), lessThan(4));
            expect((todayCard.dy - totalCard.dy).abs(), lessThan(4));
            expect(todayCard.dx, lessThan(weekCard.dx));
            expect(weekCard.dx, lessThan(streakCard.dx));
            expect(streakCard.dx, lessThan(totalCard.dx));
          } else {
            expect((todayCard.dy - weekCard.dy).abs(), lessThan(4));
            expect((streakCard.dy - totalCard.dy).abs(), lessThan(4));
            expect(streakCard.dy - todayCard.dy, greaterThan(40));
          }

          // Tablet backdrop dismiss works cleanly from top margin.
          if (expectWide) {
            await tester.tapAt(const Offset(500, 20));
            await tester.pumpAndSettle();
            expect(find.text('年度阅读热力图'), findsNothing);
          }
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.runAsync(() async {
            await repository.flush().timeout(
                  const Duration(seconds: 3),
                  onTimeout: () {},
                );
            repository.dispose();
            if (await temp.exists()) await temp.delete(recursive: true);
          });
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        }
      }

      await verifyAtViewport(const Size(1000, 900), expectWide: true);
      await verifyAtViewport(const Size(420, 900), expectWide: false);
    },
  );

  testWidgets('keeps import FAB clear of Android taskbar / navigation bar inset', (
    tester,
  ) async {
    late Directory temp;
    late LibraryRepository repository;

    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    tester.view.padding = const FakeViewPadding(bottom: 80);
    tester.view.viewPadding = const FakeViewPadding(bottom: 80);

    await tester.runAsync(() async {
      temp = await Directory.systemTemp.createTemp('manhua_fab_inset_');
      repository = await _createTestRepository(temp);
    });

    try {
      await tester.pumpWidget(ManhuaApp(repository: repository));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final fabRect = tester.getRect(find.text('导入'));
      expect(fabRect.bottom, lessThanOrEqualTo(800 - 80 - 16));
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        await repository.flush().timeout(
              const Duration(seconds: 3),
              onTimeout: () {},
            );
        repository.dispose();
        if (await temp.exists()) await temp.delete(recursive: true);
      });
      tester.view.resetPadding();
      tester.view.resetViewPadding();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }
  });
}
