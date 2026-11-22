import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:manhua_reader/formats/archive_comic_source.dart';
import 'package:manhua_reader/formats/zip/image_size.dart';
import 'package:manhua_reader/formats/zip/zip_archive_reader.dart';

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('manhua_zip_test_');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('reads image dimensions from common headers', () {
    final jpeg = _jpeg(120, 180);
    final png = _png(200, 300);
    expect(readImageDimensions(jpeg), (width: 120, height: 180));
    expect(readImageDimensions(png), (width: 200, height: 300));

    final gif = Uint8List(13)
      ..setAll(0, 'GIF89a'.codeUnits)
      ..[6] = 0x20
      ..[7] = 0x03
      ..[8] = 0x58
      ..[9] = 0x02;
    expect(readImageDimensions(gif), (width: 800, height: 600));

    final bmp = Uint8List(30)
      ..setAll(0, 'BM'.codeUnits)
      ..[18] = 0x40
      ..[19] = 0x01
      ..[22] = 0x2C
      ..[23] = 0x01;
    expect(readImageDimensions(bmp), (width: 320, height: 300));

    final webp = Uint8List(30)
      ..setAll(0, 'RIFF'.codeUnits)
      ..setAll(8, 'WEBP'.codeUnits)
      ..setAll(12, 'VP8X'.codeUnits)
      ..[24] = 0x8F
      ..[25] = 0x00
      ..[26] = 0x00
      ..[27] = 0x2B
      ..[28] = 0x00
      ..[29] = 0x00;
    expect(readImageDimensions(webp), (width: 144, height: 44));

    expect(readImageDimensions(Uint8List.fromList([1, 2, 3])), isNull);
  });

  test('sorts pages naturally and keeps image bytes intact', () async {
    final first = _jpeg(120, 180);
    final second = _jpeg(121, 181);
    final tenth = _jpeg(122, 182);
    final cover = _png(200, 300);
    final archive = Archive()
      ..add(_file('chapter/page10.jpg', tenth))
      ..add(_file('chapter/page2.jpg', second))
      ..add(_file('chapter/page1.jpg', first))
      ..add(_file('cover.png', cover, store: true))
      ..add(_file('__MACOSX/._page1.jpg', first))
      ..add(_file('.hidden.jpg', first))
      ..add(_file('notes.txt', Uint8List.fromList('not an image'.codeUnits)));
    final path = await _write(temp, 'volume.cbz', _zipBytes(archive));

    final reader = await ZipArchiveReader.open(path);
    try {
      expect(reader.pages.map((page) => page.path), [
        'chapter/page1.jpg',
        'chapter/page2.jpg',
        'chapter/page10.jpg',
        'cover.png',
      ]);
      expect(await reader.readPageBytes(0), first);
      expect(await reader.readPageBytes(1), second);
      expect(await reader.readPageBytes(3), cover);
      expect(readImageDimensions(await reader.readPagePrefix(0)), (
        width: 120,
        height: 180,
      ));
      expect(readImageDimensions(await reader.readPagePrefix(3)), (
        width: 200,
        height: 300,
      ));
    } finally {
      await reader.dispose();
    }
  });

  test('builds a chapter table of contents from top-level folders', () async {
    final page = _jpeg(100, 150);
    final archive = Archive()
      ..add(_file('chapter-1/001.jpg', page))
      ..add(_file('chapter-1/002.jpg', page))
      ..add(_file('chapter-2/001.jpg', page));
    final path = await _write(temp, 'chapters.cbz', _zipBytes(archive));

    final source = await ArchiveComicSource.open(path);
    try {
      expect(source.pageCount, 3);
      expect(source.pageSize(0).width, 100);
      expect(source.pageSize(0).height, 150);
      final toc = await source.loadToc();
      expect(toc.map((entry) => entry.title), ['chapter-1', 'chapter-2']);
      expect(toc.map((entry) => entry.page), [0, 2]);
    } finally {
      await source.dispose();
    }
  });

  test('rejects damaged, empty and encrypted archives', () async {
    final random = await _write(
      temp,
      'broken.cbz',
      Uint8List.fromList(List<int>.filled(128, 7)),
    );
    await expectLater(
      ZipArchiveReader.open(random),
      throwsA(isA<ZipArchiveException>()),
    );

    final empty = await _write(
      temp,
      'empty.cbz',
      _zipBytes(Archive()..add(_file('readme.txt', Uint8List(4)))),
    );
    await expectLater(
      ZipArchiveReader.open(empty),
      throwsA(
        isA<ZipArchiveException>().having(
          (error) => error.message,
          'message',
          contains('没有可显示的图片'),
        ),
      ),
    );

    final encrypted = _zipBytes(
      Archive()..add(_file('page.jpg', _jpeg(10, 10))),
    );
    final header = _findSignature(encrypted, [0x50, 0x4B, 0x01, 0x02]);
    encrypted[header + 8] |= 0x01;
    final encryptedPath = await _write(temp, 'encrypted.cbz', encrypted);
    await expectLater(
      ZipArchiveReader.open(encryptedPath),
      throwsA(
        isA<ZipArchiveException>().having(
          (error) => error.message,
          'message',
          contains('加密'),
        ),
      ),
    );

    final unsupported = _zipBytes(
      Archive()..add(_file('page.jpg', _jpeg(10, 10))),
    );
    final unsupportedHeader = _findSignature(unsupported, [
      0x50,
      0x4B,
      0x01,
      0x02,
    ]);
    unsupported[unsupportedHeader + 10] = 99;
    final unsupportedPath = await _write(temp, 'unsupported.cbz', unsupported);
    await expectLater(
      ZipArchiveReader.open(unsupportedPath),
      throwsA(
        isA<ZipArchiveException>().having(
          (error) => error.message,
          'message',
          contains('压缩方式'),
        ),
      ),
    );
  });
}

ArchiveFile _file(String name, Uint8List bytes, {bool store = false}) {
  final file = ArchiveFile.bytes(name, bytes);
  if (store) file.compression = CompressionType.none;
  return file;
}

Uint8List _zipBytes(Archive archive) =>
    Uint8List.fromList(ZipEncoder().encodeBytes(archive));

Uint8List _jpeg(int width, int height) {
  final picture = image.Image(width: width, height: height);
  image.fill(picture, color: image.ColorRgb8(240, 240, 240));
  return Uint8List.fromList(image.encodeJpg(picture, quality: 85));
}

Uint8List _png(int width, int height) {
  final picture = image.Image(width: width, height: height);
  image.fill(picture, color: image.ColorRgb8(30, 60, 90));
  return Uint8List.fromList(image.encodePng(picture));
}

Future<String> _write(Directory directory, String name, List<int> bytes) async {
  final file = File('${directory.path}/$name');
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}

int _findSignature(Uint8List bytes, List<int> signature) {
  for (var index = 0; index + signature.length <= bytes.length; index++) {
    var matches = true;
    for (var offset = 0; offset < signature.length; offset++) {
      if (bytes[index + offset] != signature[offset]) {
        matches = false;
        break;
      }
    }
    if (matches) return index;
  }
  throw StateError('Signature not found');
}
