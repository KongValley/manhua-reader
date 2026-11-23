import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../models/toc_entry.dart';
import '../widgets/comic_page_image.dart';
import 'comic_source.dart';
import 'page_raster.dart';

/// PDF pages rendered by pdfrx/PDFium.
/// 由 pdfrx/PDFium 渲染的 PDF 页面。
class PdfComicSource implements ComicSource, ComicPageRenderer {
  PdfComicSource(this._document);

  final PdfDocument _document;
  final _renders = <PdfPageRenderCancellationToken>{};
  bool _disposed = false;

  PdfDocument get document => _document;

  @override
  int get pageCount => _document.pages.length;

  @override
  Size pageSize(int index) =>
      ComicSource.safePageSize(_document.pages[index].size);

  @override
  Widget buildPage(
    BuildContext context,
    int index, {
    ValueChanged<ui.Image>? onImage,
  }) => ComicPageImage(source: this, index: index, onImage: onImage);

  @override
  Future<ui.Image> renderPageImage(int index, Size targetSize) async {
    if (_disposed) throw StateError('PDF source is closed');
    final page = _document.pages[index];
    final size = fitPageRasterSize(page.size, targetSize);
    final token = page.createCancellationToken();
    _renders.add(token);
    try {
      final image = await page.renderForDisplay(
        fullWidth: size.width,
        fullHeight: size.height,
        cancellationToken: token,
      );
      if (_disposed || image == null) {
        image?.dispose();
        throw StateError('PDF page could not be rendered');
      }
      return image;
    } finally {
      _renders.remove(token);
    }
  }

  @override
  Widget buildThumbnail(BuildContext context, int index) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Color(0xFF1B1E25)),
        PdfPageView(
          document: _document,
          pageNumber: index + 1,
          maximumDpi: 96,
          backgroundColor: Colors.transparent,
          decoration: const BoxDecoration(color: Colors.transparent),
        ),
      ],
    );
  }

  @override
  Future<List<TocEntry>> loadToc() async {
    try {
      final outline = await _document.loadOutline();
      final entries = <TocEntry>[];
      void walk(List<PdfOutlineNode> nodes, int level) {
        for (final node in nodes) {
          final pageNumber = node.dest?.pageNumber;
          final title = node.title.replaceAll(RegExp(r'\s+'), ' ').trim();
          if (pageNumber != null &&
              pageNumber >= 1 &&
              pageNumber <= pageCount) {
            entries.add(
              TocEntry(
                title: title.isEmpty ? '第 $pageNumber 页' : title,
                page: pageNumber - 1,
                level: level,
              ),
            );
          }
          if (node.children.isNotEmpty) {
            walk(node.children, level + 1);
          }
        }
      }

      walk(outline, 0);
      return entries;
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final token in _renders) {
      token.cancel();
    }
    await _document.dispose();
  }
}
