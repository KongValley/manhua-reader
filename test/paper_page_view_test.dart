import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manhua_reader/formats/comic_source.dart';
import 'package:manhua_reader/models/toc_entry.dart';
import 'package:manhua_reader/utils/pagination.dart';
import 'package:manhua_reader/widgets/paper_curl.dart';
import 'package:manhua_reader/widgets/paper_page_view.dart';

void main() {
  for (final rightToLeft in [false, true]) {
    testWidgets('paper turn commits only at rest (RTL: $rightToLeft)', (
      tester,
    ) async {
      final source = _PageSource();
      final controller = PageController(initialPage: 1);
      final settled = <int>[];
      await tester.pumpWidget(
        _reader(controller, source, settled, rightToLeft: rightToLeft),
      );
      await tester.pumpAndSettle();

      final size = tester.getSize(find.byType(PaperPageView));
      final direction = rightToLeft ? 1 : -1;
      final start = Offset(
        size.width * (rightToLeft ? 0.2 : 0.8),
        size.height * 0.76,
      );
      final drag = await tester.startGesture(start);
      await drag.moveBy(Offset(22.0 * direction, 0));
      await tester.pump(const Duration(milliseconds: 30));
      await drag.moveBy(Offset(size.width * 0.59 * direction, 0));
      await tester.pump(const Duration(milliseconds: 30));

      final painter = _painter(tester);
      final turn = painter.readTurn(size);
      expect(turn, isNotNull);
      expect(turn!.progress, greaterThan(0.5));
      expect(turn.fromRight, !rightToLeft);
      expect(turn.touchHeight, closeTo(0.76, 0.01));
      expect(turn.outgoing.single.image.isCloneOf(source.images[1]), isTrue);
      expect(turn.incoming.single.image.isCloneOf(source.images[2]), isTrue);
      expect(settled, isEmpty);

      await drag.moveBy(Offset(-size.width * 0.45 * direction, 0));
      await tester.pump(const Duration(milliseconds: 200));
      await drag.up();
      await tester.pumpAndSettle();
      expect(controller.page, 1);
      expect(settled, everyElement(1));
      expect(painter.readTurn(size), isNull);

      await tester.dragFrom(start, Offset(size.width * 0.72 * direction, 0));
      await tester.pumpAndSettle();
      expect(controller.page, 2);
      expect(settled.where((slot) => slot != 1), [2]);
      expect(tester.takeException(), isNull);

      await _close(tester, controller, source);
    });
  }

  testWidgets('animates a spread turn using the rendered facing pages', (
    tester,
  ) async {
    final source = _PageSource();
    final controller = PageController(initialPage: 1);
    final settled = <int>[];
    await tester.pumpWidget(
      _reader(
        controller,
        source,
        settled,
        spreads: buildSpreads(source.pageCount),
      ),
    );
    await tester.pumpAndSettle();

    final animation = controller.animateToPage(
      2,
      duration: const Duration(milliseconds: 400),
      curve: Curves.linear,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    final turn = _painter(tester)
        .readTurn(tester.getSize(find.byType(PaperPageView)));
    expect(turn, isNotNull);
    expect(turn!.outgoing, hasLength(2));
    expect(turn.incoming, hasLength(2));
    expect(turn.outgoing.last.image.isCloneOf(source.images[2]), isTrue);
    expect(turn.incoming.first.image.isCloneOf(source.images[3]), isTrue);
    expect(settled, isEmpty);

    await tester.pumpAndSettle();
    await animation;
    expect(settled, [2]);
    expect(tester.takeException(), isNull);
    await _close(tester, controller, source);
  });
}

Widget _reader(
  PageController controller,
  _PageSource source,
  List<int> settled, {
  bool rightToLeft = false,
  List<List<int>>? spreads,
}) => MaterialApp(
  home: PaperPageView(
    controller: controller,
    source: source,
    rightToLeft: rightToLeft,
    background: Colors.black,
    spreads: spreads,
    wrapPage: (child, onZoomChanged) => child,
    onSettled: settled.add,
  ),
);

PaperCurlPainter _painter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((widget) => widget.painter)
    .whereType<PaperCurlPainter>()
    .single;

Future<void> _close(
  WidgetTester tester,
  PageController controller,
  _PageSource source,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  controller.dispose();
  await source.dispose();
}

class _PageSource extends ComicSource {
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
    final image = images[index];
    onImage?.call(image);
    return RawImage(image: image, fit: BoxFit.fill);
  }

  @override
  Widget buildThumbnail(BuildContext context, int index) =>
      buildPage(context, index);

  @override
  Future<List<TocEntry>> loadToc() async => [];

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
