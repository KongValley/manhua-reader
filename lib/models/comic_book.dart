import 'bookmark.dart';
import 'reader_settings.dart';
import '../utils/pagination.dart';

enum AlbumSortField {
  name('名称'),
  created('创建时间'),
  modified('修改时间');

  const AlbumSortField(this.label);

  final String label;

  static AlbumSortField fromName(String name) {
    for (final field in values) {
      if (field.name == name) return field;
    }
    return AlbumSortField.name;
  }
}

enum ComicFormat {
  pdf('PDF', ['pdf']),
  mobi('MOBI', ['mobi']),
  cbz('CBZ', ['cbz']),
  album('相册', []);

  const ComicFormat(this.label, this.extensions);

  /// Short label shown in the UI.
  /// UI 中显示的短标签。
  final String label;

  /// Accepted lower-case file extensions, with the primary one first.
  /// 接受的小写扩展名，第一个为主扩展名。
  final List<String> extensions;

  /// Primary extension used when a new copy has no usable original name.
  /// 新副本没有可用原名时使用的主扩展名；相册没有扩展名。
  String get extension => extensions.isEmpty ? name : extensions.first;

  /// Whether this entry references an external image folder.
  /// 是否为引用外部图片文件夹的相册。
  bool get isAlbum => this == album;

  /// Every importable extension, used by file pickers and scanners.
  /// 所有可导入扩展名，供文件选择器和扫描器使用。
  static List<String> get allExtensions => [
    for (final format in values) ...format.extensions,
  ];

  static ComicFormat? fromExtension(String extension) {
    final normalized = extension.toLowerCase().replaceFirst('.', '');
    for (final format in values) {
      if (format.extensions.contains(normalized)) return format;
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
    this.albumSort = AlbumSortField.name,
    this.albumSortDescending = false,
    List<Bookmark>? bookmarks,
    this.readingMode,
    this.rightToLeft,
    this.doublePage,
    this.spreadOffset,
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

  /// Page order used by referenced image albums.
  /// 引用型图片相册使用的页面排序方式。
  AlbumSortField albumSort;

  /// Whether album page order is descending.
  /// 相册页面是否按降序排列。
  bool albumSortDescending;

  /// Per-book reading mode override. Null follows the global setting.
  /// 按书保存的阅读模式；为 null 时跟随全局设置。
  ReadingMode? readingMode;

  /// Per-book reading direction override. Null follows the global setting.
  /// 按书保存的阅读方向；为 null 时跟随全局设置。
  bool? rightToLeft;

  /// Per-book double-page override. Null follows the global setting.
  /// 按书保存的双页开关；为 null 时跟随全局设置。
  bool? doublePage;

  /// Leading single pages before double-page pairing (0–2).
  /// Null follows the global setting.
  /// 双页配对前单独显示的页数（0–2）；为 null 时跟随全局设置。
  int? spreadOffset;

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
    AlbumSortField? albumSort,
    bool? albumSortDescending,
    ReadingMode? readingMode,
    bool? rightToLeft,
    bool? doublePage,
    int? spreadOffset,
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
      albumSort: albumSort ?? this.albumSort,
      albumSortDescending: albumSortDescending ?? this.albumSortDescending,
      readingMode: readingMode ?? this.readingMode,
      rightToLeft: rightToLeft ?? this.rightToLeft,
      doublePage: doublePage ?? this.doublePage,
      spreadOffset: spreadOffset ?? this.spreadOffset,
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
    'albumSort': albumSort.name,
    'albumSortDescending': albumSortDescending,
    'readingMode': readingMode?.name,
    'rightToLeft': rightToLeft,
    'doublePage': doublePage,
    'spreadOffset': spreadOffset,
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
    final rawMode = json['readingMode'] as String?;
    final readingMode = rawMode == null
        ? null
        : ReadingMode.values.where((mode) => mode.name == rawMode).firstOrNull;
    final rawSpreadOffset = (json['spreadOffset'] as num?)?.toInt();
    final spreadOffset =
        rawSpreadOffset == null ||
            rawSpreadOffset < 0 ||
            rawSpreadOffset > maxSpreadOffset
        ? null
        : rawSpreadOffset;
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
      albumSort: AlbumSortField.fromName(json['albumSort'] as String? ?? ''),
      albumSortDescending: json['albumSortDescending'] == true,
      readingMode: readingMode,
      rightToLeft: json['rightToLeft'] as bool?,
      doublePage: json['doublePage'] as bool?,
      spreadOffset: spreadOffset,
      bookmarks: bookmarks,
    );
  }
}
