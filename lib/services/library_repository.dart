import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import '../formats/album/album_store.dart';
import '../formats/archive_comic_source.dart';
import '../formats/mobi/mobi_book.dart';
import '../formats/zip/zip_archive_reader.dart';
import '../models/bookmark.dart';
import '../models/comic_book.dart';
import '../models/library_folder.dart';
import '../models/library_settings.dart';
import '../models/library_storage_report.dart';
import '../models/reader_settings.dart';
import '../models/reading_stats.dart';
import '../utils/series.dart';
import 'app_paths.dart';
import 'cover_generator.dart';
import 'library_index.dart';
import 'pdf_password_cache.dart';
import 'saf_album_service.dart';

class ImportException implements Exception {
  ImportException(this.message);

  final String message;

  @override
  String toString() => message;
}

typedef ImportProgressCallback = void Function(String label, double progress);

/// Owns the bookshelf, import pipeline, covers and reading progress.
/// 负责书架状态、导入流水线、封面与阅读进度。
class LibraryRepository extends ChangeNotifier {
  LibraryRepository(this.paths);

  final AppPaths paths;

  final List<ComicBook> _books = [];
  final List<LibraryFolder> _folders = [];
  ReaderSettings settings = ReaderSettings();
  LibrarySettings librarySettings = LibrarySettings();
  ReadingStats stats = ReadingStats();

  final LibraryIndex _index = LibraryIndex();

  Timer? _saveTimer;
  bool _saved = false;
  bool _saving = false;
  bool _dirty = false;

  bool get isLoaded => _saved;
  bool get isEmpty => _books.isEmpty;
  int get bookCount => _books.length;

  List<ComicBook> get books => List<ComicBook>.unmodifiable(_books);

  List<String> get seriesNames => _index.seriesNames;
  List<String> get tagNames => _index.tagNames;
  Map<String, int> get seriesCounts => _index.seriesCounts;
  Map<String, int> get tagCounts => _index.tagCounts;

  bool matchesSearch(ComicBook book, String query) {
    if (_index.matches(book, query)) return true;
    final folderName = folderById(book.folderId)?.name.toLowerCase();
    return folderName != null && folderName.contains(query);
  }

  List<LibraryFolder> get folders => List<LibraryFolder>.unmodifiable(_folders);

