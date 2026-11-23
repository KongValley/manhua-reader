import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manhua_reader/formats/comic_source.dart';
import 'package:manhua_reader/formats/comic_source_factory.dart';
import 'package:manhua_reader/models/comic_book.dart';
import 'package:manhua_reader/models/reader_settings.dart';
import 'package:manhua_reader/models/toc_entry.dart';
import 'package:manhua_reader/screens/reader_screen.dart';
import 'package:manhua_reader/services/app_paths.dart';
import 'package:manhua_reader/services/library_repository.dart';
import 'package:manhua_reader/theme/app_theme.dart';
import 'package:manhua_reader/widgets/slider_ticks.dart';
import 'package:path/path.dart' as p;

/// A five-page comic whose pages are flat colours, so no decoding is needed.
/// 五页的纯色漫画，无需图片解码。
class _FakeSource extends ComicSource {
  final List<ui.Image> images = [
    for (final color in [
      Colors.red,
      Colors.blue,
      Colors.green,
      Colors.pink,
      Colors.orange,
    ])
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
  Future<List<TocEntry>> loadToc() async => const [
    TocEntry(title: '第一章 起航', page: 0),
    TocEntry(title: '第二章 风暴', page: 3),
  ];

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

class _Shelf {
  late Directory temp;
  late LibraryRepository repository;
  late ComicBook volume1;
  late ComicBook volume2;
  final sources = <_FakeSource>[];
}

ComicBook _volume(String id, String title, String dir) => ComicBook(
  id: id,
  title: title,
  originalName: '$id.pdf',
  filePath: p.join(dir, '$id.pdf'),
  format: ComicFormat.pdf,
  pageCount: 5,
  fileSize: 3,
  addedAt: DateTime(2026, 11, 1),
  lastPage: id == 'v1' ? 3 : 0,
  lastReadAt: DateTime(2026, 11, 20),
  series: '测试',
);

String _counter(int page) => '$page / 5';

/// Opens the reader on volume 1, runs [body], then closes it.
///
/// Everything runs inside one real-async scope: the repository writes files
/// for real while frame callbacks run on the fake clock, so closing alternates
/// real waits with frame pumps until the save queue has drained.
/// 在第 1 卷上打开阅读器、执行 [body] 后关闭。
///
/// 整个流程位于同一个真实异步作用域：仓库真实写文件，而帧回调运行在假时钟上，
/// 因此关闭时交替进行真实等待与帧推进，直到保存队列排空。
Future<void> _withReader(
  WidgetTester tester,
  Future<void> Function(_Shelf shelf) body, {
  void Function(_Shelf shelf)? prepare,
}) async {
  await tester.runAsync(() async {
    final shelf = _Shelf();
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    ComicSourceFactory.debugOpener = (book) async {
      final source = _FakeSource();
      shelf.sources.add(source);
      return source;
    };
    addTearDown(() => ComicSourceFactory.debugOpener = null);

    shelf.temp = await Directory.systemTemp.createTemp('manhua_reader_ui_');
    final paths = await AppPaths.create(shelf.temp);
    await File(p.join(paths.booksDir.path, 'v2.pdf')).writeAsBytes([1, 2, 3]);
    await paths.libraryFile.writeAsString(
      jsonEncode({
        'version': 5,
        'settings': <String, Object?>{},
        'library': <String, Object?>{},
        'books': [
          _volume('v1', '测试 第1卷', paths.booksDir.path).toJson(),
          _volume('v2', '测试 第2卷', paths.booksDir.path).toJson(),
        ],
      }),
    );
    shelf.repository = LibraryRepository(paths);
    await shelf.repository.load();
    // The reader mutates the loaded instances, so keep references to those.
    // 阅读器修改的是加载后的实例，因此引用加载后的对象。
    shelf.volume1 = shelf.repository.books.firstWhere((b) => b.id == 'v1');
    shelf.volume2 = shelf.repository.books.firstWhere((b) => b.id == 'v2');

    prepare?.call(shelf);
    try {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: ReaderScreen(book: shelf.volume1, repository: shelf.repository),
        ),
      );
      await tester.pumpAndSettle();
      await body(shelf);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      for (var i = 0; i < 8; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
        await tester.pump();
      }
      await shelf.repository.flush().timeout(
        const Duration(seconds: 3),
        onTimeout: () {},
      );
      shelf.repository.dispose();
      if (await shelf.temp.exists()) {
        await shelf.temp.delete(recursive: true);
      }
    }
  });
}

