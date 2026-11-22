import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/toc_entry.dart';
import 'comic_source.dart';
import 'zip/image_size.dart';
import 'zip/zip_archive_reader.dart';

/// CBZ comics (ZIP container): every image entry is one page.
/// CBZ 漫画（ZIP 容器）：每个图片条目对应一页。
class ArchiveComicSource implements ComicSource {
  ArchiveComicSource._(this._reader, this._sizes, this._toc);

  final ZipArchiveReader _reader;
  final List<Size> _sizes;
  final List<TocEntry> _toc;

  static Future<ArchiveComicSource> open(String filePath) async {
    final reader = await ZipArchiveReader.open(filePath);
    try {
      final sizes = <Size>[];
      for (var index = 0; index < reader.pages.length; index++) {
        final prefix = await reader.readPagePrefix(index);
        final dimensions = readImageDimensions(prefix);
        sizes.add(
          dimensions == null
              ? ComicSource.fallbackPageSize
              : ComicSource.safePageSize(
                  Size(
                    dimensions.width.toDouble(),
                    dimensions.height.toDouble(),
                  ),
                ),
        );
      }
      return ArchiveComicSource._(reader, sizes, _buildToc(reader.pages));
    } catch (_) {
      await reader.dispose();
      rethrow;
    }
  }

  @override
  int get pageCount => _reader.pages.length;

  @override
  Size pageSize(int index) => _sizes[index];

  Future<Uint8List> readPageBytes(int index) => _reader.readPageBytes(index);

  @override
  Widget buildPage(
    BuildContext context,
    int index, {
    ValueChanged<ui.Image>? onImage,
  }) {
    return ArchivePageImage(
      source: this,
      reader: _reader,
      pageIndex: index,
      onImage: onImage,
    );
  }

  @override
  Widget buildThumbnail(BuildContext context, int index) {
    return ArchivePageImage(
      source: this,
      reader: _reader,
      pageIndex: index,
      targetWidth: 240,
      compact: true,
    );
  }

  @override
  Future<List<TocEntry>> loadToc() async => _toc;

  @override
  Future<void> dispose() => _reader.dispose();

  static List<TocEntry> _buildToc(List<ZipPage> pages) {
    final firstPageByChapter = <String, int>{};
    for (var index = 0; index < pages.length; index++) {
      final path = pages[index].path;
      final slash = path.indexOf('/');
      if (slash <= 0) continue;
      firstPageByChapter.putIfAbsent(path.substring(0, slash), () => index);
    }
    if (firstPageByChapter.length < 2) return const [];
    final entries = [
      for (final chapter in firstPageByChapter.entries)
        TocEntry(title: chapter.key, page: chapter.value),
    ]..sort((a, b) => a.page.compareTo(b.page));
    return entries;
  }
}

/// Loads and decodes one archive page lazily, releasing the bitmap when the
/// page leaves the widget tree.
/// 按需加载并解码压缩包中的一页，页面移出组件树时释放位图。
class ArchivePageImage extends StatefulWidget {
  const ArchivePageImage({
    required this.source,
    required this.reader,
    required this.pageIndex,
    this.targetWidth,
    this.compact = false,
    this.onImage,
    super.key,
  });

  final ArchiveComicSource source;
  final ZipArchiveReader reader;
  final int pageIndex;
  final int? targetWidth;
  final bool compact;
  final ValueChanged<ui.Image>? onImage;

  @override
  State<ArchivePageImage> createState() => _ArchivePageImageState();
}

class _ArchivePageImageState extends State<ArchivePageImage> {
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
  void didUpdateWidget(covariant ArchivePageImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reader != widget.reader ||
        oldWidget.pageIndex != widget.pageIndex) {
      _image?.dispose();
      _image = null;
      _load();
    }
  }

  Future<void> _load() async {
    final attempt = ++_loadAttempt;
    if (_error != null) {
      setState(() => _error = null);
    }

    try {
      final bytes = await widget.reader.readPageBytes(widget.pageIndex);
      if (!mounted || attempt != _loadAttempt) return;

      final int targetWidth;
      if (widget.targetWidth != null) {
        targetWidth = widget.targetWidth!;
      } else {
        final media = MediaQuery.of(context);
        final devicePixels = media.size.width * media.devicePixelRatio * 1.35;
        final nativeWidth = widget.source.pageSize(widget.pageIndex).width;
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

    final image = _image;
    if (image != null) widget.onImage?.call(image);
    return Stack(
      fit: StackFit.expand,
      children: [
        if (image != null)
          RawImage(
            image: image,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
          )
        else
          const ColoredBox(color: Color(0xFF0F1013)),
        if (image == null && !widget.compact)
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
