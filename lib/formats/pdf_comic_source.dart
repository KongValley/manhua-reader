import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../models/toc_entry.dart';
import 'comic_source.dart';

/// PDF pages rendered by pdfrx/PDFium.
/// 由 pdfrx/PDFium 渲染的 PDF 页面。
class PdfComicSource implements ComicSource {
  PdfComicSource(this._document);

  final PdfDocument _document;

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
  }) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white24, width: 2),
            ),
          ),
        ),
        PdfPageView(
          document: _document,
          pageNumber: index + 1,
          maximumDpi: 300,
          backgroundColor: Colors.transparent,
          decoration: const BoxDecoration(color: Colors.transparent),
          decorationBuilder: onImage == null
              ? null
              : (context, pageSize, page, rawImage) {
                  final image = rawImage?.image;
                  if (image != null) onImage(image);
                  return Center(child: rawImage);
                },
        ),
      ],
    );
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
  Future<void> dispose() => _document.dispose();
}
