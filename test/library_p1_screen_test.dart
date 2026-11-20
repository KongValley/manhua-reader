import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manhua_reader/app.dart';
import 'package:manhua_reader/models/comic_book.dart';
import 'package:manhua_reader/models/library_settings.dart';
import 'package:manhua_reader/services/app_paths.dart';
import 'package:manhua_reader/services/library_repository.dart';
import 'package:path/path.dart' as p;

class _Harness {
  late Directory temp;
  late AppPaths paths;
  late LibraryRepository repository;
}

Future<_Harness> _pumpLibrary(
  WidgetTester tester, {
  Size size = const Size(1000, 1600),
}) async {
  final harness = _Harness();

  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;

  await tester.runAsync(() async {
    harness.temp = await Directory.systemTemp.createTemp('manhua_p1_ui_');
    harness.paths = await AppPaths.create(harness.temp);

    Future<ComicBook> seed({
      required String id,
      required String title,
      required String originalName,
      required ComicFormat format,
      required int pageCount,
      required DateTime addedAt,
      int lastPage = 0,
      DateTime? lastReadAt,
      bool missing = false,
    }) async {
      final file = File(
        p.join(harness.paths.booksDir.path, '$id.${format.extension}'),
      );
      if (!missing) await file.writeAsBytes([1, 2, 3]);
      return ComicBook(
        id: id,
        title: title,
        originalName: originalName,
        filePath: file.path,
        format: format,
        pageCount: pageCount,
        fileSize: 3,
        addedAt: addedAt,
        lastPage: lastPage,
        lastReadAt: lastReadAt,
      );
    }

    final books = [
      await seed(
        id: 'seaside',
        title: '海边的咖啡馆',
        originalName: 'seaside.pdf',
        format: ComicFormat.pdf,
        pageCount: 20,
        addedAt: DateTime(2026, 11, 1),
      ),
      await seed(
        id: 'forest',
        title: '山林日记',
        originalName: 'forest.mobi',
        format: ComicFormat.mobi,
        pageCount: 20,
        addedAt: DateTime(2026, 11, 2),
        lastPage: 5,
        lastReadAt: DateTime(2026, 11, 18),
      ),
      await seed(
        id: 'album',
        title: '旧相册',
        originalName: 'album.pdf',
        format: ComicFormat.pdf,
        pageCount: 12,
        addedAt: DateTime(2026, 11, 3),
        missing: true,
      ),
      await seed(
        id: 'finale',
        title: '完结篇',
        originalName: 'finale.pdf',
        format: ComicFormat.pdf,
        pageCount: 10,
        addedAt: DateTime(2026, 11, 4),
        lastPage: 9,
        lastReadAt: DateTime(2026, 11, 19),
      ),
    ];

    await harness.paths.libraryFile.writeAsString(
      jsonEncode({
        'version': 2,
        'settings': <String, Object?>{},
        'library': {'view': 'grid', 'sort': 'recentRead'},
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

Finder _sheet() => find.byType(BottomSheet);

void main() {
  testWidgets('search filters the shelf and shows a no-results state', (
    tester,
  ) async {
    await _pumpLibrary(tester);

    expect(find.text('海边的咖啡馆'), findsOneWidget);
    expect(find.text('山林日记'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '海边');
    await tester.pump();
    expect(find.text('海边的咖啡馆'), findsOneWidget);
    expect(find.text('山林日记'), findsNothing);
    expect(find.text('1 / 4'), findsOneWidget);

    await tester.tap(find.byTooltip('清除搜索'));
    await tester.pump();
    expect(find.text('山林日记'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '不存在');
    await tester.pump();
    expect(find.text('没有匹配的漫画'), findsOneWidget);

    await tester.tap(find.text('清除搜索与筛选'));
    await tester.pump();
    expect(find.text('海边的咖啡馆'), findsOneWidget);
    expect(find.text('山林日记'), findsOneWidget);
  });

  testWidgets('filters by format and reading status, and saves the sort', (
    tester,
  ) async {
    final harness = await _pumpLibrary(tester);

    await tester.tap(find.byTooltip('排序与筛选'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    await tester.tap(find.descendant(of: _sheet(), matching: find.text('书名')));
    await tester.pump();
    await tester.tap(
      find.descendant(of: _sheet(), matching: find.text('MOBI')),
    );
    await tester.pump();
    await tester.tap(find.descendant(of: _sheet(), matching: find.text('应用')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(harness.repository.librarySettings.sort, LibrarySort.title);
    expect(find.text('山林日记'), findsOneWidget);
    expect(find.text('海边的咖啡馆'), findsNothing);
    expect(find.text('清除筛选'), findsOneWidget);

    await tester.tap(find.text('清除筛选'));
    await tester.pump();
    expect(find.text('海边的咖啡馆'), findsOneWidget);

    await tester.tap(find.byTooltip('排序与筛选'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.descendant(of: _sheet(), matching: find.text('已读完')));
    await tester.pump();
    await tester.tap(find.descendant(of: _sheet(), matching: find.text('应用')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('完结篇'), findsOneWidget);
    expect(find.text('海边的咖啡馆'), findsNothing);
    expect(find.text('山林日记'), findsNothing);

    await tester.runAsync(harness.repository.flush);
  });

  testWidgets('toggles between grid and list view', (tester) async {
    final harness = await _pumpLibrary(tester);

    expect(find.byType(SliverGrid), findsOneWidget);
    await tester.tap(find.byTooltip('切换为列表'));
    await tester.pump();

    expect(harness.repository.librarySettings.view, LibraryViewMode.list);
    expect(find.byType(SliverGrid), findsNothing);
    expect(find.byType(SliverList), findsOneWidget);
    expect(find.text('山林日记'), findsOneWidget);

    await tester.tap(find.byTooltip('切换为网格'));
    await tester.pump();
    expect(harness.repository.librarySettings.view, LibraryViewMode.grid);
    expect(find.byType(SliverGrid), findsOneWidget);

    await tester.runAsync(harness.repository.flush);
  });

  testWidgets('selects all visible books and closes batch mode', (
    tester,
  ) async {
    await _pumpLibrary(tester);

    await tester.longPress(find.text('海边的咖啡馆'));
    await tester.pump();
    expect(find.text('已选 1 本'), findsOneWidget);

    await tester.tap(find.text('山林日记'));
    await tester.pump();
    expect(find.text('已选 2 本'), findsOneWidget);

    await tester.tap(find.text('全选'));
    await tester.pump();
    expect(find.text('已选 4 本'), findsOneWidget);
    expect(find.text('取消全选'), findsOneWidget);

    await tester.tap(find.text('删除'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('删除选中的 4 本漫画？'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('已选 4 本'), findsOneWidget);

    await tester.tap(find.byTooltip('退出多选'));
    await tester.pump();
    expect(find.textContaining('已选'), findsNothing);
  });

  testWidgets('marks selected books as read', (tester) async {
    final harness = await _pumpLibrary(tester);

    await tester.longPress(find.text('海边的咖啡馆'));
    await tester.pump();
    await tester.tap(find.text('山林日记'));
    await tester.pump();
    expect(find.text('已选 2 本'), findsOneWidget);

    await tester.tap(find.byTooltip('标记已读'));
    await tester.pump();
    expect(find.textContaining('已选'), findsNothing);

    final seaside = harness.repository.books.firstWhere(
      (book) => book.id == 'seaside',
    );
    final forest = harness.repository.books.firstWhere(
      (book) => book.id == 'forest',
    );
    expect(seaside.progress, 1);
    expect(forest.progress, 1);

    await tester.runAsync(harness.repository.flush);
  });

  testWidgets('renames a book from its action sheet', (tester) async {
    final harness = await _pumpLibrary(tester);

    final title = find.text('海边的咖啡馆');
    final card = find.ancestor(of: title, matching: find.byType(InkWell)).first;
    await tester.tap(
      find.descendant(
        of: card,
        matching: find.byIcon(Icons.more_horiz_rounded),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    await tester.tap(find.text('重命名'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    final field = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(field, '  海边   故事  ');
    await tester.pump();
    await tester.tap(find.text('保存'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    final renamed = harness.repository.books.firstWhere(
      (book) => book.id == 'seaside',
    );
    expect(renamed.title, '海边 故事');
    expect(find.text('海边 故事'), findsOneWidget);

    await tester.runAsync(harness.repository.flush);
  });

  testWidgets('marks missing files and offers to relink them', (tester) async {
    await _pumpLibrary(tester);

    expect(find.text('文件丢失'), findsOneWidget);

    await tester.tap(find.text('旧相册'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('重新定位文件'), findsOneWidget);
    expect(find.text('删除漫画'), findsOneWidget);
    expect(find.textContaining('文件已丢失'), findsOneWidget);

    await tester.tapAt(const Offset(500, 20));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('重新定位文件'), findsNothing);
  });

  testWidgets('opens storage management from the header menu', (tester) async {
    await _pumpLibrary(tester);

    await tester.tap(find.byTooltip('更多'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('关于漫阅'), findsOneWidget);

    await tester.tap(find.text('存储管理'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('存储管理'), findsOneWidget);
    expect(find.text('应用内副本、封面与缓存'), findsOneWidget);
  });

  testWidgets('fits the selection bar on a narrow phone', (tester) async {
    await _pumpLibrary(tester, size: const Size(360, 800));

    await tester.longPress(find.text('完结篇').last);
    await tester.pump();

    expect(find.text('已选 1 本'), findsOneWidget);
    expect(find.text('全选'), findsOneWidget);
    expect(find.text('已读'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);
  });
}
