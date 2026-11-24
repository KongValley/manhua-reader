import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manhua_reader/app.dart';
import 'package:manhua_reader/formats/comic_source.dart';
import 'package:manhua_reader/formats/comic_source_factory.dart';
import 'package:manhua_reader/models/comic_book.dart';
import 'package:manhua_reader/models/reading_stats.dart';
import 'package:manhua_reader/models/toc_entry.dart';
import 'package:manhua_reader/screens/reader_screen.dart';
import 'package:manhua_reader/services/app_paths.dart';
import 'package:manhua_reader/services/library_repository.dart';
import 'package:manhua_reader/theme/app_theme.dart';
import 'package:path/path.dart' as p;

class _FakeSource extends ComicSource {
  final List<ui.Image> images = [
    for (final color in [Colors.red, Colors.blue, Colors.green])
      _makeImage(color),
  ];

  @override
  int get pageCount => images.length;

  @override
  Size pageSize(int index) => const Size(120, 168);

  @override
  Widget buildPage(
    BuildContext context,
    int index, {
    ValueChanged<ui.Image>? onImage,
  }) {
    onImage?.call(images[index]);
    return RawImage(image: images[index], fit: BoxFit.fill);
  }

  @override
  Widget buildThumbnail(BuildContext context, int index) =>
      buildPage(context, index);

  @override
  Future<List<TocEntry>> loadToc() async => const [];

  @override
  Future<void> dispose() async {
    for (final image in images) {
      image.dispose();
    }
  }

  static ui.Image _makeImage(Color color) {
    final recorder = ui.PictureRecorder();
    Canvas(recorder)
        .drawRect(const Rect.fromLTWH(0, 0, 120, 168), Paint()..color = color);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(120, 168);
    picture.dispose();
    return image;
  }
}

