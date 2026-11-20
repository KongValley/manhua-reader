import 'bookmark.dart';

enum ComicFormat {
  pdf('PDF', 'pdf'),
  mobi('MOBI', 'mobi');

  const ComicFormat(this.label, this.extension);

  /// Short label shown in the UI.
  /// UI 中显示的短标签。
  final String label;

  /// Lower-case file extension.
  /// 小写文件扩展名。
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
/// 保存在本地书架中的一本漫画。
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
    this.favorite = false,
    this.pinned = false,
    this.series,
    List<String>? tags,
    this.folderId,
    this.customCover = false,
    List<Bookmark>? bookmarks,
  }) : bookmarks = bookmarks ?? <Bookmark>[],
       tags = tags ?? <String>[];

  final String id;

  /// Display title. Can be changed from the bookshelf without touching the
  /// original file name.
  /// 书架显示标题，可在不修改原文件名的情况下重命名。
  String title;

  /// Original file name as picked by the user, used for duplicate detection.
  /// 用户选择时的原始文件名，用于重复检测。
  final String originalName;

  /// Absolute path of the imported copy inside the app library.
  ///
  /// Mutable because iOS may move the app container between launches; the
  /// repository relocates it by file name when loading the library.
  /// 应用书库中导入副本的绝对路径。
  ///
  /// 该字段可变：iOS 可能在两次启动之间移动应用容器，仓库加载书架时会
  /// 按文件名重新定位。
  String filePath;
  final ComicFormat format;
  int pageCount;
  int fileSize;
  final DateTime addedAt;

  /// Zero-based index of the last page read.
  /// 最后阅读页的零基索引。
  int lastPage;
  DateTime? lastReadAt;

  /// Absolute path of the generated cover thumbnail.
  /// 生成封面缩略图的绝对路径。
  String? coverPath;

  /// Whether [coverPath] was chosen by the user instead of being generated
  /// from the first page.
  /// [coverPath] 是否由用户选择，而不是从第一页自动生成。
  bool customCover;

  /// Whether the user starred this book.
  /// 用户是否收藏了本书。
  bool favorite;

  /// Pinned books sort before regular books.
  /// 置顶书籍排在普通书籍之前。
  bool pinned;

  /// Optional series / collection name used for grouping volumes.
  /// 可选的系列 / 合集名，用于合并展示同一系列的卷。
  String? series;

  /// Shelf folder id for books imported from a directory.
  /// 从目录导入时所属书架文件夹的 id。
  String? folderId;

  /// Free-form tags for filtering.
  /// 用于筛选的自由标签。
  List<String> tags;

  /// User-created bookmarks, kept in ascending page order.
  /// 用户创建的书签，按页码升序保存。
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
  /// 0..1 范围内的阅读进度。
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
    bool? favorite,
    bool? pinned,
    String? series,
    bool clearSeries = false,
    List<String>? tags,
    String? folderId,
    bool clearFolder = false,
    bool? customCover,
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
      favorite: favorite ?? this.favorite,
      pinned: pinned ?? this.pinned,
      series: clearSeries ? null : (series ?? this.series),
      folderId: clearFolder ? null : (folderId ?? this.folderId),
      tags: tags ?? this.tags,
      customCover: customCover ?? this.customCover,
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
    'favorite': favorite,
    'pinned': pinned,
    'series': series,
    'folderId': folderId,
    'tags': tags,
    'customCover': customCover,
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
    final tags = <String>[];
    for (final item in (json['tags'] as List? ?? const [])) {
      if (item is! String) continue;
      final tag = item.trim();
      if (tag.isEmpty || tags.contains(tag)) continue;
      tags.add(tag);
      if (tags.length >= 20) break;
    }
    final rawSeries = (json['series'] as String?)?.trim();
    final rawFolder = (json['folderId'] as String?)?.trim();
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
      favorite: json['favorite'] == true,
      pinned: json['pinned'] == true,
      series: rawSeries == null || rawSeries.isEmpty ? null : rawSeries,
      folderId: rawFolder == null || rawFolder.isEmpty ? null : rawFolder,
      tags: tags,
      customCover: json['customCover'] == true,
      bookmarks: bookmarks,
    );
  }
}
