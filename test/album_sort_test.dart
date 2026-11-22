import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:manhua_reader/formats/album/album_store.dart';
import 'package:manhua_reader/models/comic_book.dart';
import 'package:path/path.dart' as p;

void main() {
  test('sorts by natural name in both directions', () {
    final images = [
      _image('page10.jpg'),
      _image('page2.jpg'),
      _image('page1.jpg'),
    ];
    expect(
      sortAlbumImages(
        images,
        AlbumSortField.name,
        false,
      ).map((image) => image.name),
      ['page1.jpg', 'page2.jpg', 'page10.jpg'],
    );
    expect(
      sortAlbumImages(
        images,
        AlbumSortField.name,
        true,
      ).map((image) => image.name),
      ['page10.jpg', 'page2.jpg', 'page1.jpg'],
    );
  });

  test('sorts by creation and modification times', () {
    final images = [
      _image(
        'b.jpg',
        created: DateTime(2026, 1, 2),
        modified: DateTime(2026, 3, 2),
      ),
      _image(
        'a.jpg',
        created: DateTime(2026, 1, 1),
        modified: DateTime(2026, 3, 3),
      ),
      _image(
        'c.jpg',
        created: DateTime(2026, 1, 3),
        modified: DateTime(2026, 3, 1),
      ),
    ];
    expect(
      sortAlbumImages(
        images,
        AlbumSortField.created,
        false,
      ).map((image) => image.name),
      ['a.jpg', 'b.jpg', 'c.jpg'],
    );
    expect(
      sortAlbumImages(
        images,
        AlbumSortField.created,
        true,
      ).map((image) => image.name),
      ['c.jpg', 'b.jpg', 'a.jpg'],
    );
    expect(
      sortAlbumImages(
        images,
        AlbumSortField.modified,
        false,
      ).map((image) => image.name),
      ['c.jpg', 'b.jpg', 'a.jpg'],
    );
  });

  test('puts images without timestamps last', () {
    final images = [
      _image('unknown.jpg'),
      _image('known.jpg', modified: DateTime(2026, 1, 1)),
    ];
    expect(
      sortAlbumImages(images, AlbumSortField.modified, false).last.name,
      'unknown.jpg',
    );
    expect(
      sortAlbumImages(images, AlbumSortField.modified, true).last.name,
      'unknown.jpg',
    );
  });

  test('file store sorts by modification time', () async {
    final temp = await Directory.systemTemp.createTemp('album_sort_files_');
    addTearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });
    final first = File(p.join(temp.path, 'a.jpg'))..writeAsBytesSync([1, 2, 3]);
    final second = File(p.join(temp.path, 'b.jpg'))
      ..writeAsBytesSync([1, 2, 3]);
    final third = File(p.join(temp.path, 'c.jpg'))..writeAsBytesSync([1, 2, 3]);
    await first.setLastModified(DateTime(2026, 1, 3));
    await second.setLastModified(DateTime(2026, 1, 1));
    await third.setLastModified(DateTime(2026, 1, 2));

    final store = FileAlbumStore(temp.path);
    final ascending = await store.list(
      sort: AlbumSortField.modified,
      descending: false,
    );
    expect(ascending.map((image) => image.name), ['b.jpg', 'c.jpg', 'a.jpg']);
    final descending = await store.list(
      sort: AlbumSortField.modified,
      descending: true,
    );
    expect(descending.map((image) => image.name), ['a.jpg', 'c.jpg', 'b.jpg']);
  });
}

AlbumImage _image(String name, {DateTime? created, DateTime? modified}) {
  return AlbumImage(
    relativePath: name,
    name: name,
    size: 10,
    width: 100,
    height: 150,
    created: created,
    modified: modified,
  );
}
