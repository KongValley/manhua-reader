import 'bookmark.dart';

enum ComicFormat {
  pdf('PDF', 'pdf'),
  mobi('MOBI', 'mobi');

  const ComicFormat(this.label, this.extension);

  /// Short label shown in the UI.
  final String label;

  /// Lower-case file extension.
  final String extension;

  static ComicFormat? fromExtension(String extension) {
    final normalized = extension.toLowerCase().replaceFirst('.', '');
    for (final format in values) {
      if (format.extension == normalized) return format;
    }
    return null;
  }

  static ComicFormat fromName(String name) {
    for (final format in values) {
      if (format.name == name) return format;
    }
    return ComicFormat.pdf;
  }
}

/// A comic stored in the local library.
class ComicBook {
  ComicBook({
    required this.id,
    required this.title,
    required this.originalName,
    required this.filePath,
    required this.format,
    required this.pageCount,
    required this.fileSize,
    required this.addedAt,
    this.lastPage = 0,
    this.lastReadAt,
    this.coverPath,
    List<Bookmark>? bookmarks,
  }) : bookmarks = bookmarks ?? <Bookmark>[];

  final String id;
  final String title;

  /// Original file name as picked by the user, used for duplicate detection.
  final String originalName;

  /// Absolute path of the imported copy inside the app library.
  ///
  /// Mutable because iOS may move the app container between launches; the
  /// repository relocates it by file name when loading the library.
  String filePath;
  final ComicFormat format;
  int pageCount;
  final int fileSize;
  final DateTime addedAt;

  /// Zero-based index of the last page read.
  int lastPage;
  DateTime? lastReadAt;

  /// Absolute path of the generated cover thumbnail.
  String? coverPath;

  /// User-created bookmarks, kept in ascending page order.
  final List<Bookmark> bookmarks;

  Bookmark? bookmarkAt(int page) {
    for (final bookmark in bookmarks) {
      if (bookmark.page == page) return bookmark;
    }
    return null;
  }

  bool isBookmarked(int page) => bookmarkAt(page) != null;

  int get safeLastPage {
    if (pageCount <= 0) return 0;
    return lastPage.clamp(0, pageCount - 1);
  }

  /// Reading progress in the range 0..1.
  double get progress {
    if (pageCount <= 0) return 0;
    return ((safeLastPage + 1) / pageCount).clamp(0.0, 1.0);
  }

  bool get hasStarted => lastReadAt != null;

  DateTime get lastActivity => lastReadAt ?? addedAt;

  ComicBook copyWith({
    String? title,
    int? lastPage,
    DateTime? lastReadAt,
    String? coverPath,
  }) {
    return ComicBook(
      id: id,
      title: title ?? this.title,
      originalName: originalName,
      filePath: filePath,
      format: format,
      pageCount: pageCount,
      fileSize: fileSize,
      addedAt: addedAt,
      lastPage: lastPage ?? this.lastPage,
      lastReadAt: lastReadAt ?? this.lastReadAt,
      coverPath: coverPath ?? this.coverPath,
      bookmarks: bookmarks,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'originalName': originalName,
    'filePath': filePath,
    'format': format.name,
    'pageCount': pageCount,
    'fileSize': fileSize,
    'addedAt': addedAt.toIso8601String(),
    'lastPage': lastPage,
    'lastReadAt': lastReadAt?.toIso8601String(),
    'coverPath': coverPath,
    'bookmarks': bookmarks.map((bookmark) => bookmark.toJson()).toList(),
  };

  factory ComicBook.fromJson(Map<String, Object?> json) {
    final filePath = json['filePath'] as String? ?? '';
    final formatName = json['format'] as String? ?? '';
    final inferred = formatName.isEmpty
        ? ComicFormat.fromExtension(
            filePath.contains('.') ? filePath.split('.').last : '',
          )
        : null;
    final pageCount = (json['pageCount'] as num?)?.toInt() ?? 0;
    final bookmarks =
        <Bookmark>[
            for (final item in (json['bookmarks'] as List? ?? const []))
              if (item is Map)
                Bookmark.fromJson(
                  item.map((key, value) => MapEntry('$key', value)),
                ),
          ]
          ..removeWhere(
            (bookmark) => bookmark.page < 0 || bookmark.page >= pageCount,
          )
          ..sort((a, b) => a.page.compareTo(b.page));

    return ComicBook(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '未命名',
      originalName: json['originalName'] as String? ?? '',
      filePath: filePath,
      format: inferred ?? ComicFormat.fromName(formatName),
      pageCount: pageCount,
      fileSize: (json['fileSize'] as num?)?.toInt() ?? 0,
      addedAt:
          DateTime.tryParse(json['addedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      lastPage: (json['lastPage'] as num?)?.toInt() ?? 0,
      lastReadAt: DateTime.tryParse(json['lastReadAt'] as String? ?? ''),
      coverPath: json['coverPath'] as String?,
      bookmarks: bookmarks,
    );
  }
}
