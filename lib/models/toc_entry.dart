/// One entry in a comic's table of contents.
class TocEntry {
  const TocEntry({required this.title, required this.page, this.level = 0});

  final String title;

  /// Zero-based page index.
  final int page;

  /// Nesting depth (0 = top-level chapter).
  final int level;
}
