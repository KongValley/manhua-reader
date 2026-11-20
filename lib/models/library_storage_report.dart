/// Disk usage summary for the bookshelf storage manager.
class LibraryStorageReport {
  const LibraryStorageReport({
    required this.bookBytes,
    required this.coverBytes,
    required this.cacheBytes,
    required this.orphanBytes,
    required this.orphanFiles,
  });

  /// Bytes of files referenced by books in the shelf.
  final int bookBytes;

  /// Bytes of cover thumbnails referenced by books.
  final int coverBytes;

  /// Bytes in the app cache directory (safe to reclaim).
  final int cacheBytes;

  /// Bytes of unreferenced files in books/ and covers/.
  final int orphanBytes;

  /// Number of unreferenced files in books/ and covers/.
  final int orphanFiles;

  int get totalBytes => bookBytes + coverBytes;

  int get reclaimableBytes => cacheBytes + orphanBytes;
}