Future<void> _tapPage(WidgetTester tester, Offset offset) async {
  await tester.tapAt(offset);
  // Let single-tap recognition finish before settling the turn animation.
  // 等单击识别完成，再等待翻页动画结束。
  await Future<void>.delayed(const Duration(milliseconds: 325));
  await tester.pump();
}

void main() {
  testWidgets('names the current chapter and ticks bookmarks on the slider', (
    tester,
  ) async {
    await _withReader(tester, (shelf) async {
      // Page 4 belongs to the chapter that starts on page 4.
      // 第 4 页属于从第 4 页开始的章节。
      expect(find.text('第 4 / 5 页 · 第二章 风暴'), findsOneWidget);
      expect(find.byType(SliderTicks), findsNothing);

      await tester.tap(find.byTooltip('添加书签'));
      await tester.pump();
      expect(shelf.volume1.isBookmarked(3), isTrue);
      expect(find.byType(SliderTicks), findsOneWidget);
      await tester.tap(find.byTooltip('移除书签'));
      await tester.pump();
      expect(find.byType(SliderTicks), findsNothing);
    });
  });

  testWidgets('turns pages by tap zones of the configured width', (
    tester,
  ) async {
    await _withReader(tester, (shelf) async {
      expect(find.text(_counter(4)), findsOneWidget);

      // The right zone turns forward with the default width.
      // 默认宽度下，点按右侧区域向后翻页。
      await _tapPage(tester, const Offset(760, 300));
      await tester.pumpAndSettle();
      expect(find.text(_counter(5)), findsOneWidget);
      await _tapPage(tester, const Offset(40, 300));
      await tester.pumpAndSettle();
      expect(find.text(_counter(4)), findsOneWidget);
    });
  });

  testWidgets('locks touch page turning but keeps keyboard turning', (
    tester,
  ) async {
    await _withReader(tester, (shelf) async {
      await tester.tap(find.byTooltip('锁定触摸翻页'));
      await tester.pump();
      expect(find.byTooltip('解除触摸锁定'), findsOneWidget);
      await _tapPage(tester, const Offset(760, 300));
      await tester.pumpAndSettle();
      expect(find.text(_counter(4)), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await tester.pumpAndSettle();
      expect(find.text(_counter(5)), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
      await tester.pumpAndSettle();
      expect(find.text(_counter(4)), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(find.text(_counter(5)), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pumpAndSettle();
      expect(find.text(_counter(1)), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pumpAndSettle();
      expect(find.text(_counter(5)), findsOneWidget);

      await tester.tap(find.byTooltip('解除触摸锁定'));
      await tester.pump();
      expect(find.byTooltip('锁定触摸翻页'), findsOneWidget);
    });
  });

  testWidgets('offers the next volume on the last page and remembers prefs', (
    tester,
  ) async {
    await _withReader(tester, (shelf) async {
      expect(find.text('继续阅读'), findsNothing);

      await _tapPage(tester, const Offset(760, 300));
      await tester.pumpAndSettle();
      expect(find.text(_counter(5)), findsOneWidget);
      expect(find.text('下一卷：测试 第2卷'), findsOneWidget);

      // Right-to-left is remembered for this book and becomes the default.
      // 从右向左会为本书记住，并成为默认值。
      await tester.tap(find.byTooltip('从左向右阅读'));
      await tester.pump();
      expect(shelf.volume1.rightToLeft, isTrue);
      expect(shelf.repository.settings.rightToLeft, isTrue);

      await tester.tap(find.text('继续阅读'));
      await tester.pumpAndSettle();
      expect(find.text('测试 第2卷'), findsOneWidget);
      expect(find.text(_counter(1)), findsOneWidget);
      expect(find.text('继续阅读'), findsNothing);
      expect(shelf.sources.length, 2);
      // The previous volume was read to its last page before switching.
      // 切换前，上一卷的进度已保存到最后一页。
      expect(shelf.volume1.lastPage, 4);
      // Volume 2 has no preference of its own and follows the default.
      // 第 2 卷没有单独的偏好，跟随默认值。
      expect(shelf.volume2.rightToLeft, isNull);
      expect(find.byTooltip('从右向左阅读'), findsOneWidget);
    });
  });

  testWidgets('scrolls by a screen when tapping the sides in vertical mode', (
    tester,
  ) async {
    await _withReader(tester, (shelf) async {
      await tester.tap(find.byTooltip('切换为纵向滚动'));
      await tester.pumpAndSettle();
      expect(shelf.volume1.readingMode, ReadingMode.vertical);
      expect(shelf.volume2.readingMode, isNull);

      double offset() => tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .pixels;
      // Volume 1 opens where it was left off: the top of page 4.
      // Each page is 800 × 1.4 = 1120 high, plus a 6 px gap.
      // 第 1 卷从上次读到的第 4 页顶部打开；
      // 每页高 800 × 1.4 = 1120，外加 6 px 间距。
      const start = 3378.0;
      expect(offset(), start);

      // Pages are taller than the screen, so one tap moves less than a page.
      // 页面比屏幕高，点一次滚动的距离小于一页。
      await _tapPage(tester, const Offset(400, 300));
      await tester.pumpAndSettle();
      expect(offset(), start);

      await _tapPage(tester, const Offset(760, 300));
      await tester.pumpAndSettle();
      expect(offset(), start + 540);
      expect(find.text(_counter(4)), findsOneWidget);

      await _tapPage(tester, const Offset(40, 300));
      await tester.pumpAndSettle();
      expect(offset(), start);
    });
  });

  testWidgets('finishes the last facing spread when opening the next volume', (
    tester,
  ) async {
    await _withReader(tester, (shelf) async {
      expect(find.text('4–5 / 5'), findsOneWidget);
      expect(find.text('下一卷：测试 第2卷'), findsOneWidget);
      await tester.tap(find.text('继续阅读'));
      await tester.pumpAndSettle();
      expect(shelf.volume1.lastPage, 4);
      expect(LibraryRepository.isFinished(shelf.volume1), isTrue);
      expect(find.text(shelf.volume2.title), findsOneWidget);
    }, prepare: (shelf) => shelf.volume1.doublePage = true);
  });

  testWidgets('reset applies vertical global defaults without editing them', (
    tester,
  ) async {
    await _withReader(
      tester,
      (shelf) async {
        await tester.tap(find.byTooltip('阅读设置'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('改回跟随全局'));
        await tester.pumpAndSettle();
        expect(find.text('改回跟随全局'), findsNothing);
        expect(find.widgetWithText(SwitchListTile, '双页模式'), findsNothing);
        expect(shelf.volume1.readingMode, isNull);
        expect(shelf.volume1.doublePage, isNull);
        expect(shelf.repository.settings.mode, ReadingMode.vertical);
        expect(shelf.repository.settings.doublePage, isTrue);
        expect(find.byTooltip('切换为横向翻页'), findsOneWidget);
      },
      prepare: (shelf) {
        shelf.repository.settings
          ..mode = ReadingMode.vertical
          ..doublePage = true;
        shelf.volume1
          ..readingMode = ReadingMode.horizontal
          ..doublePage = false;
      },
    );
  });

  testWidgets('blocks vertical drags when locked but allows the End key', (
    tester,
  ) async {
    await _withReader(tester, (shelf) async {
      double scrollOffset() => tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .pixels;
      final before = scrollOffset();
      await tester.tap(find.byTooltip('锁定触摸翻页'));
      await tester.pump();
      await tester.dragFrom(const Offset(400, 330), const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(scrollOffset(), before);
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pumpAndSettle();
      expect(scrollOffset(), greaterThan(before));
      expect(find.text('下一卷：测试 第2卷'), findsOneWidget);
    }, prepare: (shelf) => shelf.volume1.readingMode = ReadingMode.vertical);
  });

  testWidgets('honours a narrow tap zone', (tester) async {
    await _withReader(tester, (shelf) async {
      shelf.repository.setTapZoneWidth(TapZoneWidth.narrow);
      await tester.tap(find.byTooltip('阅读设置'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('窄'));
      await tester.pump();
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
      expect(shelf.repository.settings.tapZoneWidth, TapZoneWidth.narrow);

      // 20% from the left is the menu zone when the side zones are narrow,
      // while 12.5% still turns back.
      // 翻页区域为「窄」时，距左边缘 20% 的位置属于菜单区域，
      // 而 12.5% 处仍会向前翻页。
      await _tapPage(tester, const Offset(160, 300));
      await tester.pumpAndSettle();
      expect(find.text(_counter(4)), findsOneWidget);
      await _tapPage(tester, const Offset(100, 300));
      await tester.pumpAndSettle();
      expect(find.text(_counter(3)), findsOneWidget);
    });
  });
}
