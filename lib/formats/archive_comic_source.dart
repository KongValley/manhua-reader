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
class ArchiveComicSource implements ComicSource, ComicPageRenderer {
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
