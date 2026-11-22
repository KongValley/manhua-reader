import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manhua_reader/app.dart';
import 'package:manhua_reader/models/comic_book.dart';
import 'package:manhua_reader/services/app_paths.dart';
import 'package:manhua_reader/services/library_repository.dart';
import 'package:path/path.dart' as p;

class _Harness {
  late Directory temp;
  late AppPaths paths;
  late LibraryRepository repository;
}

Future<_Harness> _pumpLibrary(WidgetTester tester) async {
  final harness = _Harness();
  tester.view.physicalSize = const Size(1000, 1600);
  tester.view.devicePixelRatio = 1.0;

  await tester.runAsync(() async {
    harness.temp = await Directory.systemTemp.createTemp('manhua_p2_ui_');
    harness.paths = await AppPaths.create(harness.temp);

    Future<ComicBook> seed({
      required String id,
      required String title,
      required String originalName,
      required DateTime addedAt,
      int pageCount = 20,
      int lastPage = 0,
      DateTime? lastReadAt,
      String? series,
      List<String> tags = const [],
      bool favorite = false,
      bool pinned = false,
    }) async {
      final file = File(p.join(harness.paths.booksDir.path, '$id.pdf'));
      await file.writeAsBytes([1, 2, 3]);
      return ComicBook(
        id: id,
        title: title,
        originalName: originalName,
        filePath: file.path,
        format: ComicFormat.pdf,
        pageCount: pageCount,
        fileSize: 3,
        addedAt: addedAt,
        lastPage: lastPage,
        lastReadAt: lastReadAt,
        series: series,
        tags: tags,
        favorite: favorite,
        pinned: pinned,
      );
    }

    final books = [
      await seed(
        id: 'one-piece-1',
        title: '海贼王 第1卷',
        originalName: 'one-piece-1.pdf',
        addedAt: DateTime(2026, 11, 1),
        lastPage: 3,
        lastReadAt: DateTime(2026, 11, 20),
        series: '海贼王',
        tags: ['冒险'],
        favorite: true,
      ),
      await seed(
        id: 'one-piece-2',
        title: '海贼王 第2卷',
        originalName: 'one-piece-2.pdf',
        addedAt: DateTime(2026, 11, 2),
        series: '海贼王',
        tags: ['热血'],
      ),
      await seed(
        id: 'daily',
        title: '日常',
        originalName: 'daily.pdf',
        addedAt: DateTime(2026, 11, 3),
        tags: ['日常'],
      ),
    ];

    await harness.paths.libraryFile.writeAsString(
      jsonEncode({
        'version': 3,
        'settings': <String, Object?>{},
        'library': {'view': 'grid', 'sort': 'recentRead'},
        'stats': <String, Object?>{},
        'books': books.map((book) => book.toJson()).toList(),
      }),
    );

    harness.repository = LibraryRepository(harness.paths);
    await harness.repository.load();
  });

  await tester.pumpWidget(ManhuaApp(repository: harness.repository));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));

  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      await harness.repository.flush();
      harness.repository.dispose();
      if (await harness.temp.exists()) {
        await harness.temp.delete(recursive: true);
      }
    });
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  return harness;
}

Finder _dialog() => find.byType(AlertDialog);

