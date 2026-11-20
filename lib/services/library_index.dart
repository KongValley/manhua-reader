import '../models/comic_book.dart';

/// Incremental in-memory index for fast bookshelf search, tag and series
/// lookups. It is rebuilt from `library.json` on startup and updated on every
/// mutation, avoiding repeated lower-casing of the whole shelf while typing.
class LibraryIndex {
  final Map<String, String> _searchText = {};
  final Map<String, String?> _seriesOf = {};
  final Map<String, Set<String>> _tagsOf = {};
  final Map<String, Set<String>> _seriesBooks = {};
  final Map<String, Set<String>> _tagBooks = {};

  void rebuild(Iterable<ComicBook> books) {
    _searchText.clear();
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
    _searchText[book.id] = _buildSearchText(book);
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

  bool matches(ComicBook book, String normalizedQuery) {
    if (normalizedQuery.isEmpty) return true;
    return searchTextFor(book.id).contains(normalizedQuery);
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

  String _buildSearchText(ComicBook book) {
    final buffer = StringBuffer()
      ..write(book.title.toLowerCase())
      ..write('\n')
      ..write(book.originalName.toLowerCase());
    final series = book.series?.trim();
    if (series != null && series.isNotEmpty) {
      buffer
        ..write('\n')
        ..write(series.toLowerCase());
    }
    for (final tag in book.tags) {
      buffer
        ..write('\n')
        ..write(tag.toLowerCase());
    }
    return buffer.toString();
  }
}
