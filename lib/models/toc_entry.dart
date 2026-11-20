/// One entry in a comic's table of contents.
/// 漫画目录中的一个条目。
class TocEntry {
  const TocEntry({required this.title, required this.page, this.level = 0});

  final String title;

  /// Zero-based page index.
  /// 零基页码。
  final int page;

  /// Nesting depth (0 = top-level chapter).
  /// 嵌套深度（0 表示顶层章节）。
  final int level;
}
