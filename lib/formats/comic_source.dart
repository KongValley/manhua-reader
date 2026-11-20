import 'package:flutter/widgets.dart';

import '../models/toc_entry.dart';

/// Common interface for a readable comic file.
///
/// [pageSize] returns the intrinsic size of a page (in any consistent unit);
/// only the aspect ratio is used for layout. [buildPage] must fill the size
/// given by its parent.
abstract class ComicSource {
  int get pageCount;

  Size pageSize(int index);

  Widget buildPage(BuildContext context, int index);

  /// A small preview used by the navigation sheet's thumbnail grid.
  Widget buildThumbnail(BuildContext context, int index);

  /// Chapters supplied by the file itself (PDF outline / MOBI headings).
  Future<List<TocEntry>> loadToc();

  Future<void> dispose();

  /// Fallback size for pages whose real size is unknown.
  static const fallbackPageSize = Size(1000, 1400);

  /// Returns a sane page size, guarding against corrupt image headers.
  static Size safePageSize(Size size) {
    final aspect = size.width / size.height;
    if (!aspect.isFinite || aspect <= 0.15 || aspect >= 6) {
      return fallbackPageSize;
    }
    return size;
  }
}

/// Raised when a comic cannot be opened (missing file, bad format, DRM, ...).
class ComicOpenException implements Exception {
  ComicOpenException(this.message);

  final String message;

  @override
  String toString() => message;
}
