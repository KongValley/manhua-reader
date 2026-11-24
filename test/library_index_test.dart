import 'package:flutter_test/flutter_test.dart';
import 'package:manhua_reader/models/comic_book.dart';
import 'package:manhua_reader/services/library_index.dart';

ComicBook _book(
  String id,
  String title, {
  String? series,
  List<String> tags = const [],
}) {
  return ComicBook(
    id: id,
    title: title,
    originalName: '$title.pdf',
    filePath: '$title.pdf',
    format: ComicFormat.pdf,
    pageCount: 10,
    fileSize: 3,
    addedAt: DateTime(2026, 11, 1),
    series: series,
    tags: tags,
  );
}

void main() {
  test('indexes titles, series and tags incrementally', () {
    final index = LibraryIndex();
    final first = _book('a', '海贼王 第1卷', series: '海贼王', tags: ['冒险']);
    final second = _book('b', '海贼王 第2卷', series: '海贼王', tags: ['冒险', '热血']);
    index.rebuild([first, second]);

    expect(index.seriesNames, ['海贼王']);
    expect(index.seriesCounts['海贼王'], 2);
    expect(index.tagNames, ['冒险', '热血']);
    expect(index.matches(first, '海贼王'), isTrue);
    expect(index.matches(first, '冒险'), isTrue);
    expect(index.matches(first, '不存在'), isFalse);

    first.series = '新系列';
    first.tags = ['日常'];
    index.upsert(first);
    expect(index.seriesCounts['海贼王'], 1);
    expect(index.seriesCounts['新系列'], 1);
    expect(index.tagNames, containsAll(['冒险', '热血', '日常']));

    index.remove(second);
    expect(index.seriesNames, ['新系列']);
    expect(index.seriesCounts['新系列'], 1);
    expect(index.tagNames, ['日常']);
  });

  test('groups series case-insensitively and handles unusual characters', () {
    final index = LibraryIndex();
    final upper = _book('1', 'Vol 1', series: 'One Piece');
    final lower = _book('2', '🚀🎉✨', series: 'one piece');
    index.rebuild([upper, lower]);

    expect(index.seriesCounts.values.single, 2);
    expect(index.matches(upper, 'one piece'), isTrue);
    expect(index.matches(lower, '🚀'), isTrue);
  });
}
