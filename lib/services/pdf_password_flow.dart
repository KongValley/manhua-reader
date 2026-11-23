import '../models/comic_book.dart';
import 'pdf_password_cache.dart';
import 'pdf_password_store.dart';

class PdfPasswordEntry {
  const PdfPasswordEntry(this.password, {this.remember = false});

  final String password;
  final bool remember;
}

enum _Origin { session, stored, dialog }

/// Tracks password attempts for a single PDF open.
/// 记录单次打开 PDF 时的密码尝试。
class PdfPasswordFlow {
  PdfPasswordFlow({ComicBook? book, required this.prompt})
    : _book = book,
      _filePath = book?.filePath,
      _generation = book == null ? null : PdfPasswordStore.generation(book);

  final Future<PdfPasswordEntry?> Function(String? errorText) prompt;
  final ComicBook? _book;
  final String? _filePath;
  final Object? _generation;
  bool _triedStored = false;
  ({PdfPasswordEntry entry, _Origin origin})? _last;

  bool _isCurrent(ComicBook book, String filePath) =>
      book.filePath == filePath &&
      identical(_generation, PdfPasswordStore.generation(book));

  /// PDFium requests another password only after rejecting the previous one.
  /// PDFium 只有在拒绝上一次密码后才会请求新的密码。
  Future<String?> provide() async {
    final previous = _last;
    _last = null;
    final book = _book;
    final path = _filePath;
    if (book != null && path != null && _isCurrent(book, path)) {
      final rejected = previous?.entry.password;
      if (previous == null) {
        final session = PdfPasswordCache.get(path);
        if (session != null) {
          _last = (entry: PdfPasswordEntry(session), origin: _Origin.session);
          return session;
        }
      } else if (previous.origin == _Origin.session) {
        if (PdfPasswordCache.get(path) == rejected) {
          PdfPasswordCache.remove(path);
        }
      } else if (previous.origin == _Origin.stored) {
        await PdfPasswordStore.reject(book, path, previous.entry.password);
      }

      if (!_triedStored) {
        _triedStored = true;
        final stored = await PdfPasswordStore.read(book, path);
        if (stored != null && _isCurrent(book, path)) {
          if (stored != rejected) {
            _last = (entry: PdfPasswordEntry(stored), origin: _Origin.stored);
            return stored;
          }
          await PdfPasswordStore.reject(book, path, stored);
        }
      }
    }

    final entry = await prompt(previous == null ? null : '密码不正确，请重试');
    if (entry == null) return null;
    _last = (entry: entry, origin: _Origin.dialog);
    return entry.password;
  }

  /// Applies the last credential after the open has succeeded.
  /// 仅在成功打开文件后应用最后一次输入的密码。
  Future<bool> onSuccess(ComicBook book) async {
    final entry = _last?.entry;
    _last = null;
    if (entry == null || book.format != ComicFormat.pdf) return true;
    if (_book != null &&
        (!identical(_book, book) || !_isCurrent(book, _filePath!))) {
      return true;
    }
    PdfPasswordCache.put(book.filePath, entry.password);
    if (!entry.remember) return true;
    return PdfPasswordStore.remember(book, entry.password);
  }
}
