import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import '../formats/mobi/mobi_book.dart';
import '../models/bookmark.dart';
import '../models/comic_book.dart';
import '../models/library_settings.dart';
import '../models/library_storage_report.dart';
import '../models/reader_settings.dart';
import '../models/reading_stats.dart';
import '../utils/series.dart';
import 'app_paths.dart';
import 'cover_generator.dart';
import 'library_index.dart';
import 'pdf_password_cache.dart';

class ImportException implements Exception {
  ImportException(this.message);

  final String message;

  @override
  String toString() => message;
}

typedef ImportProgressCallback = void Function(String label, double progress);

/// Owns the bookshelf, import pipeline, covers and reading progress.
class LibraryRepository extends ChangeNotifier {
  LibraryRepository(this.paths);

  final AppPaths paths;

  final List<ComicBook> _books = [];
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

  bool matchesSearch(ComicBook book, String query) =>
      _index.matches(book, query);

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

  bool fileExists(ComicBook book) => File(book.filePath).existsSync();

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
      for (final book in _books) {
        book.series ??= deriveSeriesName(book.title, book.originalName);
      }
    }

    for (final book in _books) {
      // iOS can move the app container between launches. Fall back to the
      // current app directories when an absolute path is stale.
      if (!File(book.filePath).existsSync()) {
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
    _index.rebuild(_books);
    _sortBooks();
    _saved = true;
    notifyListeners();
  }

  Future<ComicBook> importFile(
    String sourcePath, {
    String? originalName,
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
      throw ImportException('仅支持 PDF 与 MOBI 格式');
    }

    final fileSize = await source.length();
    _checkDuplicate(name, fileSize);

    final id = _newId();
    final destination = File(
      p.join(paths.booksDir.path, '$id.${format.extension}'),
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
  Future<ComicBook> importStream({
    required String originalName,
    required Stream<List<int>> stream,
    int? totalSize,
    ImportProgressCallback? onProgress,
    PdfPasswordProvider? pdfPasswordProvider,
  }) async {
    final format = ComicFormat.fromExtension(p.extension(originalName));
    if (format == null) {
      throw ImportException('仅支持 PDF 与 MOBI 格式');
    }
    if (totalSize != null) {
      _checkDuplicate(originalName, totalSize);
    }

    final id = _newId();
    final destination = File(
      p.join(paths.booksDir.path, '$id.${format.extension}'),
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

  Future<ComicBook> _registerImportedFile({
    required File destination,
    required ComicFormat format,
    required String originalName,
    required String id,
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
    if (error is MobiException) throw ImportException(error.message);
    throw ImportException('无法导入该文件：${_friendlyError(error)}');
  }

  /// Replaces a missing (or broken) file for an existing bookshelf entry while
  /// keeping its id, title, progress and bookmarks.
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
        '${book.id}_r$stamp.${book.format.extension}',
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
      if (error is MobiException) throw ImportException(error.message);
      throw ImportException('无法重新定位文件：${_friendlyError(error)}');
    }
  }

  /// Rebuilds a cover in a new file so Flutter's image cache sees the change.
  Future<bool> regenerateCover(
    ComicBook book, {
    ImportProgressCallback? onProgress,
    PdfPasswordProvider? pdfPasswordProvider,
  }) async {
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
  Uint8List exportBackupJson() {
    final manifest = _buildBackupManifest(includeFiles: false);
    return Uint8List.fromList(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(manifest)),
    );
  }

  /// Builds a ZIP backup containing `manifest.json`, books and covers.
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
        if (await source.exists()) {
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
        final extension = format.extension;
        final declaredSize = (map['fileSize'] as num?)?.toInt() ?? 0;
        final originalName = '${map['originalName'] ?? ''}';
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
      final json = book.toJson();
      json['filePath'] = _relativeBookPath(book);
      json['coverPath'] = _relativeCoverPath(book);
      books.add(json);
      fileList.add({
        'id': book.id,
        'title': book.title,
        'path': _relativeBookPath(book),
        'cover': _relativeCoverPath(book),
        'size': book.fileSize,
        'available': File(book.filePath).existsSync(),
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
          'version': 3,
          'settings': settings.toJson(),
          'library': librarySettings.toJson(),
          'stats': stats.toJson(),
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
