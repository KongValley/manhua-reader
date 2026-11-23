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

/// Reads a referenced folder of images as one comic album.
/// 将引用的图片文件夹作为一本相册读取。
class AlbumComicSource implements ComicSource, ComicPageRenderer {
  AlbumComicSource._(this._store, this._images, this._sizes, this._toc);

  final AlbumStore _store;
  final List<AlbumImage> _images;
  final List<Size> _sizes;
  final List<TocEntry> _toc;

  final LinkedHashMap<int, Uint8List> _cache = LinkedHashMap<int, Uint8List>();
  int _cachedBytes = 0;
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
