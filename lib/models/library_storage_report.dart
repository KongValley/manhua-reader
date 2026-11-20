/// Disk usage summary for the bookshelf storage manager.
/// 书架存储管理器的磁盘占用摘要。
class LibraryStorageReport {
  const LibraryStorageReport({
    required this.bookBytes,
    required this.coverBytes,
    required this.cacheBytes,
    required this.orphanBytes,
    required this.orphanFiles,
  });

  /// Bytes of files referenced by books in the shelf.
  /// 书架中书籍引用的文件字节数。
  final int bookBytes;

  /// Bytes of cover thumbnails referenced by books.
  /// 书籍引用的封面缩略图字节数。
  final int coverBytes;

  /// Bytes in the app cache directory (safe to reclaim).
  /// 应用缓存目录的字节数（可安全回收）。
  final int cacheBytes;

  /// Bytes of unreferenced files in books/ and covers/.
  /// `books/` 与 `covers/` 中未被引用文件的字节数。
  final int orphanBytes;

  /// Number of unreferenced files in books/ and covers/.
  /// `books/` 与 `covers/` 中未被引用的文件数量。
  final int orphanFiles;

  int get totalBytes => bookBytes + coverBytes;

  int get reclaimableBytes => cacheBytes + orphanBytes;
}