Future<void> _openFilterSheet(WidgetTester tester) async {
  await tester.tap(find.byTooltip('排序与筛选'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

Future<void> _applyFilters(WidgetTester tester) async {
  await tester.tap(find.text('应用'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

void main() {
  testWidgets('filters by favorites, series and tags, and searches tags', (
    tester,
  ) async {
    await _pumpLibrary(tester);

    await _openFilterSheet(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('只看收藏'),
      ),
    );
    await tester.pump();
    await _applyFilters(tester);
    expect(find.text('海贼王 第1卷'), findsOneWidget);
    expect(find.text('海贼王 第2卷'), findsNothing);
    expect(find.text('日常'), findsNothing);

    await tester.tap(find.text('清除筛选'));
    await tester.pump();
    expect(find.text('海贼王 第2卷'), findsOneWidget);

    await _openFilterSheet(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('海贼王 (2)'),
      ),
    );
    await tester.pump();
    await _applyFilters(tester);
    expect(find.text('海贼王 第1卷'), findsOneWidget);
    expect(find.text('海贼王 第2卷'), findsOneWidget);
    expect(find.text('日常'), findsNothing);

    await tester.tap(find.text('清除筛选'));
    await tester.pump();
    await _openFilterSheet(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('#冒险 (1)'),
      ),
    );
    await tester.pump();
    await _applyFilters(tester);
    expect(find.text('海贼王 第1卷'), findsOneWidget);
    expect(find.text('海贼王 第2卷'), findsNothing);

    await tester.tap(find.text('清除筛选'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '冒险');
    await tester.pump();
    expect(find.text('海贼王 第1卷'), findsOneWidget);
    expect(find.text('海贼王 第2卷'), findsNothing);
  });

  testWidgets(
    'closes selection after unfavoriting under the favorites filter',
    (tester) async {
      final harness = await _pumpLibrary(tester);

      await _openFilterSheet(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('只看收藏'),
        ),
      );
      await tester.pump();
      await _applyFilters(tester);
      expect(find.text('海贼王 第1卷'), findsOneWidget);

      await tester.longPress(find.text('海贼王 第1卷'));
      await tester.pump();
      expect(find.text('已选 1 本'), findsOneWidget);

      await tester.tap(find.byTooltip('取消收藏选中的漫画'));
      await tester.pump();
      expect(find.textContaining('已选'), findsNothing);
      expect(find.text('海贼王 第1卷'), findsNothing);
      final book = harness.repository.books.firstWhere(
        (item) => item.id == 'one-piece-1',
      );
      expect(book.favorite, isFalse);

      await tester.runAsync(harness.repository.flush);
    },
  );

  testWidgets('opens the merged series screen and volume list', (tester) async {
    await _pumpLibrary(tester);

    await tester.tap(find.byTooltip('更多'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text('系列合集'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('系列合集'), findsOneWidget);
    expect(find.text('海贼王'), findsOneWidget);
    expect(find.text('2 卷'), findsOneWidget);

    await tester.tap(find.text('海贼王'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('海贼王 第1卷'), findsOneWidget);
    expect(find.text('海贼王 第2卷'), findsOneWidget);
    expect(find.text('日常'), findsNothing);
  });

  testWidgets('edits series and tags from the action sheet', (tester) async {
    final harness = await _pumpLibrary(tester);

    final title = find.text('海贼王 第1卷').last;
    final card = find.ancestor(of: title, matching: find.byType(InkWell)).first;
    await tester.tap(
      find.descendant(
        of: card,
        matching: find.byIcon(Icons.more_horiz_rounded),
      ),
      warnIfMissed: false,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    await tester.tap(find.text('系列与标签'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    final fields = find.descendant(
      of: _dialog(),
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.at(0), '新系列');
    await tester.enterText(fields.at(1), '测试标签');
    await tester.pump();
    await tester.tap(find.byTooltip('添加标签'));
    await tester.pump();
    expect(find.text('测试标签'), findsWidgets);

    await tester.tap(find.text('保存'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    final book = harness.repository.books.firstWhere(
      (item) => item.id == 'one-piece-1',
    );
    expect(book.series, '新系列');
    expect(book.tags, contains('测试标签'));

    await tester.runAsync(harness.repository.flush);
  });

  testWidgets('toggles favorite and pinned from the action sheet', (
    tester,
  ) async {
    final harness = await _pumpLibrary(tester);

    Future<void> openActions() async {
      final title = find.text('海贼王 第2卷');
      final card = find
          .ancestor(of: title, matching: find.byType(InkWell))
          .first;
      await tester.tap(
        find.descendant(
          of: card,
          matching: find.byIcon(Icons.more_horiz_rounded),
        ),
        warnIfMissed: false,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
    }

    await openActions();
    await tester.tap(find.text('收藏'));
    await tester.pump();
    var book = harness.repository.books.firstWhere(
      (item) => item.id == 'one-piece-2',
    );
    expect(book.favorite, isTrue);

    await openActions();
    expect(find.text('已收藏'), findsOneWidget);
    await tester.tap(find.text('置顶'));
    await tester.pump();
    book = harness.repository.books.firstWhere(
      (item) => item.id == 'one-piece-2',
    );
    expect(book.pinned, isTrue);
    expect(harness.repository.books.first.id, 'one-piece-2');

    await tester.runAsync(harness.repository.flush);
  });

  testWidgets('toggles favorite and pin from card and list quick actions', (
    tester,
  ) async {
    final harness = await _pumpLibrary(tester);

    await tester.tap(find.byTooltip('收藏《海贼王 第2卷》'));
    await tester.pump();
    var book = harness.repository.books.firstWhere(
      (item) => item.id == 'one-piece-2',
    );
    expect(book.favorite, isTrue);
    expect(find.byTooltip('取消收藏《海贼王 第2卷》'), findsOneWidget);

    await tester.tap(find.byTooltip('置顶《海贼王 第2卷》'));
    await tester.pump();
    book = harness.repository.books.firstWhere(
      (item) => item.id == 'one-piece-2',
    );
    expect(book.pinned, isTrue);
    expect(harness.repository.books.first.id, 'one-piece-2');

    await tester.tap(find.byTooltip('切换为列表'));
    await tester.pump();
    await tester.tap(find.byTooltip('收藏《日常》'));
    await tester.pump();
    book = harness.repository.books.firstWhere((item) => item.id == 'daily');
    expect(book.favorite, isTrue);
    expect(find.byTooltip('取消收藏《日常》'), findsOneWidget);

    await tester.runAsync(harness.repository.flush);
  });

  testWidgets('batch favorites and pins selected books', (tester) async {
    final harness = await _pumpLibrary(tester);

    await tester.longPress(find.text('海贼王 第2卷'));
    await tester.pump();
    await tester.tap(find.text('日常'));
    await tester.pump();
    expect(find.text('已选 2 本'), findsOneWidget);

    await tester.tap(find.text('收藏'));
    await tester.pump();
    var second = harness.repository.books.firstWhere(
      (item) => item.id == 'one-piece-2',
    );
    var daily = harness.repository.books.firstWhere(
      (item) => item.id == 'daily',
    );
    expect(second.favorite, isTrue);
    expect(daily.favorite, isTrue);
    expect(find.text('已收藏 2 本'), findsOneWidget);
    expect(find.text('已选 2 本'), findsOneWidget);

    await tester.tap(find.text('收藏'));
    await tester.pump();
    second = harness.repository.books.firstWhere(
      (item) => item.id == 'one-piece-2',
    );
    daily = harness.repository.books.firstWhere((item) => item.id == 'daily');
    expect(second.favorite, isFalse);
    expect(daily.favorite, isFalse);
    expect(
      harness.repository.books
          .firstWhere((item) => item.id == 'one-piece-1')
          .favorite,
      isTrue,
    );

    await tester.tap(find.text('置顶'));
    await tester.pump();
    expect(
      harness.repository.books.take(2).every((book) => book.pinned),
      isTrue,
    );
    expect(find.text('已置顶 2 本'), findsOneWidget);

    await tester.tap(find.text('置顶'));
    await tester.pump();
    expect(harness.repository.books.any((book) => book.pinned), isFalse);
    expect(find.text('已选 2 本'), findsOneWidget);

    await tester.tap(find.byTooltip('退出多选'));
    await tester.pump();
    expect(find.textContaining('已选'), findsNothing);

    await tester.runAsync(harness.repository.flush);
  });

  testWidgets('opens reading statistics and backup panels', (tester) async {
    await _pumpLibrary(tester);

    await tester.tap(find.byTooltip('更多'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text('阅读统计'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('阅读统计'), findsOneWidget);
    expect(find.text('今日阅读'), findsOneWidget);
    expect(find.text('本周阅读'), findsOneWidget);
    expect(find.text('最近 7 天'), findsOneWidget);

    await tester.tapAt(const Offset(500, 20));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    await tester.tap(find.byTooltip('更多'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text('备份与恢复'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('导出书架数据'), findsOneWidget);
    expect(find.text('导出完整备份'), findsOneWidget);
    expect(find.text('从备份恢复'), findsOneWidget);
  });

  testWidgets('shows the desktop drag import overlay', (tester) async {
    await _pumpLibrary(tester);
    const codec = StandardMethodCodec();

    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'desktop_drop',
      codec.encodeMethodCall(const MethodCall('entered', <double>[500, 800])),
      (_) {},
    );
    await tester.pump();
    expect(find.text('松开以导入漫画'), findsOneWidget);

    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'desktop_drop',
      codec.encodeMethodCall(const MethodCall('exited')),
      (_) {},
    );
    await tester.pump();
    expect(find.text('松开以导入漫画'), findsNothing);
  });
}
