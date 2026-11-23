import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../models/toc_entry.dart';
import '../widgets/comic_page_image.dart';
import 'comic_source.dart';
import 'mobi/mobi_book.dart';
import 'page_raster.dart';

/// MOBI comics: every page is one embedded image record.
/// MOBI 漫画：每一页对应一条内嵌图片记录。
class MobiComicSource implements ComicSource, ComicPageRenderer {
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
      decodePageRaster(await book.readPage(index), targetSize);

  @override
  Future<List<TocEntry>> loadToc() async => book.toc;

  @override
  Future<void> dispose() => book.dispose();
}