void main() {
  testWidgets(
    'shows daily reading strip on shelf, book total duration, and rich stats log',
    (tester) async {
      late Directory temp;
      late AppPaths paths;
      late LibraryRepository repository;
      final now = DateTime.now();
      final yesterday = now.subtract(const Duration(days: 1));

      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1.0;

      await tester.runAsync(() async {
        temp = await Directory.systemTemp.createTemp('manhua_time_ui_');
        paths = await AppPaths.create(temp);
        final bookFile = File(p.join(paths.booksDir.path, 'b1.pdf'));
        await bookFile.writeAsBytes([1, 2, 3]);
        final secondFile = File(p.join(paths.booksDir.path, 'b2.pdf'));
        await secondFile.writeAsBytes([1, 2, 3]);

        final stats = ReadingStats()
          ..addSeconds(
            900,
            DateTime(now.year, now.month, now.day, 20, 30),
            bookId: 'b1',
            bookTitle: '海贼王 第1卷',
          )
          ..addPages(12, now, bookId: 'b1')
          ..addSeconds(
            600,
            DateTime(yesterday.year, yesterday.month, yesterday.day, 21, 15),
            bookId: 'b2',
            bookTitle: '日常',
          );

        final books = [
          ComicBook(
            id: 'b1',
            title: '海贼王 第1卷',
            originalName: 'b1.pdf',
            filePath: bookFile.path,
            format: ComicFormat.pdf,
            pageCount: 20,
            fileSize: 3,
            addedAt: DateTime(2026, 11, 1),
          ),
          ComicBook(
            id: 'b2',
            title: '日常',
            originalName: 'b2.pdf',
            filePath: secondFile.path,
            format: ComicFormat.pdf,
            pageCount: 20,
            fileSize: 3,
            addedAt: DateTime(2026, 11, 2),
          ),
        ];

        await paths.libraryFile.writeAsString(
          jsonEncode({
            'version': 5,
            'settings': <String, Object?>{},
            'library': <String, Object?>{},
            'stats': stats.toJson(),
            'books': books.map((book) => book.toJson()).toList(),
          }),
        );

        repository = LibraryRepository(paths);
        await repository.load();
      });

      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(() async {
          await repository.flush();
          repository.dispose();
          if (await temp.exists()) await temp.delete(recursive: true);
        });
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(ManhuaApp(repository: repository));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      // Shelf strip shows today's reading duration and opens the stats sheet.
      // 书架顶部提示条展示今日阅读时长，点按可打开阅读统计面板。
      expect(find.text('今日已看 15 分钟'), findsOneWidget);
      await tester.tap(find.text('今日已看 15 分钟'));
      await tester.pumpAndSettle();

      expect(find.text('每日阅读目标'), findsOneWidget);
      expect(find.text('每日时间记录'), findsOneWidget);
      expect(find.text('按漫画分布'), findsOneWidget);
      expect(find.text('阅读时段'), findsOneWidget);
      expect(find.text('共 2 天有记录'), findsOneWidget);

      // Set a 15-minute goal and verify both sheet and shelf mark it reached.
      // 设定 15 分钟每日目标，验证统计面板与书架同步显示已达标。
      await tester.tap(find.text('设定目标'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('15 分钟'),
        ),
      );
      await tester.pump();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('保存'),
        ),
      );
      await tester.pumpAndSettle();

      expect(repository.stats.dailyGoalMinutes, 15);
      expect(find.text('今日目标已达成'), findsOneWidget);

      // Toggle 7-day chart between 时长 and 页数, and expand yesterday's log.
      // 在 7 天柱状图切换时长/页数，并展开昨天的每日记录。
      expect(find.text('15分'), findsOneWidget);
      await tester.tap(find.text('页数'));
      await tester.pump();
      expect(find.text('15分'), findsNothing);
      expect(find.text('12'), findsNWidgets(4));
      await tester.tap(find.text('时长'));
      await tester.pump();
      expect(find.text('15分'), findsOneWidget);

      await tester.ensureVisible(find.text('昨天'));
      await tester.tap(find.text('昨天'));
      await tester.pumpAndSettle();
      expect(find.text('10 分钟'), findsWidgets);
      expect(find.text('21:05–21:15'), findsOneWidget);

      // Dismiss sheet and verify bookshelf strip + book action metadata.
      // 关闭面板后检查书架条和单本书操作菜单的累计时长显示。
      await tester.tapAt(const Offset(200, 20));
      await tester.pumpAndSettle();
      expect(find.text('已达成每日 15 分钟目标'), findsOneWidget);

      final title = find.text('海贼王 第1卷').last;
      final card = find.ancestor(of: title, matching: find.byType(InkWell)).first;
      await tester.tap(
        find.descendant(
          of: card,
          matching: find.byIcon(Icons.more_horiz_rounded),
        ),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(find.text('PDF · 20 页 · 3 B · 已看 15 分钟'), findsOneWidget);
    },
  );

  testWidgets('reader displays today reading badge and opens stats sheet', (
    tester,
  ) async {
    await tester.runAsync(() async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      ComicSourceFactory.debugOpener = (_) async => _FakeSource();
      addTearDown(() => ComicSourceFactory.debugOpener = null);

      final temp = await Directory.systemTemp.createTemp('manhua_reader_time_');
      final paths = await AppPaths.create(temp);
      final file = File(p.join(paths.booksDir.path, 'v1.pdf'));
      await file.writeAsBytes([1, 2, 3]);
      final book = ComicBook(
        id: 'v1',
        title: '测试第1卷',
        originalName: 'v1.pdf',
        filePath: file.path,
        format: ComicFormat.pdf,
        pageCount: 3,
        fileSize: 3,
        addedAt: DateTime(2026, 11, 1),
      );
      await paths.libraryFile.writeAsString(
        jsonEncode({
          'version': 5,
          'settings': <String, Object?>{},
          'library': <String, Object?>{},
          'books': [book.toJson()],
        }),
      );
      final repository = LibraryRepository(paths);
      await repository.load();
      final loaded = repository.books.single;
      repository.addReadingTime(120, book: loaded);

      try {
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(),
            home: ReaderScreen(book: loaded, repository: repository),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('今日已看 2 分钟'), findsOneWidget);
        await tester.tap(find.text('今日已看 2 分钟'));
        await tester.pumpAndSettle();

        expect(find.text('阅读统计'), findsOneWidget);
        expect(find.text('每日时间记录'), findsOneWidget);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        for (var i = 0; i < 8; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 25));
          await tester.pump();
        }
        await repository.flush().timeout(
          const Duration(seconds: 3),
          onTimeout: () {},
        );
        repository.dispose();
        if (await temp.exists()) await temp.delete(recursive: true);
      }
    });
  });
}
