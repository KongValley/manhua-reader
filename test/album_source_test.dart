import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:manhua_reader/formats/album/album_store.dart';
import 'package:manhua_reader/formats/album_comic_source.dart';

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('manhua_album_source_');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('scans images naturally and ignores non-image files', () async {
    await _write(temp, 'page10.jpg', _jpeg(120, 180));
    await _write(temp, 'page2.jpg', _jpeg(121, 181));
    await _write(temp, 'page1.jpg', _jpeg(122, 182));
    await _write(temp, 'cover.png', _png(200, 300));
    await _write(temp, '.hidden.jpg', _jpeg(10, 10));
    await _write(temp, '__MACOSX/._page1.jpg', _jpeg(10, 10));
    await _write(temp, 'notes.txt', Uint8List.fromList('hello'.codeUnits));

    final store = FileAlbumStore(temp.path);
    final images = await store.list();
    expect(images.map((image) => image.relativePath), [
      'cover.png',
      'page1.jpg',
      'page2.jpg',
      'page10.jpg',
    ]);
    expect(images.first.width, 0);
    expect(images.first.height, 0);
    expect(await store.readBytes(images[1]), await _read(temp, 'page1.jpg'));
    await store.dispose();
  });

  test('builds a chapter table of contents from subfolders', () async {
    await _write(temp, 'cover.jpg', _jpeg(100, 150));
    await _write(temp, 'chapter-1/001.jpg', _jpeg(100, 150));
    await _write(temp, 'chapter-1/002.jpg', _jpeg(100, 150));
    await _write(temp, 'chapter-2/001.jpg', _jpeg(100, 150));

    final source = await AlbumComicSource.open(temp.path);
    var changes = 0;
    void onSizesChanged() => changes++;
    source.pageSizesChanged.addListener(onSizesChanged);
    try {
      expect(source.pageCount, 4);
      await source.ensurePageSizes([1]);
      await Future<void>.delayed(Duration.zero);
      expect(source.pageSize(1), const Size(100, 150));
      expect(changes, 1);
      final toc = await source.loadToc();
      expect(toc.map((entry) => entry.title), ['chapter-1', 'chapter-2']);
      expect(toc.map((entry) => entry.page), [0, 2]);
      final bytes = await source.readPageBytes(0);
      expect(bytes, isNotEmpty);
      expect(source.pageSize(0), const Size(100, 150));
    } finally {
      source.pageSizesChanged.removeListener(onSizesChanged);
      await source.dispose();
    }
  });

  test('reports an empty or missing folder', () async {
    await expectLater(
      FileAlbumStore(temp.path).list(),
      throwsA(isA<AlbumSourceException>()),
    );
    final missing = Directory('${temp.path}/missing');
    await expectLater(
      FileAlbumStore(missing.path).list(),
      throwsA(
        isA<AlbumSourceException>().having(
          (error) => error.message,
          'message',
          contains('不可用'),
        ),
      ),
    );
  });
}

Future<void> _write(Directory root, String relative, Uint8List bytes) async {
  final file = File('${root.path}/$relative');
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes, flush: true);
}

Future<Uint8List> _read(Directory root, String relative) =>
    File('${root.path}/$relative').readAsBytes();

Uint8List _jpeg(int width, int height) {
  final picture = image.Image(width: width, height: height);
  image.fill(picture, color: image.ColorRgb8(220, 220, 220));
  return Uint8List.fromList(image.encodeJpg(picture, quality: 85));
}

Uint8List _png(int width, int height) {
  final picture = image.Image(width: width, height: height);
  image.fill(picture, color: image.ColorRgb8(30, 60, 90));
  return Uint8List.fromList(image.encodePng(picture));
}
