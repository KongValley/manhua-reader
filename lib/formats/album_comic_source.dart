import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/comic_book.dart';
import '../models/toc_entry.dart';
import 'album/album_store.dart';
import 'comic_source.dart';

/// Reads a referenced folder of images as one comic album.
/// 将引用的图片文件夹作为一本相册读取。
class AlbumComicSource implements ComicSource {
  AlbumComicSource._(this._store, this._images, this._sizes, this._toc);

  final AlbumStore _store;
  final List<AlbumImage> _images;
  final List<Size> _sizes;
  final List<TocEntry> _toc;

  final LinkedHashMap<int, Uint8List> _cache = LinkedHashMap<int, Uint8List>();
  int _cachedBytes = 0;
  static const int _cacheLimit = 6;
  static const int _cacheByteLimit = 48 * 1024 * 1024;

  static Future<AlbumComicSource> open(
    String source, {
    AlbumSortField sort = AlbumSortField.name,
    bool descending = false,
  }) async {
    final store = createAlbumStore(source);
    try {
      final images = await store.list(sort: sort, descending: descending);
      final sizes = [
        for (final image in images)
          image.width > 0 && image.height > 0
              ? ComicSource.safePageSize(
                  Size(image.width.toDouble(), image.height.toDouble()),
                )
              : ComicSource.fallbackPageSize,
      ];
      return AlbumComicSource._(store, images, sizes, _buildToc(images));
    } catch (_) {
      await store.dispose();
      rethrow;
    }
  }

  @override
  int get pageCount => _images.length;

  /// Total byte size of the referenced images.
  /// 引用图片的总字节数。
  int get totalBytes => _images.fold<int>(0, (sum, image) => sum + image.size);

  /// Stable relative paths in current page order, used when sorting remaps
  /// progress and bookmarks.
  /// 当前页序下稳定的相对路径，用于排序时重映射进度和书签。
  List<String> get pageKeys => [
    for (final image in _images) image.relativePath,
  ];

  @override
  Size pageSize(int index) => _sizes[index];

  Future<Uint8List> readPageBytes(int index) async {
    if (index < 0 || index >= _images.length) {
      throw RangeError.index(index, _images, 'index');
    }
    final cached = _cache.remove(index);
    if (cached != null) {
      _cache[index] = cached;
      return cached;
    }
    final bytes = await _store.readBytes(_images[index]);
    _cache[index] = bytes;
    _cachedBytes += bytes.length;
    while ((_cache.length > _cacheLimit || _cachedBytes > _cacheByteLimit) &&
        _cache.isNotEmpty) {
      final evicted = _cache.remove(_cache.keys.first)!;
      _cachedBytes -= evicted.length;
    }
    return bytes;
  }

  @override
  Widget buildPage(
    BuildContext context,
    int index, {
    ValueChanged<ui.Image>? onImage,
  }) {
    return AlbumPageImage(source: this, pageIndex: index, onImage: onImage);
  }

  @override
  Widget buildThumbnail(BuildContext context, int index) {
    return AlbumPageImage(
      source: this,
      pageIndex: index,
      targetWidth: 240,
      compact: true,
    );
  }

  @override
  Future<List<TocEntry>> loadToc() async => _toc;

  @override
  Future<void> dispose() async {
    _cache.clear();
    _cachedBytes = 0;
    await _store.dispose();
  }

  static List<TocEntry> _buildToc(List<AlbumImage> images) {
    final firstPageByChapter = <String, int>{};
    for (var index = 0; index < images.length; index++) {
      final path = images[index].relativePath;
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

/// Lazily loads and decodes one album page.
/// 按需加载并解码相册中的一页。
class AlbumPageImage extends StatefulWidget {
  const AlbumPageImage({
    required this.source,
    required this.pageIndex,
    this.targetWidth,
    this.compact = false,
    this.onImage,
    super.key,
  });

  final AlbumComicSource source;
  final int pageIndex;
  final int? targetWidth;
  final bool compact;
  final ValueChanged<ui.Image>? onImage;

  @override
  State<AlbumPageImage> createState() => _AlbumPageImageState();
}

class _AlbumPageImageState extends State<AlbumPageImage> {
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
  void didUpdateWidget(covariant AlbumPageImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source ||
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
      final bytes = await widget.source.readPageBytes(widget.pageIndex);
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
