import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../formats/comic_page_crop.dart';
import '../formats/comic_source.dart';
import '../formats/page_raster.dart';

/// Supplies the zoom transform to page renders below an InteractiveViewer.
/// 将 InteractiveViewer 的缩放变换提供给下方的页面渲染。
class PageRenderScale extends InheritedWidget {
  const PageRenderScale({
    required this.controller,
    required super.child,
    super.key,
  });

  final TransformationController controller;

  static TransformationController? _of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PageRenderScale>()?.controller;

  @override
  bool updateShouldNotify(PageRenderScale oldWidget) =>
      oldWidget.controller != controller;
}

/// Paints a lazy page and upgrades its bitmap as the reader zooms in.
/// 按需绘制页面，并在阅读器放大时提升位图分辨率。
class ComicPageImage extends StatefulWidget {
  const ComicPageImage({
    required this.source,
    required this.index,
    this.cropController,
    this.onImage,
    this.onFrame,
    this.thumbnailWidth,
    super.key,
  }) : assert(cropController == null || thumbnailWidth == null);

  final ComicSource source;
  final int index;
  final ComicPageCropController? cropController;
  final int? thumbnailWidth;
  final ValueChanged<ui.Image>? onImage;

  /// Borrows the full bitmap and its visible pixel rectangle for the callback.
  /// 回调期间借用完整位图及其可见的像素矩形。
  final void Function(ui.Image image, Rect imageRect)? onFrame;

  @override
  State<ComicPageImage> createState() => _ComicPageImageState();
}

typedef _PageRequest = ({ComicPageRenderer renderer, int index, Size size});

class _ComicPageImageState extends State<ComicPageImage> {
  static final _renderQueue = <_ComicPageImageState>{};
  static int _activeRenders = 0;

  TransformationController? _transform;
  Timer? _zoomDebounce;
  double? _pendingZoom;
  double _zoom = 1;
  Rect _bounds = ComicPageCropController.fullPage;
  _PageRequest? _requested;
  _PageRequest? _attempted;
  _PageRequest? _displayed;
  bool _rendering = false;
  bool _failed = false;
  ui.Image? _image;

  ComicPageCropController? get _crop =>
      identical(widget.cropController?.source, widget.source)
      ? widget.cropController
      : null;

  @override
  void initState() {
    super.initState();
    _crop?.addListener(_updateCrop);
    _bounds =
        _crop?.boundsFor(widget.index) ?? ComicPageCropController.fullPage;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final transform = widget.thumbnailWidth == null
        ? PageRenderScale._of(context)
        : null;
    if (transform == _transform) return;
    _zoomDebounce?.cancel();
    _pendingZoom = null;
    _transform?.removeListener(_updateZoom);
    _transform = transform;
    _transform?.addListener(_updateZoom);
    _zoom = _zoomTier;
  }

