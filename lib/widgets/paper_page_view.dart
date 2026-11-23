import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../formats/comic_page_crop.dart';
import '../formats/comic_source.dart';
import 'comic_page_image.dart';
import 'paper_curl.dart';

/// Keeps the PageView in charge of gestures while painting the turn above it.
/// 保留 PageView 的手势处理，并在其上绘制纸张翻页。
class PaperPageView extends StatefulWidget {
  const PaperPageView({
    required this.controller,
    required this.source,
    required this.rightToLeft,
    required this.background,
    required this.wrapPage,
    required this.onSettled,
    this.spreads,
    this.cropController,
    this.paperAnimation = true,
    this.scrollable = true,
    super.key,
  });

  final PageController controller;
  final ComicSource source;
  final bool rightToLeft;
  final Color background;
  final List<List<int>>? spreads;
  final ComicPageCropController? cropController;
  final bool paperAnimation;

  /// Whether swipes turn pages. Programmatic turns keep working when false.
  /// 是否允许滑动翻页；为 false 时仍可通过程序翻页。
  final bool scrollable;
  final Widget Function(Widget child, ValueChanged<bool> onZoomChanged)
  wrapPage;
  final ValueChanged<int> onSettled;

  @override
  State<PaperPageView> createState() => _PaperPageViewState();
}

class _PaperPageViewState extends State<PaperPageView> {
  final _paintUpdates = ValueNotifier(0);
  final _images = <int, _TurnPageImageState>{};
  final _zoomedSlots = <int>{};
  final _pointers = <int>{};
  late int _settledSlot = widget.controller.initialPage;
  (int, int)? _slideOnly;
  double? _touchY;
  bool _pinching = false;

  int get _slotCount => widget.spreads?.length ?? widget.source.pageCount;

  ComicPageCropController? get _crop =>
      identical(widget.cropController?.source, widget.source)
      ? widget.cropController
      : null;

  @override
  void initState() {
    super.initState();
    _crop?.addListener(_cropChanged);
  }

