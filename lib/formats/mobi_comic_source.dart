import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/toc_entry.dart';
import 'comic_source.dart';
import 'mobi/mobi_book.dart';

/// MOBI comics: every page is one embedded image record.
/// MOBI 漫画：每一页对应一条内嵌图片记录。
class MobiComicSource implements ComicSource {
  MobiComicSource(this.book);

  final MobiBook book;

  @override
  int get pageCount => book.pageCount;

  @override
  Size pageSize(int index) {
    final image = book.images[index];
    if (!image.hasSize) return ComicSource.fallbackPageSize;
    return ComicSource.safePageSize(
      Size(image.width.toDouble(), image.height.toDouble()),
    );
  }

  @override
  Widget buildPage(BuildContext context, int index) {
    return MobiPageImage(book: book, pageIndex: index);
  }

  @override
  Widget buildThumbnail(BuildContext context, int index) {
    return MobiPageImage(
      book: book,
      pageIndex: index,
      targetWidth: 240,
      compact: true,
    );
  }

  @override
  Future<List<TocEntry>> loadToc() async => book.toc;

  @override
  Future<void> dispose() async {}
}

/// Loads and decodes one page image lazily, releasing the decoded bitmap when
/// the page scrolls out of the widget tree.
/// 按需加载并解码单个页面图片，页面滚出组件树时释放已解码位图。
class MobiPageImage extends StatefulWidget {
  const MobiPageImage({
    required this.book,
    required this.pageIndex,
    this.targetWidth,
    this.compact = false,
    super.key,
  });

  final MobiBook book;
  final int pageIndex;

  /// Decode width override (used for small thumbnails).
  /// 解码宽度覆盖值（用于小尺寸缩略图）。
  final int? targetWidth;

  /// Compact mode hides loading/error text for tiny navigation thumbnails.
  /// 紧凑模式会在微型导航缩略图中隐藏加载 / 错误文字。
  final bool compact;

  @override
  State<MobiPageImage> createState() => _MobiPageImageState();
}

class _MobiPageImageState extends State<MobiPageImage> {
  ui.Image? _image;
  Object? _error;
  bool _started = false;
  int _loadAttempt = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load();
  }

  @override
  void didUpdateWidget(covariant MobiPageImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.book != widget.book ||
        oldWidget.pageIndex != widget.pageIndex) {
      _load();
    }
  }

  Future<void> _load() async {
    final attempt = ++_loadAttempt;
    if (_error != null) {
      setState(() => _error = null);
    }

    try {
      final imageRecord = widget.book.images[widget.pageIndex];
      final bytes = await widget.book.readPage(widget.pageIndex);
      if (!mounted || attempt != _loadAttempt) return;

      final int targetWidth;
      if (widget.targetWidth != null) {
        targetWidth = widget.targetWidth!;
      } else {
        final media = MediaQuery.of(context);
        final devicePixels = media.size.width * media.devicePixelRatio * 1.35;
        final nativeWidth = imageRecord.width > 0
            ? imageRecord.width.toDouble()
            : 2200.0;
        targetWidth = math
            .min(nativeWidth, devicePixels)
            .clamp(720.0, 2400.0)
            .round();
      }

      final image = await _decode(bytes, targetWidth);
      if (!mounted || attempt != _loadAttempt) {
        image.dispose();
        return;
      }
      setState(() {
        _image?.dispose();
        _image = image;
      });
    } catch (error) {
      if (!mounted || attempt != _loadAttempt) return;
      setState(() => _error = error);
    }
  }

  Future<ui.Image> _decode(Uint8List bytes, int targetWidth) async {
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: targetWidth,
    );
    try {
      final frame = await codec.getNextFrame();
      return frame.image;
    } finally {
      codec.dispose();
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      if (widget.compact) {
        return const ColoredBox(
          color: Color(0xFF15161A),
          child: Center(
            child: Icon(
              Icons.broken_image_outlined,
              color: Colors.white24,
              size: 18,
            ),
          ),
        );
      }
      return ColoredBox(
        color: const Color(0xFF15161A),
        child: Center(
          child: Column(
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
              TextButton(onPressed: _load, child: const Text('重试')),
            ],
          ),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        if (_image != null)
          RawImage(
            image: _image,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
          )
        else
          const ColoredBox(color: Color(0xFF0F1013)),
        if (_image == null && !widget.compact)
          const Center(
            child: SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: Colors.white38,
              ),
            ),
          ),
      ],
    );
  }
}
