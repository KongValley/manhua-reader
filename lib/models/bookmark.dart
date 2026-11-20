/// A reader-created bookmark at a specific page.
class Bookmark {
  Bookmark({
    required this.page,
    required this.createdAt,
    this.label,
    this.note,
  });

  /// Zero-based page index.
  final int page;
  final DateTime createdAt;

  /// Optional user-provided name. Falls back to "第 N 页".
  final String? label;

  /// Optional free-form note shown in the bookmarks panel.
  final String? note;

  String get title {
    final text = label?.trim();
    return text == null || text.isEmpty ? '第 ${page + 1} 页' : text;
  }

  bool get hasNote => note?.trim().isNotEmpty == true;

  Map<String, Object?> toJson() => {
    'page': page,
    'createdAt': createdAt.toIso8601String(),
    'label': label,
    'note': note,
  };

  factory Bookmark.fromJson(Map<String, Object?> json) {
    return Bookmark(
      page: (json['page'] as num?)?.toInt() ?? 0,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      label: json['label'] as String?,
      note: json['note'] as String?,
    );
  }
}
