import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../models/comic_book.dart';
import '../models/toc_entry.dart';
import '../widgets/comic_page_image.dart';
import 'album/album_store.dart';
import 'comic_source.dart';
import 'page_raster.dart';
import 'zip/image_size.dart';

/// Reads a referenced folder of images as one comic album.
/// 将引用的图片文件夹作为一本相册读取。
class AlbumComicSource
    implements ComicSource, ComicPageRenderer, ComicPageLayoutSource {
  AlbumComicSource._(
    this._store,
    this._images,
    this._sizes,
    this._defaultSize,
    this._toc,
  );

  final AlbumStore _store;
  final List<AlbumImage> _images;
  final List<Size?> _sizes;
  final Size _defaultSize;
  final List<TocEntry> _toc;

  final LinkedHashMap<int, Uint8List> _cache = LinkedHashMap<int, Uint8List>();
  final ValueNotifier<int> _sizeRevision = ValueNotifier<int>(0);
  final Set<int> _probing = <int>{};
  int _cachedBytes = 0;
  bool _notifyScheduled = false;
  bool _disposed = false;
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
      final sizes = List<Size?>.filled(images.length, null);
      Size? defaultSize;
      for (var index = 0; index < images.length; index++) {
        final image = images[index];
        if (image.width <= 0 || image.height <= 0) continue;
        final size = ComicSource.safePageSize(
          Size(image.width.toDouble(), image.height.toDouble()),
        );
        sizes[index] = size;
        defaultSize ??= size;
      }
      return AlbumComicSource._(
        store,
        images,
        sizes,
        defaultSize ?? ComicSource.fallbackPageSize,
        _buildToc(images),
      );
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
  Size pageSize(int index) => _sizes[index] ?? _defaultSize;

  @override
  Listenable get pageSizesChanged => _sizeRevision;

  @override
  Future<void> ensurePageSizes(Iterable<int> indices) async {
    for (final index in indices.toSet()) {
      if (_disposed || index < 0 || index >= _images.length) continue;
      if (_sizes[index] != null || !_probing.add(index)) continue;
      try {
        final size = _sizeFromBytes(await _store.readPrefix(_images[index]));
        if (size != null) _learnSize(index, size);
      } catch (_) {
        // A damaged page keeps the estimated size; rendering reports the error.
        // 损坏页面保留估算尺寸，渲染时再显示错误。
      } finally {
        _probing.remove(index);
      }
    }
  }

  Future<Uint8List> readPageBytes(int index) async {
    if (_disposed) throw StateError('Album source is closed');
    if (index < 0 || index >= _images.length) {
      throw RangeError.index(index, _images, 'index');
    }
    final cached = _cache.remove(index);
    if (cached != null) {
      _cache[index] = cached;
      return cached;
    }
    final bytes = await _store.readBytes(_images[index]);
    if (_disposed) throw StateError('Album source is closed');
    _learnSize(index, _sizeFromBytes(bytes));
    _cachedBytes -= _cache.remove(index)?.length ?? 0;
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
  }) => ComicPageImage(source: this, index: index, onImage: onImage);

  @override
  Widget buildThumbnail(BuildContext context, int index) =>
      ComicPageImage(source: this, index: index, thumbnailWidth: 240);

  @override
  Future<ui.Image> renderPageImage(int index, Size targetSize) async =>
      decodePageRaster(await readPageBytes(index), targetSize);

  @override
  Future<List<TocEntry>> loadToc() async => _toc;

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _sizeRevision.dispose();
    _cache.clear();
    _cachedBytes = 0;
    await _store.dispose();
  }

  void _learnSize(int index, Size? size) {
    if (_disposed || size == null || _sizes[index] != null) return;
    _sizes[index] = size;
    if (_notifyScheduled) return;
    _notifyScheduled = true;
    scheduleMicrotask(() {
      _notifyScheduled = false;
      if (!_disposed) _sizeRevision.value++;
    });
  }

  static Size? _sizeFromBytes(Uint8List bytes) {
    final dimensions = readImageDimensions(bytes);
    if (dimensions == null) return null;
    return ComicSource.safePageSize(
      Size(dimensions.width.toDouble(), dimensions.height.toDouble()),
    );
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