  @override
  void didUpdateWidget(covariant ComicPageImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cropController != widget.cropController ||
        !identical(oldWidget.source, widget.source)) {
      oldWidget.cropController?.removeListener(_updateCrop);
      _crop?.addListener(_updateCrop);
    }
    _bounds =
        _crop?.boundsFor(widget.index) ?? ComicPageCropController.fullPage;
    if (!identical(oldWidget.source, widget.source) ||
        oldWidget.index != widget.index) {
      _requested = _attempted = _displayed = null;
      _image?.dispose();
      _image = null;
      _failed = false;
    }
  }

  void _updateCrop() {
    final bounds =
        _crop?.boundsFor(widget.index) ?? ComicPageCropController.fullPage;
    if (bounds != _bounds) setState(() => _bounds = bounds);
  }

  double get _zoomTier {
    final scale = _transform?.value.getMaxScaleOnAxis() ?? 1;
    return switch (scale) {
      <= 1.01 => 1,
      <= 1.5 => 1.5,
      <= 2 => 2,
      <= 3 => 3,
      <= 4 => 4,
      _ => 5,
    };
  }

  void _updateZoom() {
    final tier = _zoomTier;
    if (tier == _pendingZoom) return;
    _zoomDebounce?.cancel();
    _pendingZoom = null;
    if (tier == _zoom) return;
    if (tier == 1) {
      setState(() => _zoom = tier);
    } else {
      _pendingZoom = tier;
      _zoomDebounce = Timer(const Duration(milliseconds: 100), () {
        _pendingZoom = null;
        setState(() => _zoom = tier);
      });
    }
  }

  void _request(ComicPageRenderer renderer, Size size) {
    _requested = (renderer: renderer, index: widget.index, size: size);
    if (_rendering || _attempted == _requested || _displayed == _requested) {
      return;
    }
    _rendering = true;
    _renderQueue.add(this);
    scheduleMicrotask(_drainRenderQueue);
  }

  static void _drainRenderQueue() {
    // Bound concurrent allocations while the reader scrolls through pages.
    // 阅读器滚动翻页时限制同时进行的位图分配。
    while (_activeRenders < 3 && _renderQueue.isNotEmpty) {
      final next = _renderQueue.first;
      _renderQueue.remove(next);
      _activeRenders++;
      unawaited(
        next._renderLatest().whenComplete(() {
          _activeRenders--;
          _drainRenderQueue();
        }),
      );
    }
  }

  Future<void> _renderLatest() async {
    // Keep one request in flight and coalesce new layout or zoom requests.
    // 同时只进行一次请求，并合并新的布局或缩放请求。
    while (mounted) {
      final request = _requested;
      if (request == null || request == _attempted || request == _displayed) {
        break;
      }
      _attempted = request;
      try {
        final image = await request.renderer.renderPageImage(
          request.index,
          request.size,
        );
        if (!mounted || request != _requested) {
          image.dispose();
          continue;
        }
        setState(() {
          _image?.dispose();
          _image = image;
          _displayed = request;
          _failed = false;
        });
      } catch (_) {
        if (mounted && request == _requested && _image == null) {
          setState(() => _failed = true);
        }
      }
    }
    _rendering = false;
  }

  @override
  void dispose() {
    _renderQueue.remove(this);
    _zoomDebounce?.cancel();
    _transform?.removeListener(_updateZoom);
    _crop?.removeListener(_updateCrop);
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final source = widget.source;
    if (source is! ComicPageRenderer) {
      final index = widget.index;
      final onFrame = widget.onFrame;
      final onImage = widget.onImage;
      return source.buildPage(
        context,
        index,
        onImage: onFrame == null && onImage == null
            ? null
            : (image) {
                if (!mounted ||
                    !identical(widget.source, source) ||
                    widget.index != index) {
                  return;
                }
                onImage?.call(image);
                onFrame?.call(
                  image,
                  _pixelRect(image, ComicPageCropController.fullPage),
                );
              },
      );
    }

    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    final originalSize = ComicSource.safePageSize(
      source.pageSize(widget.index),
    );
    final pageSize = _crop?.pageSize(widget.index) ?? originalSize;
    final thumbnailWidth = widget.thumbnailWidth;
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = constraints.constrain(
          Size(
            constraints.hasBoundedWidth ? constraints.maxWidth : pageSize.width,
            constraints.hasBoundedHeight
                ? constraints.maxHeight
                : pageSize.height,
          ),
        );
        if (!viewport.isEmpty) {
          final fit = applyBoxFit(
            BoxFit.contain,
            pageSize,
            viewport,
          ).destination;
          final rasterSize = Size(
            pageSize.width / _bounds.width,
            pageSize.height / _bounds.height,
          );
          final baseTarget = thumbnailWidth == null
              ? Size(fit.width / _bounds.width, fit.height / _bounds.height) *
                    devicePixelRatio
              : Size(
                  thumbnailWidth.toDouble(),
                  thumbnailWidth / originalSize.aspectRatio,
                );
          final base = fitPageRasterSize(
            rasterSize,
            baseTarget,
            maxEdge: 2304,
            maxPixels: 4 * 1024 * 1024,
          );
          _request(
            source as ComicPageRenderer,
            _zoom == 1 ? base : fitPageRasterSize(rasterSize, base * _zoom),
          );
        } else {
          _requested = null;
        }

        final image = _image;
        if (image == null) return _placeholder(thumbnailWidth != null);
        _crop?.inspectPage(widget.index, image);
        final imageRect = _pixelRect(image, _bounds);
        widget.onImage?.call(image);
        widget.onFrame?.call(image, imageRect);
        if (_bounds == ComicPageCropController.fullPage) {
          return RawImage(
            image: image,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
          );
        }
        return CustomPaint(
          size: viewport,
          painter: _CropPainter(image, imageRect, pageSize),
        );
      },
    );
  }

  Widget _placeholder(bool compact) {
    if (_failed) {
      return ColoredBox(
        color: const Color(0xFF15161A),
        child: Center(
          child: compact
              ? const Icon(
                  Icons.broken_image_outlined,
                  color: Colors.white24,
                  size: 18,
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white38,
                      size: 34,
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      '这一页加载失败',
                      style: TextStyle(color: Colors.white54, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => setState(() {
                        _attempted = null;
                        _failed = false;
                      }),
                      child: const Text('重试'),
                    ),
                  ],
                ),
        ),
      );
    }
    return ColoredBox(
      color: const Color(0xFF0F1013),
      child: Center(
        child: compact
            ? null
            : const SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: Colors.white38,
                ),
              ),
      ),
    );
  }
}

Rect _pixelRect(ui.Image image, Rect bounds) => Rect.fromLTRB(
  bounds.left * image.width,
  bounds.top * image.height,
  bounds.right * image.width,
  bounds.bottom * image.height,
);

class _CropPainter extends CustomPainter {
  const _CropPainter(this.image, this.imageRect, this.pageSize);

  final ui.Image image;
  final Rect imageRect;
  final Size pageSize;

  @override
  void paint(Canvas canvas, Size size) {
    final fitted = applyBoxFit(BoxFit.contain, pageSize, size).destination;
    canvas.drawImageRect(
      image,
      imageRect,
      Alignment.center.inscribe(fitted, Offset.zero & size),
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(covariant _CropPainter oldDelegate) =>
      !image.isCloneOf(oldDelegate.image) ||
      imageRect != oldDelegate.imageRect ||
      pageSize != oldDelegate.pageSize;
}
