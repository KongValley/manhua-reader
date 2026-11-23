import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../models/toc_entry.dart';
import '../widgets/comic_page_image.dart';
import 'comic_source.dart';
import 'page_raster.dart';
import 'zip/image_size.dart';
import 'zip/zip_archive_reader.dart';

/// CBZ comics (ZIP container): every image entry is one page.
/// CBZ 漫画（ZIP 容器）：每个图片条目对应一页。
class ArchiveComicSource
    implements ComicSource, ComicPageRenderer, ComicPageLayoutSource {
  ArchiveComicSource._(this._reader, this._sizes, this._defaultSize, this._toc);

  final ZipArchiveReader _reader;
  final List<Size?> _sizes;
  final Size _defaultSize;
  final List<TocEntry> _toc;
  final ValueNotifier<int> _sizeRevision = ValueNotifier<int>(0);
  final Set<int> _probing = <int>{};
  bool _notifyScheduled = false;
  bool _disposed = false;

  /// Number of image headers inspected. Tests use this to guard lazy opening.
  /// 已检查的图片头数量。测试用它确认打开时不会扫描全书。
  @visibleForTesting
  static int debugSizeProbes = 0;

  static Future<ArchiveComicSource> open(String filePath) async {
    final reader = await ZipArchiveReader.open(filePath);
    try {
      final sizes = List<Size?>.filled(reader.pages.length, null);
      Size? first;
      Size? body;
      if (reader.pages.isNotEmpty) {
        first = await _probeSize(reader, 0);
        sizes[0] = first;
      }
      if (reader.pages.length > 1) {
        body = await _probeSize(reader, 1);
        sizes[1] = body;
      }
      return ArchiveComicSource._(
        reader,
        sizes,
        body ?? first ?? ComicSource.fallbackPageSize,
        _buildToc(reader.pages),
      );
    } catch (_) {
      await reader.dispose();
      rethrow;
    }
  }

  @override
  int get pageCount => _reader.pages.length;

  @override
  Size pageSize(int index) => _sizes[index] ?? _defaultSize;

  @override
  Listenable get pageSizesChanged => _sizeRevision;

  @override
  Future<void> ensurePageSizes(Iterable<int> indices) async {
    for (final index in indices.toSet()) {
      if (_disposed || index < 0 || index >= pageCount) continue;
      if (_sizes[index] != null || !_probing.add(index)) continue;
      try {
        final size = await _probeSize(_reader, index);
        if (size != null) _learnSize(index, size);
      } finally {
        _probing.remove(index);
      }
    }
  }

  Future<Uint8List> readPageBytes(int index) async {
    final bytes = await _reader.readPageBytes(index);
    _learnSize(index, _sizeFromBytes(bytes));
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
    await _reader.dispose();
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

  static Future<Size?> _probeSize(ZipArchiveReader reader, int index) async {
    debugSizeProbes++;
    try {
      return _sizeFromBytes(await reader.readPagePrefix(index));
    } catch (_) {
      return null;
    }
  }

  static Size? _sizeFromBytes(Uint8List bytes) {
    final dimensions = readImageDimensions(bytes);
    if (dimensions == null) return null;
    return ComicSource.safePageSize(
      Size(dimensions.width.toDouble(), dimensions.height.toDouble()),
    );
  }

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
