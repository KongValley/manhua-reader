import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import '../formats/mobi/mobi_book.dart';
import '../models/bookmark.dart';
import '../models/comic_book.dart';
import '../models/reader_settings.dart';
import 'app_paths.dart';
import 'cover_generator.dart';
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

  Timer? _saveTimer;
  bool _saved = false;
  bool _saving = false;
  bool _dirty = false;

  bool get isLoaded => _saved;
  bool get isEmpty => _books.isEmpty;
  int get bookCount => _books.length;

  List<ComicBook> get books => List<ComicBook>.unmodifiable(_books);

  ComicBook? get lastRead {
    for (final book in _books) {
      if (book.lastReadAt != null) return book;
    }
    return null;
  }

  bool fileExists(ComicBook book) => File(book.filePath).existsSync();

  Future<void> load() async {
    try {
      final file = paths.libraryFile;
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map<String, dynamic>) {
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
        }
      }
    } catch (error, stack) {
      debugPrint('Library load failed: $error\n$stack');
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
    try {
      await _copyWithProgress(
        source,
        destination,
        (value) => onProgress?.call('正在复制 $name', value * 0.78),
      );
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
    try {
      final sink = destination.openWrite();
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
      onProgress?.call('正在解析漫画信息', 0.82);

      final String title;
      final int pageCount;
      if (format == ComicFormat.mobi) {
        final mobi = await MobiBook.open(
          destination.path,
          fallbackTitle: p.basenameWithoutExtension(originalName),
        );
        title = mobi.title;
        pageCount = mobi.pageCount;
        onProgress?.call('正在生成封面', 0.9);
        final cover = File(p.join(paths.coversDir.path, '$id.png'));
        final firstPage = await mobi.readPage(0);
        coverPath = await CoverGenerator.fromImageBytes(firstPage, cover.path);
      } else {
        title = _cleanTitle(p.basenameWithoutExtension(originalName));
        final document = await PdfDocument.openFile(
          destination.path,
          passwordProvider: pdfPasswordProvider,
        );
        try {
          pageCount = document.pages.length;
          if (pageCount == 0) {
            throw ImportException('PDF 没有可显示的页面');
          }
          onProgress?.call('正在生成封面', 0.9);
          final cover = File(p.join(paths.coversDir.path, '$id.png'));
          coverPath = await CoverGenerator.fromPdf(document, cover.path);
        } finally {
          await document.dispose();
        }
      }

      final book = ComicBook(
        id: id,
        title: _cleanTitle(title),
        originalName: originalName,
        filePath: destination.path,
        format: format,
        pageCount: pageCount,
        fileSize: fileSize,
        addedAt: DateTime.now(),
        coverPath: coverPath,
      );

      _books.insert(0, book);
      await _saveNow();
      notifyListeners();
      onProgress?.call('导入完成', 1);
      return book;
    } catch (error) {
      if (coverPath != null) await _deleteQuietly(File(coverPath));
      rethrow;
    }
  }

  Future<ComicBook> _handleImportFailure(
    Object error,
    StackTrace stack, {
    required File destination,
    required String id,
  }) async {
    debugPrint('Import failed: $error\n$stack');
    await _deleteQuietly(destination);
    await _deleteQuietly(File(p.join(paths.coversDir.path, '$id.png')));
    if (error is ImportException) throw error;
    if (error is MobiException) throw ImportException(error.message);
    throw ImportException('无法导入该文件：${_friendlyError(error)}');
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
    book.lastPage = clamped;
    book.lastReadAt = DateTime.now();
    _moveToFront(book);
    notifyListeners();
    _scheduleSave();
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

  Future<void> deleteBook(ComicBook book) async {
    _books.remove(book);
    notifyListeners();
    await _saveNow();
    PdfPasswordCache.remove(book.filePath);
    await _deleteQuietly(File(book.filePath));
    if (book.coverPath != null) {
      await _deleteQuietly(File(book.coverPath!));
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
    _books.sort((a, b) => b.lastActivity.compareTo(a.lastActivity));
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
          'version': 1,
          'settings': settings.toJson(),
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

  String _newId() {
    final time = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final random = Random().nextInt(1 << 30).toRadixString(36);
    return '$time${random.padLeft(6, '0')}';
  }

  String _cleanTitle(String value) {
    final title = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    return title.isEmpty ? '未命名漫画' : title;
  }

  String? _cleanBookmarkText(String? value, int maxLength) {
    final text = value?.trim();
    if (text == null || text.isEmpty) return null;
    return text.length <= maxLength ? text : text.substring(0, maxLength);
  }

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