  LibraryFolder? folderById(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final folder in _folders) {
      if (folder.id == id) return folder;
    }
    return null;
  }

  Map<String, int> get folderCounts {
    final counts = {for (final folder in _folders) folder.id: 0};
    for (final book in _books) {
      final id = book.folderId;
      if (id == null) continue;
      if (counts.containsKey(id)) counts[id] = counts[id]! + 1;
    }
    return counts;
  }

  ComicBook? get lastRead {
    ComicBook? latest;
    for (final book in _books) {
      final readAt = book.lastReadAt;
      if (readAt == null) continue;
      if (latest == null || readAt.isAfter(latest.lastReadAt!)) {
        latest = book;
      }
    }
    return latest;
  }

  bool fileExists(ComicBook book) {
    if (book.format.isAlbum) {
      if (book.filePath.startsWith('content://')) return true;
      return Directory(book.filePath).existsSync();
    }
    return File(book.filePath).existsSync();
  }

  Future<void> load() async {
    var loadedVersion = 1;
    try {
      final file = paths.libraryFile;
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map<String, dynamic>) {
          loadedVersion = (decoded['version'] as num?)?.toInt() ?? 1;
          final booksJson = decoded['books'];
          if (booksJson is List) {
            _books
              ..clear()
              ..addAll(
                booksJson
                    .whereType<Map>()
                    .map(
                      (json) => ComicBook.fromJson(
                        json.map((key, value) => MapEntry('$key', value)),
                      ),
                    )
                    .where(
                      (book) => book.id.isNotEmpty && book.filePath.isNotEmpty,
                    ),
              );
          }
          final foldersJson = decoded['folders'];
          _folders.clear();
          if (foldersJson is List) {
            _folders.addAll(
              foldersJson
                  .whereType<Map>()
                  .map(
                    (json) => LibraryFolder.fromJson(
                      json.map((key, value) => MapEntry('$key', value)),
                    ),
                  )
                  .where(
                    (folder) =>
                        folder.id.isNotEmpty && folder.name.trim().isNotEmpty,
                  ),
            );
          }
          settings = ReaderSettings.fromJson(
            decoded['settings'] is Map
                ? (decoded['settings'] as Map).map(
                    (key, value) => MapEntry('$key', value),
                  )
                : null,
          );
          librarySettings = LibrarySettings.fromJson(
            decoded['library'] is Map
                ? (decoded['library'] as Map).map(
                    (key, value) => MapEntry('$key', value),
                  )
                : null,
          );
          stats = ReadingStats.fromJson(
            decoded['stats'] is Map
                ? (decoded['stats'] as Map).map(
                    (key, value) => MapEntry('$key', value),
                  )
                : null,
          );
        }
      }
    } catch (error, stack) {
      debugPrint('Library load failed: $error\n$stack');
    }

    if (loadedVersion < 3) {
      // Version 3 introduces series/tag organization. Derive a series hint
      // from titles such as "VOL.001" or "海贼王 第12卷" once during migration.
      // 版本 3 引入系列/标签组织。迁移时从 "VOL.001" 或 "海贼王 第12卷"
      // 这类标题中推导一次系列提示。
      for (final book in _books) {
        book.series ??= deriveSeriesName(book.title, book.originalName);
      }
    }

    for (final book in _books) {
      // iOS can move the app container between launches. Fall back to the
      // current app directories when an absolute path is stale.
      // iOS 可能在两次启动之间移动应用容器；绝对路径失效时回退到当前
      // 应用目录。
      if (!book.format.isAlbum && !File(book.filePath).existsSync()) {
        final candidate = File(
          p.join(paths.booksDir.path, p.basename(book.filePath)),
        );
        if (candidate.existsSync()) book.filePath = candidate.path;
      }
      final coverPath = book.coverPath;
      if (coverPath != null && !File(coverPath).existsSync()) {
        final candidate = File(
          p.join(paths.coversDir.path, p.basename(coverPath)),
        );
        book.coverPath = candidate.existsSync() ? candidate.path : null;
      }
    }
    final folderIds = {for (final folder in _folders) folder.id};
    for (final book in _books) {
      if (book.folderId != null && !folderIds.contains(book.folderId)) {
        book.folderId = null;
      }
    }
    _index.rebuild(_books);
    _sortBooks();
    _saved = true;
    notifyListeners();
  }

  Future<ComicBook> importFile(
    String sourcePath, {
    String? originalName,
    String? folderId,
    ImportProgressCallback? onProgress,
    PdfPasswordProvider? pdfPasswordProvider,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw ImportException('文件不存在：$sourcePath');
    }

    final name = originalName ?? p.basename(sourcePath);
    final format = ComicFormat.fromExtension(p.extension(name));
    if (format == null) {
      throw ImportException('仅支持 PDF、MOBI、CBZ 格式');
    }

    final fileSize = await source.length();
    _checkDuplicate(name, fileSize);

    final id = _newId();
    final destination = File(
      p.join(paths.booksDir.path, '$id.${_storageExtension(name, format)}'),
    );
    final part = File('${destination.path}.part');
    try {
      await _copyWithProgress(
        source,
        part,
        (value) => onProgress?.call('正在复制 $name', value * 0.78),
      );
      await part.rename(destination.path);
      return await _registerImportedFile(
        destination: destination,
        format: format,
        originalName: name,
        id: id,
        folderId: folderId,
        onProgress: onProgress,
        pdfPasswordProvider: pdfPasswordProvider,
      );
    } catch (error, stack) {
      return _handleImportFailure(
        error,
        stack,
        destination: destination,
        id: id,
      );
    }
  }

  /// Imports a file exposed by a platform picker (Android SAF content URIs
  /// cannot always be represented by a local path).
  /// 导入平台文件选择器提供的文件（Android SAF content URI 不一定能表示为
  /// 本地路径）。
  Future<ComicBook> importStream({
    required String originalName,
    required Stream<List<int>> stream,
    int? totalSize,
    String? folderId,
    ImportProgressCallback? onProgress,
    PdfPasswordProvider? pdfPasswordProvider,
  }) async {
    final format = ComicFormat.fromExtension(p.extension(originalName));
    if (format == null) {
      throw ImportException('仅支持 PDF、MOBI、CBZ 格式');
    }
    if (totalSize != null) {
      _checkDuplicate(originalName, totalSize);
    }

    final id = _newId();
    final destination = File(
      p.join(
        paths.booksDir.path,
        '$id.${_storageExtension(originalName, format)}',
      ),
    );
    final part = File('${destination.path}.part');
    try {
      final sink = part.openWrite();
      var copied = 0;
      var lastReport = 0;
      final stopwatch = Stopwatch()..start();
      try {
        await for (final chunk in stream) {
          sink.add(chunk);
          copied += chunk.length;
          if (stopwatch.elapsedMilliseconds - lastReport > 120) {
            lastReport = stopwatch.elapsedMilliseconds;
            final fraction = totalSize != null && totalSize > 0
                ? (copied / totalSize).clamp(0.0, 1.0)
                : 0.0;
            onProgress?.call('正在复制 $originalName', fraction * 0.78);
          }
        }
      } finally {
        await sink.close();
      }
      if (totalSize == null) {
        _checkDuplicate(originalName, await part.length());
      }
      await part.rename(destination.path);

      return await _registerImportedFile(
        destination: destination,
        format: format,
        originalName: originalName,
        id: id,
        folderId: folderId,
        onProgress: onProgress,
        pdfPasswordProvider: pdfPasswordProvider,
      );
    } catch (error, stack) {
      return _handleImportFailure(
        error,
        stack,
        destination: destination,
        id: id,
      );
    }
  }

  /// Adds a local image folder as a referenced album without copying images.
  /// 将本地图片文件夹作为引用型相册加入书架，不复制图片。
  Future<ComicBook> importAlbumDirectory(
    Directory directory, {
    String? folderId,
    ImportProgressCallback? onProgress,
  }) {
    return _importAlbum(
      store: FileAlbumStore(directory.path),
      source: directory.path,
      name: p.basename(directory.path),
      folderId: folderId,
      onProgress: onProgress,
    );
  }

  /// Adds an Android SAF image folder as a referenced album.
  /// 将 Android SAF 图片文件夹作为引用型相册加入书架。
  Future<ComicBook> importSafAlbum({
    required String treeUri,
    required String name,
    String? folderId,
    ImportProgressCallback? onProgress,
  }) {
    return _importAlbum(
      store: SafAlbumStore(treeUri),
      source: treeUri,
      name: name,
      folderId: folderId,
      onProgress: onProgress,
    );
  }

  Future<ComicBook> _importAlbum({
    required AlbumStore store,
    required String source,
    required String name,
    String? folderId,
    ImportProgressCallback? onProgress,
  }) async {
    File? coverFile;
    try {
      onProgress?.call('正在扫描相册', 0.15);
      final images = await store.list();
      if (images.isEmpty) {
        throw ImportException('相册文件夹里没有图片');
      }
      final totalSize = images.fold<int>(0, (sum, image) => sum + image.size);
      final title = name.trim().isEmpty ? '图片相册' : name.trim();
      _checkDuplicate(title, totalSize);

      onProgress?.call('正在生成封面', 0.7);
      final id = _newId();
      coverFile = File(p.join(paths.coversDir.path, '$id.png'));
      String? coverPath;
      try {
        final firstImage = await store.readBytes(images.first);
        coverPath = await CoverGenerator.fromImageBytes(
          firstImage,
          coverFile.path,
        );
      } catch (error) {
        debugPrint('Album cover generation failed: $error');
      }

      final book = ComicBook(
        id: id,
        title: title,
        originalName: title,
        filePath: source,
        format: ComicFormat.album,
        pageCount: images.length,
        fileSize: totalSize,
        addedAt: DateTime.now(),
        coverPath: coverPath,
        folderId: folderId,
      );
      _books.add(book);
      _index.upsert(book);
      _sortBooks();
      notifyListeners();
      await _saveNow();
      onProgress?.call('导入完成', 1);
      return book;
    } on ImportException {
      rethrow;
    } on AlbumSourceException catch (error) {
      throw ImportException(error.message);
    } catch (error, stack) {
      debugPrint('Album import failed: $error\n$stack');
      if (coverFile != null) await _deleteQuietly(coverFile);
      throw ImportException('无法导入相册：$error');
    } finally {
      await store.dispose();
    }
  }

  Future<ComicBook> _registerImportedFile({
    required File destination,
    required ComicFormat format,
    required String originalName,
    required String id,
    String? folderId,
    ImportProgressCallback? onProgress,
    PdfPasswordProvider? pdfPasswordProvider,
  }) async {
    final fileSize = await destination.length();
    String? coverPath;
    try {
      final info = await _inspectComic(
        file: destination,
        format: format,
        coverId: id,
        fallbackTitle: p.basenameWithoutExtension(originalName),
        pdfPasswordProvider: pdfPasswordProvider,
        onProgress: onProgress,
      );
      coverPath = info.coverPath;

      final book = ComicBook(
        id: id,
        title: _cleanTitle(info.title),
        originalName: originalName,
        filePath: destination.path,
        format: format,
        pageCount: info.pageCount,
        fileSize: fileSize,
        addedAt: DateTime.now(),
        coverPath: coverPath,
        series: deriveSeriesName(info.title, originalName),
        folderId: folderId,
      );

      _books.insert(0, book);
      _index.upsert(book);
      await _saveNow();
      notifyListeners();
      onProgress?.call('导入完成', 1);
      return book;
    } catch (error) {
      if (coverPath != null) await _deleteQuietly(File(coverPath));
      rethrow;
    }
  }

  Future<_InspectedComic> _inspectComic({
    required File file,
    required ComicFormat format,
    required String coverId,
    required String fallbackTitle,
    PdfPasswordProvider? pdfPasswordProvider,
    ImportProgressCallback? onProgress,
  }) async {
    onProgress?.call('正在解析漫画信息', 0.82);

    if (format == ComicFormat.cbz) {
      final archive = await ArchiveComicSource.open(file.path);
      try {
        if (archive.pageCount == 0) {
          throw ImportException('压缩包里没有可显示的图片');
        }
        onProgress?.call('正在生成封面', 0.9);
        final cover = File(p.join(paths.coversDir.path, '$coverId.png'));
        final firstPage = await archive.readPageBytes(0);
        final coverPath = await CoverGenerator.fromImageBytes(
          firstPage,
          cover.path,
        );
        return _InspectedComic(
          title: fallbackTitle,
          pageCount: archive.pageCount,
          coverPath: coverPath,
        );
      } finally {
        await archive.dispose();
      }
    }

    if (format == ComicFormat.mobi) {
      final mobi = await MobiBook.open(file.path, fallbackTitle: fallbackTitle);
      onProgress?.call('正在生成封面', 0.9);
      final cover = File(p.join(paths.coversDir.path, '$coverId.png'));
      final firstPage = await mobi.readPage(0);
      final coverPath = await CoverGenerator.fromImageBytes(
        firstPage,
        cover.path,
      );
      return _InspectedComic(
        title: mobi.title,
        pageCount: mobi.pageCount,
        coverPath: coverPath,
      );
    }

    final document = await PdfDocument.openFile(
      file.path,
      passwordProvider: pdfPasswordProvider,
    );
    try {
      final pageCount = document.pages.length;
      if (pageCount == 0) {
        throw ImportException('PDF 没有可显示的页面');
      }
      onProgress?.call('正在生成封面', 0.9);
      final cover = File(p.join(paths.coversDir.path, '$coverId.png'));
      final coverPath = await CoverGenerator.fromPdf(document, cover.path);
      return _InspectedComic(
        title: fallbackTitle,
        pageCount: pageCount,
        coverPath: coverPath,
      );
    } finally {
      await document.dispose();
    }
  }

  Future<ComicBook> _handleImportFailure(
    Object error,
    StackTrace stack, {
    required File destination,
    required String id,
  }) async {
    debugPrint('Import failed: $error\n$stack');
    await _deleteQuietly(File('${destination.path}.part'));
    await _deleteQuietly(destination);
    await _deleteQuietly(File(p.join(paths.coversDir.path, '$id.png')));
    if (error is ImportException) throw error;
    if (error is ZipArchiveException) throw ImportException(error.message);
    if (error is MobiException) throw ImportException(error.message);
    throw ImportException('无法导入该文件：${_friendlyError(error)}');
  }

  /// Replaces a missing (or broken) file for an existing bookshelf entry while
  /// keeping its id, title, progress and bookmarks.
  /// 为已有书架条目替换丢失（或损坏）的文件，同时保留 id、标题、进度和书签。
  Future<ComicBook> relinkFile(
    ComicBook book,
    String sourcePath, {
    ImportProgressCallback? onProgress,
    PdfPasswordProvider? pdfPasswordProvider,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw ImportException('文件不存在：$sourcePath');
    }
    final format = ComicFormat.fromExtension(p.extension(sourcePath));
    if (format == null || format != book.format) {
      throw ImportException('请选择 ${book.format.label} 格式的文件');
    }

    final stamp = DateTime.now().millisecondsSinceEpoch;
    final destination = File(
      p.join(
        paths.booksDir.path,
        '${book.id}_r$stamp.${_storageExtension(sourcePath, format)}',
      ),
    );
    final part = File('${destination.path}.part');
    final coverId = '${book.id}_c$stamp';
    String? newCoverPath;
    try {
      await _copyWithProgress(
        source,
        part,
        (value) =>
            onProgress?.call('正在复制 ${p.basename(sourcePath)}', value * 0.7),
      );
      await part.rename(destination.path);
      final info = await _inspectComic(
        file: destination,
        format: book.format,
        coverId: coverId,
        fallbackTitle: book.title,
        pdfPasswordProvider: pdfPasswordProvider,
        onProgress: (label, value) =>
            onProgress?.call(label, 0.7 + value * 0.3),
      );
      newCoverPath = info.coverPath;

      final oldFile = File(book.filePath);
      final oldCover = book.coverPath;
      book.filePath = destination.path;
      book.pageCount = info.pageCount;
      book.fileSize = await destination.length();
      book.coverPath = newCoverPath;
      book.customCover = false;
      book.lastPage = _clampPage(book.lastPage, book.pageCount);
      book.bookmarks.removeWhere(
        (bookmark) => bookmark.page < 0 || bookmark.page >= book.pageCount,
      );
      await _saveNow();
      notifyListeners();
      PdfPasswordCache.remove(oldFile.path);
      await _deleteQuietly(oldFile);
      if (oldCover != null && oldCover != newCoverPath) {
        await _deleteQuietly(File(oldCover));
      }
      onProgress?.call('重新定位完成', 1);
      return book;
    } catch (error, stack) {
      debugPrint('Relink failed: $error\n$stack');
      await _deleteQuietly(part);
      await _deleteQuietly(destination);
      await _deleteQuietly(File(p.join(paths.coversDir.path, '$coverId.png')));
      if (newCoverPath != null) await _deleteQuietly(File(newCoverPath));
      if (error is ImportException) rethrow;
      if (error is ZipArchiveException) throw ImportException(error.message);
      if (error is MobiException) throw ImportException(error.message);
      throw ImportException('无法重新定位文件：${_friendlyError(error)}');
    }
  }

  /// Rebuilds a cover in a new file so Flutter's image cache sees the change.
  /// 在新文件中重建封面，使 Flutter 图片缓存能够感知变化。
  /// Replaces the source folder of a referenced album while keeping metadata.
  /// 更换引用型相册的源文件夹，同时保留标题、进度与书签。
  Future<ComicBook> relinkAlbum(
    ComicBook book, {
    required String source,
    ImportProgressCallback? onProgress,
  }) async {
    final store = createAlbumStore(source);
    final oldPath = book.filePath;
    final oldCover = book.coverPath;
    String? newCoverPath;
    try {
      onProgress?.call('正在扫描相册', 0.2);
      final images = await store.list();
      final totalSize = images.fold<int>(0, (sum, image) => sum + image.size);
      onProgress?.call('正在生成封面', 0.7);
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final cover = File(
        p.join(paths.coversDir.path, '${book.id}_c$stamp.png'),
      );
      try {
        final firstImage = await store.readBytes(images.first);
        newCoverPath = await CoverGenerator.fromImageBytes(
          firstImage,
          cover.path,
        );
      } catch (error) {
        debugPrint('Album relink cover failed: $error');
      }

      book.filePath = source;
      book.pageCount = images.length;
      book.fileSize = totalSize;
      book.lastPage = _clampPage(book.lastPage, book.pageCount);
      book.bookmarks.removeWhere(
        (bookmark) => bookmark.page < 0 || bookmark.page >= book.pageCount,
      );
      if (newCoverPath != null) {
        book.coverPath = newCoverPath;
        book.customCover = false;
      }
      await _saveNow();
      notifyListeners();
      if (oldCover != null &&
          newCoverPath != null &&
          oldCover != newCoverPath) {
        await _deleteQuietly(File(oldCover));
      }
      if (oldPath != source && oldPath.startsWith('content://')) {
        await _releaseAlbumTreeIfUnused(oldPath);
      }
      onProgress?.call('重新定位完成', 1);
      return book;
    } on ImportException {
      rethrow;
    } on AlbumSourceException catch (error) {
      if (newCoverPath != null) await _deleteQuietly(File(newCoverPath));
      throw ImportException(error.message);
    } catch (error, stack) {
      debugPrint('Album relink failed: $error\n$stack');
      if (newCoverPath != null) await _deleteQuietly(File(newCoverPath));
      throw ImportException('无法重新定位相册：$error');
    } finally {
      await store.dispose();
    }
  }

  Future<bool> regenerateCover(
    ComicBook book, {
    ImportProgressCallback? onProgress,
    PdfPasswordProvider? pdfPasswordProvider,
  }) async {
    if (book.format.isAlbum) {
      try {
        await relinkAlbum(book, source: book.filePath, onProgress: onProgress);
        return true;
      } catch (_) {
        return false;
      }
    }

    final file = File(book.filePath);
    if (!await file.exists()) return false;

    final stamp = DateTime.now().millisecondsSinceEpoch;
    final coverId = '${book.id}_c$stamp';
    final cover = File(p.join(paths.coversDir.path, '$coverId.png'));
    String? newCoverPath;
    try {
      final info = await _inspectComic(
        file: file,
        format: book.format,
        coverId: coverId,
        fallbackTitle: book.title,
        pdfPasswordProvider: pdfPasswordProvider,
        onProgress: onProgress,
      );
      if (info.coverPath == null) return false;
      newCoverPath = info.coverPath;
      final oldCover = book.coverPath;
      book.coverPath = newCoverPath;
      book.customCover = false;
      if (book.pageCount != info.pageCount) {
        book.pageCount = info.pageCount;
        book.lastPage = _clampPage(book.lastPage, book.pageCount);
        book.bookmarks.removeWhere(
          (bookmark) => bookmark.page < 0 || bookmark.page >= book.pageCount,
        );
      }
      await _saveNow();
      notifyListeners();
      if (oldCover != null && oldCover != newCoverPath) {
        await _deleteQuietly(File(oldCover));
      }
      return true;
    } catch (error, stack) {
      debugPrint('Cover regeneration failed: $error\n$stack');
      await _deleteQuietly(cover);
      if (newCoverPath != null) await _deleteQuietly(File(newCoverPath));
      return false;
    }
  }

  /// Replaces the cover with a user-picked image, normalised to a 520px PNG.
  /// 用用户选择的图片替换封面，并规范化为 520px PNG。
  Future<bool> setCustomCover(ComicBook book, Uint8List bytes) async {
    if (bytes.isEmpty) return false;
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final cover = File(p.join(paths.coversDir.path, '${book.id}_u$stamp.png'));
    final newPath = await CoverGenerator.fromImageBytes(bytes, cover.path);
    if (newPath == null) {
      await _deleteQuietly(cover);
      return false;
    }
    final oldCover = book.coverPath;
    book.coverPath = newPath;
    book.customCover = true;
    await _saveNow();
    notifyListeners();
    if (oldCover != null && oldCover != newPath) {
      await _deleteQuietly(File(oldCover));
    }
    return true;
  }

  Future<LibraryStorageReport> storageReport() async {
    final bookPaths = {for (final book in _books) _pathKey(book.filePath)};
    final coverPaths = {
      for (final book in _books)
        if (book.coverPath != null) _pathKey(book.coverPath!),
    };

    var bookBytes = 0;
    var coverBytes = 0;
    var cacheBytes = 0;
    var orphanBytes = 0;
    var orphanFiles = 0;

    await _walkFiles(paths.booksDir, false, (file, size) {
      if (bookPaths.contains(_pathKey(file.path))) {
        bookBytes += size;
      } else {
        orphanBytes += size;
        orphanFiles++;
      }
    });
    await _walkFiles(paths.coversDir, false, (file, size) {
      if (coverPaths.contains(_pathKey(file.path))) {
        coverBytes += size;
      } else {
        orphanBytes += size;
        orphanFiles++;
      }
    });
    await _walkFiles(paths.cacheDir, true, (file, size) {
      cacheBytes += size;
    });

    return LibraryStorageReport(
      bookBytes: bookBytes,
      coverBytes: coverBytes,
      cacheBytes: cacheBytes,
      orphanBytes: orphanBytes,
      orphanFiles: orphanFiles,
    );
  }

  /// Deletes unreferenced files and the app cache. Returns bytes reclaimed.
  /// 删除未被引用的文件与应用缓存，返回回收的字节数。
  Future<int> cleanupStorage() async {
    final bookPaths = {for (final book in _books) _pathKey(book.filePath)};
    final coverPaths = {
      for (final book in _books)
        if (book.coverPath != null) _pathKey(book.coverPath!),
    };

    var freed = 0;
    await _walkFiles(paths.booksDir, false, (file, size) async {
      if (!bookPaths.contains(_pathKey(file.path))) {
        if (await _deleteFile(file)) freed += size;
      }
    });
    await _walkFiles(paths.coversDir, false, (file, size) async {
      if (!coverPaths.contains(_pathKey(file.path))) {
        if (await _deleteFile(file)) freed += size;
      }
    });
    await _walkFiles(paths.cacheDir, true, (file, size) async {
      if (await _deleteFile(file)) freed += size;
    });
    return freed;
  }

  static const String backupFormat = 'manhua-reader-backup';
  static const int backupVersion = 1;

  /// Exports shelf metadata, bookmarks, organization and statistics as JSON.
  /// File paths are relative; the JSON alone does not include comic bytes.
  /// 以 JSON 导出书架元数据、书签、组织信息与统计。
  /// 文件路径为相对路径；仅 JSON 不包含漫画文件字节。
  Uint8List exportBackupJson() {
    final manifest = _buildBackupManifest(includeFiles: false);
    return Uint8List.fromList(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(manifest)),
    );
  }

  /// Builds a ZIP backup containing `manifest.json`, books and covers.
  /// 构建包含 `manifest.json`、漫画文件与封面的 ZIP 备份。
  Future<File> createBackupArchive({ImportProgressCallback? onProgress}) async {
    await paths.cacheDir.create(recursive: true);
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final archiveFile = File(
      p.join(paths.cacheDir.path, 'manhua_backup_$stamp.mrbackup'),
    );
    final encoder = ZipFileEncoder();
    encoder.create(archiveFile.path, level: ZipFileEncoder.store);
    try {
      final manifestBytes = utf8.encode(
        const JsonEncoder.withIndent('  ')
            .convert(_buildBackupManifest(includeFiles: true)),
      );
      encoder.addArchiveFile(
        ArchiveFile('manifest.json', manifestBytes.length, manifestBytes),
      );

      final total = max(1, _books.length);
      var done = 0;
      for (final book in _books) {
        final source = File(book.filePath);
        if (!book.format.isAlbum && await source.exists()) {
          await encoder.addFile(
            source,
            _relativeBookPath(book),
            ZipFileEncoder.store,
          );
        }
        final coverPath = book.coverPath;
        if (coverPath != null) {
          final cover = File(coverPath);
          if (await cover.exists()) {
            await encoder.addFile(
              cover,
              _relativeCoverPath(book)!,
              ZipFileEncoder.store,
            );
          }
        }
        done++;
        onProgress?.call('正在打包 ${book.title}', done / total);
      }
      await encoder.close();
      return archiveFile;
    } catch (error) {
      try {
        await encoder.close();
      } catch (_) {}
      await _deleteQuietly(archiveFile);
      rethrow;
    }
  }

  /// Restores a JSON manifest or a ZIP backup. Existing books are kept and
  /// duplicates are skipped; statistics are merged by per-day maxima.
  /// 恢复 JSON 清单或 ZIP 备份。保留已有书籍并跳过重复项；统计按每日最大值合并。
  Future<BackupImportResult> restoreBackupBytes(
    Uint8List bytes, {
    ImportProgressCallback? onProgress,
  }) async {
    Archive? archive;
    Map<String, Object?> manifest;
    try {
      if (_looksLikeZip(bytes)) {
        archive = ZipDecoder().decodeBytes(bytes);
        final entry = archive.findFile('manifest.json');
        if (entry == null) {
          throw ImportException('备份压缩包缺少 manifest.json');
        }
        manifest = _decodeBackupManifest(entry.readBytes() ?? Uint8List(0));
      } else {
        manifest = _decodeBackupManifest(bytes);
      }
    } on ImportException {
      rethrow;
    } catch (error) {
      throw ImportException('无法读取备份：$error');
    }

    if (manifest['format'] != backupFormat) {
      throw ImportException('这不是漫阅书架备份文件');
    }
    final rawBooks = manifest['books'];
    if (rawBooks is! List) {
      throw ImportException('备份文件缺少书架数据');
    }

    final result = BackupImportResult();
    final wasEmpty = _books.isEmpty;
    final backupStats = ReadingStats.fromJson(
      manifest['stats'] is Map
          ? (manifest['stats'] as Map).map(
              (key, value) => MapEntry('$key', value),
            )
          : null,
    );
    final folderIdMap = <String, String>{};
    final rawFolders = manifest['folders'];
    if (rawFolders is List) {
      for (final item in rawFolders) {
        if (item is! Map) continue;
        final backupId = '${item['id'] ?? ''}';
        final cleanName = _cleanFolderName('${item['name'] ?? ''}');
        if (backupId.isEmpty || cleanName == null) continue;
        LibraryFolder? local;
        for (final folder in _folders) {
          if (folder.name.toLowerCase() == cleanName.toLowerCase()) {
            local = folder;
            break;
          }
        }
        local ??= LibraryFolder(id: _newId(), name: cleanName);
        if (!_folders.contains(local)) _folders.add(local);
        folderIdMap[backupId] = local.id;
      }
    }

    final total = max(1, rawBooks.length);
    for (var index = 0; index < rawBooks.length; index++) {
      final raw = rawBooks[index];
      if (raw is! Map) {
        result.failed++;
        result.errors.add('第 ${index + 1} 本：数据格式不正确');
        continue;
      }
      final map = raw.map((key, value) => MapEntry('$key', value));
      final title = '${map['title'] ?? '未命名'}';
      try {
        final formatName = '${map['format'] ?? ''}';
        final format = ComicFormat.fromName(formatName);
        final declaredSize = (map['fileSize'] as num?)?.toInt() ?? 0;
        final originalName = '${map['originalName'] ?? ''}';
        final extension = _storageExtension(originalName, format);
        var id = '${map['id'] ?? ''}';
        final relativePath = _safeArchivePath(map['filePath']);
        final relativeCover = _safeArchivePath(map['coverPath']);

        if (id.isEmpty) id = _newId();
        final duplicate = _books.any(
          (book) =>
              book.id == id ||
              (originalName.isNotEmpty &&
                  book.originalName == originalName &&
                  book.fileSize == declaredSize),
        );
        if (duplicate) {
          result.skipped++;
          continue;
        }

        if (format.isAlbum) {
          final source = '${map['filePath'] ?? ''}'.trim();
          if (source.isEmpty) throw ImportException('相册缺少源路径');
          String? coverPath;
          final coverEntry = relativeCover.isEmpty
              ? null
              : archive?.findFile(relativeCover);
          if (coverEntry != null) {
            coverPath = p.join(
              paths.coversDir.path,
              '${id}_b${DateTime.now().millisecondsSinceEpoch}.png',
            );
            await _writeArchiveEntry(coverEntry, File(coverPath));
          } else if (relativeCover.isNotEmpty) {
            final existingCover = File(
              p.join(paths.coversDir.path, p.basename(relativeCover)),
            );
            if (await existingCover.exists()) coverPath = existingCover.path;
          }
          map['id'] = id;
          map['filePath'] = source;
          map['coverPath'] = coverPath;
          map['folderId'] = folderIdMap['${map['folderId'] ?? ''}'];
          final book = ComicBook.fromJson(map);
          _books.add(book);
          _index.upsert(book);
          result.imported++;
          if (!fileExists(book)) result.booksWithoutFiles++;
          continue;
        }

        var destination = File(
          p.join(
            paths.booksDir.path,
            relativePath.isNotEmpty
                ? p.basename(relativePath)
                : '$id.$extension',
          ),
        );
        if (await destination.exists()) {
          id = _newId();
          destination = File(p.join(paths.booksDir.path, '$id.$extension'));
        }

        final archiveEntry = relativePath.isEmpty
            ? null
            : archive?.findFile(relativePath);
        var hasFile = await destination.exists();
        if (archiveEntry != null) {
          await _writeArchiveEntry(archiveEntry, destination);
          hasFile = true;
        }

        String? coverPath;
        final coverEntry = relativeCover.isEmpty
            ? null
            : archive?.findFile(relativeCover);
        if (coverEntry != null) {
          coverPath = p.join(
            paths.coversDir.path,
            '${id}_b${DateTime.now().millisecondsSinceEpoch}.png',
          );
          await _writeArchiveEntry(coverEntry, File(coverPath));
        } else if (relativeCover.isNotEmpty) {
          final existingCover = File(
            p.join(paths.coversDir.path, p.basename(relativeCover)),
          );
          if (await existingCover.exists()) coverPath = existingCover.path;
        }

        map['id'] = id;
        map['filePath'] = destination.path;
        map['coverPath'] = coverPath;
        map['folderId'] = folderIdMap['${map['folderId'] ?? ''}'];
        final book = ComicBook.fromJson(map);
        if (hasFile) {
          book.fileSize = await destination.length();
        }
        _books.add(book);
        _index.upsert(book);
        result.imported++;
        if (!hasFile) result.booksWithoutFiles++;
      } catch (error) {
        result.failed++;
        result.errors.add('$title：$error');
      }
      onProgress?.call('正在恢复 $title', (index + 1) / total);
    }

    if (wasEmpty) {
      settings = ReaderSettings.fromJson(
        manifest['settings'] is Map
            ? (manifest['settings'] as Map).map(
                (key, value) => MapEntry('$key', value),
              )
            : null,
      );
      librarySettings = LibrarySettings.fromJson(
        manifest['library'] is Map
            ? (manifest['library'] as Map).map(
                (key, value) => MapEntry('$key', value),
              )
            : null,
      );
    }
    stats.merge(backupStats);
    _sortBooks();
    await _saveNow();
    notifyListeners();
    onProgress?.call('恢复完成', 1);
    return result;
  }

  Map<String, Object?> _buildBackupManifest({required bool includeFiles}) {
    final books = <Map<String, Object?>>[];
    final fileList = <Map<String, Object?>>[];
    for (final book in _books) {
      final isAlbum = book.format.isAlbum;
      final json = book.toJson();
      json['filePath'] = isAlbum ? book.filePath : _relativeBookPath(book);
      json['coverPath'] = _relativeCoverPath(book);
      books.add(json);
      fileList.add({
        'id': book.id,
        'title': book.title,
        'path': isAlbum ? book.filePath : _relativeBookPath(book),
        'cover': _relativeCoverPath(book),
        'size': book.fileSize,
        'external': isAlbum,
        'available': isAlbum
            ? fileExists(book)
            : File(book.filePath).existsSync(),
      });
    }
    return {
      'format': backupFormat,
      'version': backupVersion,
      'app': 'manhua_reader',
      'exportedAt': DateTime.now().toIso8601String(),
      'includeFiles': includeFiles,
      'bookCount': _books.length,
      'settings': settings.toJson(),
      'library': librarySettings.toJson(),
      'stats': stats.toJson(),
      'folders': _folders.map((folder) => folder.toJson()).toList(),
      'books': books,
      'fileList': fileList,
    };
  }

  Map<String, Object?> _decodeBackupManifest(Uint8List bytes) {
    var start = 0;
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      start = 3;
    }
    final decoded = jsonDecode(utf8.decode(bytes.sublist(start)));
    if (decoded is! Map) throw ImportException('备份文件格式不正确');
    return decoded.map((key, value) => MapEntry('$key', value));
  }

  bool _looksLikeZip(Uint8List bytes) {
    return bytes.length >= 4 &&
        bytes[0] == 0x50 &&
        bytes[1] == 0x4B &&
        bytes[2] == 0x03 &&
        bytes[3] == 0x04;
  }

  String _relativeBookPath(ComicBook book) =>
      'books/${p.basename(book.filePath)}';

  String? _relativeCoverPath(ComicBook book) {
    final cover = book.coverPath;
    return cover == null ? null : 'covers/${p.basename(cover)}';
  }

  String _safeArchivePath(Object? value) {
    final text = '${value ?? ''}'.replaceAll('\\', '/').trim();
    if (text.isEmpty || text.startsWith('/') || text.contains('..')) return '';
    if (!text.startsWith('books/') && !text.startsWith('covers/')) return '';
    return text;
  }

  Future<void> _writeArchiveEntry(ArchiveFile entry, File destination) async {
    final data = entry.readBytes();
    if (data == null) throw ImportException('无法解压 ${entry.name}');
    await destination.parent.create(recursive: true);
    final part = File('${destination.path}.part');
    await part.writeAsBytes(data, flush: true);
    try {
      await part.rename(destination.path);
    } catch (_) {
      await destination.writeAsBytes(data, flush: true);
      await _deleteQuietly(part);
    }
  }

  /// Keeps the user's real extension when it belongs to the detected format.
  /// 当用户文件扩展名属于该格式时，保留真实扩展名。
  String _storageExtension(String name, ComicFormat format) {
    final extension = p.extension(name).replaceFirst('.', '').toLowerCase();
    return format.extensions.contains(extension) ? extension : format.extension;
  }

  void _checkDuplicate(String originalName, int fileSize) {
    if (_books.any(
      (book) => book.originalName == originalName && book.fileSize == fileSize,
    )) {
      throw ImportException(
        '《${p.basenameWithoutExtension(originalName)}》已经在书架里了',
      );
    }
  }

  void updateProgress(ComicBook book, int page) {
    final clamped = book.pageCount <= 0 ? 0 : page.clamp(0, book.pageCount - 1);
    final previous = book.safeLastPage;
    final now = DateTime.now();
    if (clamped > previous) {
      stats.addPages(clamped - previous, now);
    }
    book.lastPage = clamped;
    book.lastReadAt = now;
    _moveToFront(book);
    notifyListeners();
    _scheduleSave();
  }

  /// Marks every given book as finished. Returns how many changed.
  /// 将给定书籍全部标记为已读完，返回实际发生变化的数量。
  int markBooksRead(Iterable<ComicBook> books) {
    final now = DateTime.now();
    var changed = 0;
    for (final book in {...books}) {
      if (book.pageCount <= 0) continue;
      final target = book.pageCount - 1;
      if (book.lastPage == target && book.lastReadAt != null) continue;
      book.lastPage = target;
      book.lastReadAt = now;
      changed++;
    }
    if (changed == 0) return 0;
    _sortBooks();
    notifyListeners();
    _scheduleSave();
    return changed;
  }

  bool isBookmarked(ComicBook book, int page) => book.isBookmarked(page);

  void toggleBookmark(ComicBook book, int page) {
    if (page < 0 || page >= book.pageCount) return;
    final existingIndex = book.bookmarks.indexWhere(
      (bookmark) => bookmark.page == page,
    );
    if (existingIndex >= 0) {
      book.bookmarks.removeAt(existingIndex);
    } else {
      book.bookmarks.add(Bookmark(page: page, createdAt: DateTime.now()));
      book.bookmarks.sort((a, b) => a.page.compareTo(b.page));
    }
    notifyListeners();
    _scheduleSave();
  }

  /// Adds or updates a bookmark with a custom name and note.
  /// 添加或更新带自定义名称与备注的书签。
  void setBookmark(
    ComicBook book,
    int page, {
    required String? label,
    required String? note,
  }) {
    if (page < 0 || page >= book.pageCount) return;
    final cleanLabel = _cleanBookmarkText(label, 80);
    final cleanNote = _cleanBookmarkText(note, 500);
    final existingIndex = book.bookmarks.indexWhere(
      (bookmark) => bookmark.page == page,
    );
    if (existingIndex >= 0) {
      final existing = book.bookmarks[existingIndex];
      book.bookmarks[existingIndex] = Bookmark(
        page: existing.page,
        createdAt: existing.createdAt,
        label: cleanLabel,
        note: cleanNote,
      );
    } else {
      book.bookmarks.add(
        Bookmark(
          page: page,
          createdAt: DateTime.now(),
          label: cleanLabel,
          note: cleanNote,
        ),
      );
      book.bookmarks.sort((a, b) => a.page.compareTo(b.page));
    }
    notifyListeners();
    _scheduleSave();
  }

  void removeBookmark(ComicBook book, int page) {
    if (book.bookmarks.isEmpty) return;
    final before = book.bookmarks.length;
    book.bookmarks.removeWhere((bookmark) => bookmark.page == page);
    if (book.bookmarks.length != before) {
      notifyListeners();
      _scheduleSave();
    }
  }

  Future<void> _releaseAlbumTreeIfUnused(String uri) async {
    if (_books.any((book) => book.format.isAlbum && book.filePath == uri)) {
      return;
    }
    await SafAlbumService.releaseTree(uri);
  }

  /// Refreshes an album's cached page count and source size after a rescan.
  /// 重新扫描后更新相册缓存的页数与源大小。
  void syncAlbumMetadata(ComicBook book, int pageCount, int fileSize) {
    if (!book.format.isAlbum) return;
    if (book.pageCount == pageCount && book.fileSize == fileSize) return;
    book.pageCount = pageCount;
    book.fileSize = fileSize;
    book.lastPage = _clampPage(book.lastPage, pageCount);
    book.bookmarks.removeWhere(
      (bookmark) => bookmark.page < 0 || bookmark.page >= pageCount,
    );
    _index.upsert(book);
    notifyListeners();
    _scheduleSave();
  }

  /// Changes album page order and remaps progress/bookmarks by image path.
  /// 更改相册页序，并按图片路径重映射阅读进度与书签。
  int setAlbumSort(
    ComicBook book,
    AlbumSortField field,
    bool descending, {
    List<String> oldKeys = const [],
    List<String> newKeys = const [],
  }) {
    if (!book.format.isAlbum) return 0;
    var dropped = 0;
    if (oldKeys.isNotEmpty && newKeys.isNotEmpty) {
      final indexByKey = {
        for (var index = 0; index < newKeys.length; index++)
          newKeys[index]: index,
      };
      int? remap(int page) {
        if (page < 0 || page >= oldKeys.length) return null;
        return indexByKey[oldKeys[page]];
      }

      final nextLastPage = remap(book.lastPage);
      book.lastPage = nextLastPage ?? 0;
      final mapped = <Bookmark>[];
      final seen = <int>{};
      for (final bookmark in book.bookmarks) {
        final page = remap(bookmark.page);
        if (page == null || !seen.add(page)) {
          dropped++;
          continue;
        }
        mapped.add(
          Bookmark(
            page: page,
            createdAt: bookmark.createdAt,
            label: bookmark.label,
            note: bookmark.note,
          ),
        );
      }
      mapped.sort((a, b) => a.page.compareTo(b.page));
      book.bookmarks
        ..clear()
        ..addAll(mapped);
      book.pageCount = newKeys.length;
    } else {
      book.lastPage = _clampPage(book.lastPage, book.pageCount);
      book.bookmarks.removeWhere(
        (bookmark) => bookmark.page < 0 || bookmark.page >= book.pageCount,
      );
    }
    book.albumSort = field;
    book.albumSortDescending = descending;
    _index.upsert(book);
    notifyListeners();
    _scheduleSave();
    return dropped;
  }

  Future<void> deleteBook(ComicBook book) => deleteBooks([book]);

  Future<void> deleteBooks(Iterable<ComicBook> books) async {
    final targets = <ComicBook>{...books}.toList(growable: false);
    if (targets.isEmpty) return;
    for (final book in targets) {
      _books.remove(book);
      _index.remove(book);
      PdfPasswordCache.remove(book.filePath);
    }
    notifyListeners();
    await _saveNow();
    for (final book in targets) {
      if (book.format.isAlbum) {
        // Referenced albums never delete the user's source folder.
        // 引用型相册绝不删除用户的原文件夹。
        if (book.filePath.startsWith('content://')) {
          await _releaseAlbumTreeIfUnused(book.filePath);
        }
        if (book.coverPath != null) {
          await _deleteQuietly(File(book.coverPath!));
        }
        continue;
      }
      await _deleteQuietly(File(book.filePath));
      if (book.coverPath != null) {
        await _deleteQuietly(File(book.coverPath!));
      }
    }
  }

  void setReadingMode(ReadingMode mode) {
    if (settings.mode == mode) return;
    settings.mode = mode;
    _scheduleSave();
  }

  void setRightToLeft(bool value) {
    if (settings.rightToLeft == value) return;
    settings.rightToLeft = value;
    _scheduleSave();
  }

  void setDoublePage(bool value) {
    if (settings.doublePage == value) return;
    settings.doublePage = value;
    _scheduleSave();
  }

  void setKeepAwake(bool value) {
    if (settings.keepAwake == value) return;
    settings.keepAwake = value;
    _scheduleSave();
  }

  void setReaderBrightness(double value) {
    final next = value.clamp(0.4, 1.0).toDouble();
    if (settings.brightness == next) return;
    settings.brightness = next;
    _scheduleSave();
  }

  void setReaderWarmth(double value) {
    final next = value.clamp(0.0, 0.4).toDouble();
    if (settings.warmth == next) return;
    settings.warmth = next;
    _scheduleSave();
  }

  void setAutoTurnSeconds(int value) {
    final next = const {0, 5, 10, 15, 30}.contains(value) ? value : 0;
    if (settings.autoTurnSeconds == next) return;
    settings.autoTurnSeconds = next;
    _scheduleSave();
  }

  void setVolumeKeys(bool value) {
    if (settings.volumeKeys == value) return;
    settings.volumeKeys = value;
    _scheduleSave();
  }

  void setPageTurnAnimation(PageTurnAnimation value) {
    if (settings.pageTurnAnimation == value) return;
    settings.pageTurnAnimation = value;
    _scheduleSave();
  }

  void setLibraryView(LibraryViewMode view) {
    if (librarySettings.view == view) return;
    librarySettings.view = view;
    notifyListeners();
    _scheduleSave();
  }

  void setLibrarySort(LibrarySort sort) {
    if (librarySettings.sort == sort) return;
    librarySettings.sort = sort;
    notifyListeners();
    _scheduleSave();
  }

  void renameBook(ComicBook book, String title) {
    final next = title.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (next.isEmpty || next.length > 100 || next == book.title) return;
    book.title = next;
    _index.upsert(book);
    notifyListeners();
    _scheduleSave();
  }

  void toggleFavorite(ComicBook book) {
    book.favorite = !book.favorite;
    notifyListeners();
    _scheduleSave();
  }

  void togglePinned(ComicBook book) {
    book.pinned = !book.pinned;
    _sortBooks();
    notifyListeners();
    _scheduleSave();
  }

  /// Updates the user-managed series and tags for one book.
  /// 更新单本书的用户自定义系列与标签。
  void setBookOrganization(
    ComicBook book, {
    required String? series,
    required List<String> tags,
  }) {
    final cleanSeries = _cleanSeries(series);
    final cleanTags = _cleanTags(tags);
    final sameSeries = cleanSeries == book.series;
    final sameTags = listEquals(cleanTags, book.tags);
    if (sameSeries && sameTags) return;
    book.series = cleanSeries;
    book.tags = cleanTags;
    _index.upsert(book);
    notifyListeners();
    _scheduleSave();
  }

  /// Returns an existing folder with [name] (case-insensitive) or creates one.
  /// 返回已有的同名文件夹（大小写不敏感），不存在时创建。
  LibraryFolder ensureFolder(String name) {
    final clean = _cleanFolderName(name) ?? '文件夹';
    final key = clean.toLowerCase();
    for (final folder in _folders) {
      if (folder.name.toLowerCase() == key) return folder;
    }
    final folder = LibraryFolder(id: _newId(), name: clean);
    _folders.add(folder);
    notifyListeners();
    _scheduleSave();
    return folder;
  }

  /// Renames a shelf folder. Returns false for an empty/duplicate name.
  /// 重命名书架文件夹；名称为空或重复时返回 false。
  bool renameFolder(LibraryFolder folder, String name) {
    final clean = _cleanFolderName(name);
    if (clean == null || clean == folder.name) return false;
    final key = clean.toLowerCase();
    if (_folders.any(
      (item) => item.id != folder.id && item.name.toLowerCase() == key,
    )) {
      return false;
    }
    folder.name = clean;
    notifyListeners();
    _scheduleSave();
    return true;
  }

  /// Removes a folder but keeps its books on the shelf root by default.
  /// 删除文件夹，默认把其中的书籍保留在书架根目录。
  Future<void> deleteFolder(
    LibraryFolder folder, {
    bool keepBooks = true,
  }) async {
    if (!_folders.remove(folder)) return;
    final affected = _books
        .where((book) => book.folderId == folder.id)
        .toList();
    if (keepBooks) {
      for (final book in affected) {
        book.folderId = null;
      }
    }
    notifyListeners();
    await _saveNow();
    if (!keepBooks && affected.isNotEmpty) {
      await deleteBooks(affected);
    }
  }

  Future<void> flush() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    await _saveNow();
  }

  @override
  void dispose() {
    final hasPendingSave = _saveTimer != null;
    _saveTimer?.cancel();
    if (hasPendingSave) unawaited(_saveNow());
    super.dispose();
  }

  void _moveToFront(ComicBook book) {
    final index = _books.indexOf(book);
    if (index > 0) {
      _books.removeAt(index);
      _books.insert(0, book);
    }
  }

  void _sortBooks() {
    _books.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return b.lastActivity.compareTo(a.lastActivity);
    });
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 450), () {
      _saveTimer = null;
      unawaited(_saveNow());
    });
  }

  Future<void> _saveNow() async {
    _dirty = true;
    if (_saving) return;
    _saving = true;
    try {
      while (_dirty) {
        _dirty = false;
        _sortBooks();
        final payload = jsonEncode({
          'version': 4,
          'settings': settings.toJson(),
          'library': librarySettings.toJson(),
          'stats': stats.toJson(),
          'folders': _folders.map((folder) => folder.toJson()).toList(),
          'books': _books.map((book) => book.toJson()).toList(),
        });
        final temp = File('${paths.libraryFile.path}.tmp');
        await temp.writeAsString(payload, flush: true);
        try {
          await temp.rename(paths.libraryFile.path);
        } on FileSystemException {
          await paths.libraryFile.writeAsString(payload, flush: true);
          await _deleteQuietly(temp);
        }
      }
    } catch (error, stack) {
      debugPrint('Library save failed: $error\n$stack');
    } finally {
      _saving = false;
    }
  }

  Future<void> _copyWithProgress(
    File source,
    File destination,
    void Function(double value) onProgress,
  ) async {
    final total = await source.length();
    final sink = destination.openWrite();
    var copied = 0;
    var lastReport = 0;
    final stopwatch = Stopwatch()..start();
    try {
      await for (final chunk in source.openRead()) {
        sink.add(chunk);
        copied += chunk.length;
        if (total > 0 &&
            (stopwatch.elapsedMilliseconds - lastReport > 120 ||
                copied == total)) {
          lastReport = stopwatch.elapsedMilliseconds;
          onProgress((copied / total).clamp(0.0, 1.0));
        }
      }
    } finally {
      await sink.close();
    }
  }

  Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (error) {
      debugPrint('Delete failed for ${file.path}: $error');
    }
  }

  Future<bool> _deleteFile(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
        return true;
      }
    } catch (error) {
      debugPrint('Delete failed for ${file.path}: $error');
    }
    return false;
  }

  Future<void> _walkFiles(
    Directory directory,
    bool recursive,
    FutureOr<void> Function(File file, int size) onFile,
  ) async {
    if (!await directory.exists()) return;
    await for (final entity in directory.list(
      recursive: recursive,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      var size = 0;
      try {
        size = await entity.length();
      } catch (_) {}
      await onFile(entity, size);
    }
  }

  String _pathKey(String path) {
    final normalized = p.normalize(p.absolute(path));
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }

  String _newId() {
    final time = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final random = Random().nextInt(1 << 30).toRadixString(36);
    return '$time${random.padLeft(6, '0')}';
  }

  String _cleanTitle(String value) {
    final title = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    return title.isEmpty ? '未命名漫画' : title;
  }

  String? _cleanSeries(String? value) {
    final text = value?.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text == null || text.isEmpty) return null;
    return text.length <= 60 ? text : text.substring(0, 60);
  }

  List<String> _cleanTags(Iterable<String> values) {
    final tags = <String>[];
    for (final value in values) {
      final tag = value.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (tag.isEmpty || tags.contains(tag)) continue;
      tags.add(tag.length <= 24 ? tag : tag.substring(0, 24));
      if (tags.length >= 20) break;
    }
    return tags;
  }

  String? _cleanFolderName(String? value) {
    final text = value?.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text == null || text.isEmpty) return null;
    return text.length <= 60 ? text : text.substring(0, 60);
  }

  String? _cleanBookmarkText(String? value, int maxLength) {
    final text = value?.trim();
    if (text == null || text.isEmpty) return null;
    return text.length <= maxLength ? text : text.substring(0, maxLength);
  }

  int _clampPage(int page, int pageCount) =>
      pageCount <= 0 ? 0 : page.clamp(0, pageCount - 1);

  String _friendlyError(Object error) {
    if (error is PdfPasswordException) {
      final message = error.message.toLowerCase();
      if (message.contains('no password')) return '已取消输入密码';
      return 'PDF 密码不正确或已取消输入';
    }
    if (error is FormatException) return '文件格式不正确';
    if (error is FileSystemException) {
      return error.message.isEmpty ? '文件读取失败' : error.message;
    }
    final text = error.toString();
    if (text.toLowerCase().contains('password')) {
      return 'PDF 密码不正确或已取消输入';
    }
    return text.replaceFirst('Exception: ', '');
  }
}

class _InspectedComic {
  const _InspectedComic({
    required this.title,
    required this.pageCount,
    this.coverPath,
  });

  final String title;
  final int pageCount;
  final String? coverPath;
}

class BackupImportResult {
  int imported = 0;
  int skipped = 0;
  int failed = 0;
  int booksWithoutFiles = 0;
  final List<String> errors = <String>[];
}
