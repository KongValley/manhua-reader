import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../models/toc_entry.dart';

/// Common interface for a readable comic file.
///
/// [pageSize] returns the intrinsic size of a page (in any consistent unit);
/// only the aspect ratio is used for layout. [buildPage] must fill the size
/// given by its parent.
/// 可读漫画文件的通用接口。
///
/// [pageSize] 返回页面的固有尺寸（单位保持一致即可），布局只使用宽高比。
/// [buildPage] 必须填满父组件给出的尺寸。
abstract class ComicSource {
  int get pageCount;

  Size pageSize(int index);

  /// [onImage] borrows the rendered image during the callback. Clone its handle
  /// to keep it beyond the callback.
  /// [onImage] 在回调期间借用渲染结果。需要在回调后使用时，须克隆图像句柄。
  Widget buildPage(
    BuildContext context,
    int index, {
    ValueChanged<ui.Image>? onImage,
  });

  /// A small preview used by the navigation sheet's thumbnail grid.
  /// 导航面板缩略图网格使用的小预览。
  Widget buildThumbnail(BuildContext context, int index);

  /// Chapters supplied by the file itself (PDF outline / MOBI headings).
  /// 文件自身提供的章节（PDF outline / MOBI 标题）。
  Future<List<TocEntry>> loadToc();

  Future<void> dispose();

  /// Fallback size for pages whose real size is unknown.
  /// 页面真实尺寸未知时使用的回退尺寸。
  static const fallbackPageSize = Size(1000, 1400);

  /// Returns a sane page size, guarding against corrupt image headers.
  /// 返回合理的页面尺寸，并防御损坏的图片头信息。
  static Size safePageSize(Size size) {
    final aspect = size.width / size.height;
    if (!aspect.isFinite || aspect <= 0.15 || aspect >= 6) {
      return fallbackPageSize;
    }
    return size;
  }
}

/// A source whose page sizes can be discovered after the book has opened.
/// 打开书籍后再逐步发现页面尺寸的来源。
abstract interface class ComicPageLayoutSource {
  /// Fires when one or more previously estimated page sizes become exact.
  /// 一页或多页的估算尺寸变为准确尺寸时通知。
  Listenable get pageSizesChanged;

  /// Resolves exact sizes for the requested pages without blocking the book.
  /// 按需解析指定页面的准确尺寸，不阻塞整本书打开。
  Future<void> ensurePageSizes(Iterable<int> indices);
}

/// A source that can produce a new bitmap for the requested pixel budget.
/// 能按指定像素预算生成新位图的来源。
abstract interface class ComicPageRenderer {
  /// Renders the whole page within [targetSize]. The caller owns the image.
  /// 在 [targetSize] 范围内渲染完整页面，由调用者释放图像。
  Future<ui.Image> renderPageImage(int index, Size targetSize);
}

/// Raised when a comic cannot be opened (missing file, bad format, DRM, ...).
/// 漫画无法打开时抛出（文件缺失、格式错误、DRM 等）。
class ComicOpenException implements Exception {
  ComicOpenException(this.message);

  final String message;

  @override
  String toString() => message;
}
