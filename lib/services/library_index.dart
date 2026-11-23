import 'package:lpinyin/lpinyin.dart';

import '../models/comic_book.dart';

/// Incremental in-memory index for fast bookshelf search, tag and series
/// lookups. It is rebuilt from `library.json` on startup and updated on every
/// mutation, avoiding repeated lower-casing of the whole shelf while typing.
/// 用于快速书架搜索、标签与系列查询的增量内存索引。
/// 启动时从 `library.json` 重建，每次变更时增量更新，避免输入时反复
/// 对整个书架做小写转换。
class LibraryIndex {
  static final _initialsQuery = RegExp(r'^[a-z0-9\s.\-_]+$');
  static final _nonAlphanumeric = RegExp(r'[^a-z0-9]');

  final Map<String, String> _searchText = {};
  final Map<String, String> _searchInitials = {};
  final Map<String, String?> _seriesOf = {};
  final Map<String, Set<String>> _tagsOf = {};
  final Map<String, Set<String>> _seriesBooks = {};
  final Map<String, Set<String>> _tagBooks = {};

  void rebuild(Iterable<ComicBook> books) {
    _searchText.clear();
    _searchInitials.clear();
    _seriesOf.clear();
    _tagsOf.clear();
    _seriesBooks.clear();
    _tagBooks.clear();
    for (final book in books) {
      upsert(book);
    }
  }

  void upsert(ComicBook book) {
    remove(book);
    final fields = [book.title, book.originalName, ?book.series, ...book.tags];
    _searchText[book.id] = fields.map((field) => field.toLowerCase()).join('\n');
    _searchInitials[book.id] = fields.map(_initials).join('\n');
    final series = book.series?.trim();
    if (series != null && series.isNotEmpty) {
      _seriesOf[book.id] = series;
      _seriesBooks.putIfAbsent(series, () => <String>{}).add(book.id);
    } else {
      _seriesOf[book.id] = null;
    }
    final tags = {
      for (final tag in book.tags)
        if (tag.trim().isNotEmpty) tag.trim(),
    };
    _tagsOf[book.id] = tags;
    for (final tag in tags) {
      _tagBooks.putIfAbsent(tag, () => <String>{}).add(book.id);
    }
  }

  void remove(ComicBook book) {
    _searchText.remove(book.id);
    _searchInitials.remove(book.id);
    final oldSeries = _seriesOf.remove(book.id);
    if (oldSeries != null) {
      final ids = _seriesBooks[oldSeries];
      ids?.remove(book.id);
      if (ids != null && ids.isEmpty) _seriesBooks.remove(oldSeries);
    }
    final oldTags = _tagsOf.remove(book.id);
    if (oldTags != null) {
      for (final tag in oldTags) {
        final ids = _tagBooks[tag];
        ids?.remove(book.id);
        if (ids != null && ids.isEmpty) _tagBooks.remove(tag);
      }
    }
  }

  String searchTextFor(String id) => _searchText[id] ?? '';

  bool matches(ComicBook book, String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty || searchTextFor(book.id).contains(normalized)) {
      return true;
    }
    final initials = _queryInitials(normalized);
    return initials != null &&
        (_searchInitials[book.id]?.contains(initials) ?? false);
  }

  static bool matchesName(String name, String query) {
    final normalized = query.trim().toLowerCase();
    if (name.toLowerCase().contains(normalized)) return true;
    final initials = _queryInitials(normalized);
    return initials != null && _initials(name).contains(initials);
  }

  List<String> get seriesNames =>
      _seriesBooks.keys.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

  List<String> get tagNames =>
      _tagBooks.keys.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

  Map<String, int> get seriesCounts => {
    for (final entry in _seriesBooks.entries) entry.key: entry.value.length,
  };

  Map<String, int> get tagCounts => {
    for (final entry in _tagBooks.entries) entry.key: entry.value.length,
  };

  static String? _queryInitials(String query) {
    if (!_initialsQuery.hasMatch(query)) return null;
    final initials = query.replaceAll(_nonAlphanumeric, '');
    return initials.isEmpty ? null : initials;
  }

  static String _initials(String text) {
    final value = text.toLowerCase();
    if (!ChineseHelper.containsChinese(value)) return '';
    try {
      return PinyinHelper.getShortPinyin(value).replaceAll(_nonAlphanumeric, '');
    } on PinyinException {
      // Keep searchable characters around dictionary gaps.
      // 字典缺字时仍保留可搜索的相邻字符。
      final result = StringBuffer();
      for (final rune in value.runes) {
        final character = String.fromCharCode(rune);
        final simplified = ChineseHelper.convertCharToSimplifiedChinese(character);
        final pinyin = PinyinHelper.convertToPinyinArray(simplified, PinyinFormat.WITHOUT_TONE);
        result.write(pinyin.isEmpty ? character : pinyin.first[0]);
      }
      return result.toString().replaceAll(_nonAlphanumeric, '');
    }
  }
}