  @override
  void didUpdateWidget(covariant PaperPageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cropController != widget.cropController ||
        !identical(oldWidget.source, widget.source)) {
      oldWidget.cropController?.removeListener(_cropChanged);
      _crop?.addListener(_cropChanged);
    }
  }

  void _cropChanged() => setState(() {});

  double? get _page {
    final controller = widget.controller;
    if (!controller.hasClients || !controller.position.haveDimensions) {
      return null;
    }
    return controller.page;
  }

  bool _observeScroll(ScrollNotification event) {
    if (event.depth != 0 || event is! ScrollEndNotification) return false;
    final page = _page;
    if (page == null) return false;
    final slot = page.round();
    if ((page - slot).abs() > 0.001) return false;

    _settledSlot = slot;
    _slideOnly = null;
    _touchY = null;
    final controller = widget.controller;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || controller != widget.controller || _settledSlot != slot) {
        return;
      }
      final current = _page;
      if (current != null && (current - slot).abs() <= 0.001) {
        widget.onSettled(slot);
      }
    });
    _paintUpdates.value++;
    return false;
  }

  List<({int page, Rect rect})> _layout(int slot, Size viewport) {
    final pages = widget.spreads?[slot] ?? [slot];
    final ordered = widget.rightToLeft ? pages.reversed : pages;
    final aspects = [
      for (final page in ordered)
        (_crop?.pageSize(page) ??
                ComicSource.safePageSize(widget.source.pageSize(page)))
            .aspectRatio,
    ];
    const gap = 6.0;
    final totalGap = gap * (aspects.length - 1);
    final aspectSum = aspects.reduce((a, b) => a + b);
    final height = math.min(
      viewport.height,
      math.max(0.0, viewport.width - totalGap) / aspectSum,
    );
    final top = (viewport.height - height) / 2;
    var left = (viewport.width - height * aspectSum - totalGap) / 2;
    final placement = <({int page, Rect rect})>[];
    for (final (index, page) in ordered.indexed) {
      final rect = Rect.fromLTWH(left, top, aspects[index] * height, height);
      placement.add((page: page, rect: rect));
      left = rect.right + gap;
    }
    return placement;
  }

  List<PaperSheet>? _sheets(int slot, Size viewport) {
    final sheets = <PaperSheet>[];
    for (final placement in _layout(slot, viewport)) {
      final frame = _images[placement.page];
      if (frame == null ||
          !identical(frame.widget.source, widget.source) ||
          placement.rect.isEmpty) {
        return null;
      }
      final image = frame._image;
      if (image == null) return null;
      sheets.add(
        PaperSheet(image, placement.rect, sourceRect: frame._imageRect),
      );
    }
    return sheets;
  }

  PaperTurn? _readTurn(Size viewport) {
    final page = _page;
    if (page == null || viewport.isEmpty) return null;
    final delta = page - _settledSlot;
    final progress = delta.abs();
    if (progress <= 0.001 || progress >= 0.999) return null;
    final forward = delta > 0;
    final target = _settledSlot + (forward ? 1 : -1);
    if (target < 0 || target >= _slotCount) return null;
    final pair = (_settledSlot, target);
    if (_slideOnly == pair) return null;
    if (_pinching ||
        _zoomedSlots.contains(_settledSlot) ||
        _zoomedSlots.contains(target)) {
      _slideOnly = pair;
      return null;
    }

    final outgoing = _sheets(_settledSlot, viewport);
    final incoming = _sheets(target, viewport);
    if (outgoing == null || incoming == null) {
      _slideOnly = pair;
      return null;
    }
    return PaperTurn(
      outgoing: outgoing,
      incoming: incoming,
      fromRight: forward != widget.rightToLeft,
      progress: progress,
      touchHeight: ((_touchY ?? viewport.height * 0.68) / viewport.height)
          .clamp(0.0, 1.0),
    );
  }

  void _setZoom(int slot, bool zoomed) {
    final changed = zoomed ? _zoomedSlots.add(slot) : _zoomedSlots.remove(slot);
    if (changed) _paintUpdates.value++;
  }

  void _releasePointer(PointerEvent event) {
    _pointers.remove(event.pointer);
    if (_pointers.isEmpty) _pinching = false;
  }

  @override
  void dispose() {
    _crop?.removeListener(_cropChanged);
    _paintUpdates.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final animated =
        widget.paperAnimation && !MediaQuery.disableAnimationsOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final pages = NotificationListener<ScrollNotification>(
          onNotification: _observeScroll,
          child: PageView.builder(
            controller: widget.controller,
            reverse: widget.rightToLeft,
            physics: widget.scrollable
                ? const PageScrollPhysics()
                : const NeverScrollableScrollPhysics(),
            allowImplicitScrolling: true,
            itemCount: _slotCount,
            itemBuilder: (context, slot) {
              return widget.wrapPage(
                Stack(
                  children: [
                    for (final placement in _layout(slot, constraints.biggest))
                      Positioned.fromRect(
                        rect: placement.rect,
                        child: animated
                            ? _TurnPageImage(
                                key: ValueKey((widget.source, placement.page)),
                                view: this,
                                source: widget.source,
                                page: placement.page,
                                cropController: _crop,
                              )
                            : ComicPageImage(
                                key: ValueKey((widget.source, placement.page)),
                                source: widget.source,
                                index: placement.page,
                                cropController: _crop,
                              ),
                      ),
                  ],
                ),
                (zoomed) => _setZoom(slot, zoomed),
              );
            },
          ),
        );
        if (!animated) return pages;
        return Listener(
          onPointerDown: (event) {
            if (_pointers.isEmpty) {
              _touchY = event.localPosition.dy;
              _pinching = false;
            }
            _pointers.add(event.pointer);
            if (_pointers.length > 1) {
              _pinching = true;
              _paintUpdates.value++;
            }
          },
          onPointerMove: (event) {
            if (_pinching) return;
            _touchY = event.localPosition.dy;
            _paintUpdates.value++;
          },
          onPointerUp: _releasePointer,
          onPointerCancel: _releasePointer,
          child: Stack(
            fit: StackFit.expand,
            children: [
              pages,
              IgnorePointer(
                child: RepaintBoundary(
                  child: CustomPaint(
                    willChange: true,
                    painter: PaperCurlPainter(
                      readTurn: _readTurn,
                      background: widget.background,
                      repaint: Listenable.merge([
                        widget.controller,
                        _paintUpdates,
                      ]),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TurnPageImage extends StatefulWidget {
  const _TurnPageImage({
    required this.view,
    required this.source,
    required this.page,
    required this.cropController,
    super.key,
  });

  final _PaperPageViewState view;
  final ComicSource source;
  final int page;
  final ComicPageCropController? cropController;

  @override
  State<_TurnPageImage> createState() => _TurnPageImageState();
}

class _TurnPageImageState extends State<_TurnPageImage> {
  ui.Image? _image;
  Rect? _imageRect;

  void _shareImage(ui.Image image, Rect imageRect) {
    final sameImage = _image?.isCloneOf(image) == true;
    if (sameImage && _imageRect == imageRect) return;
    if (!sameImage) {
      _image?.dispose();
      _image = image.clone();
    }
    _imageRect = imageRect;
    widget.view._images[widget.page] = this;
    widget.view._paintUpdates.value++;
  }

  @override
  void dispose() {
    final view = widget.view;
    if (view._images[widget.page] == this) {
      view._images.remove(widget.page);
    }
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ComicPageImage(
    source: widget.source,
    index: widget.page,
    cropController: widget.cropController,
    onFrame: _shareImage,
  );
}
