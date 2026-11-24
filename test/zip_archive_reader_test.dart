import 'dart:convert';
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

  test('opens with sampled sizes and resolves pages on demand', () async {
    final archive = Archive();
    for (var index = 0; index < 30; index++) {
      final page = index == 12 ? _jpeg(200, 300) : _jpeg(120, 180);
      archive.add(_file('page${index + 1}.jpg', page));
    }
    final path = await _write(temp, 'lazy.cbz', _zipBytes(archive));

    ArchiveComicSource.debugSizeProbes = 0;
    final source = await ArchiveComicSource.open(path);
    var changes = 0;
    void onSizesChanged() => changes++;
    source.pageSizesChanged.addListener(onSizesChanged);
    try {
      expect(source.pageCount, 30);
      expect(ArchiveComicSource.debugSizeProbes, 2);
      expect(source.pageSize(12).width, 120);

      await source.ensurePageSizes([12]);
      await Future<void>.delayed(Duration.zero);
      expect(source.pageSize(12).width, 200);
      expect(source.pageSize(12).height, 300);
      expect(changes, 1);

      await source.readPageBytes(12);
      await Future<void>.delayed(Duration.zero);
      expect(ArchiveComicSource.debugSizeProbes, 3);
      expect(changes, 1);
    } finally {
      source.pageSizesChanged.removeListener(onSizesChanged);
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

  test('reads WebP VP8L > 1024px, BMP BITMAPCOREHEADER, and EXIF orientation', () {
    // WebP VP8L: 1200 x 2500 -> (1199) | (2499 << 14).
    const w = 1200;
    const h = 2500;
    final packed = (w - 1) | ((h - 1) << 14);
    final vp8l = Uint8List(25)
      ..setAll(0, ascii.encode('RIFF'))
      ..setAll(8, ascii.encode('WEBP'))
      ..setAll(12, ascii.encode('VP8L'))
      ..[20] = 0x2F
      ..[21] = packed & 0xFF
      ..[22] = (packed >> 8) & 0xFF
      ..[23] = (packed >> 16) & 0xFF
      ..[24] = (packed >> 24) & 0xFF;
    expect(readImageDimensions(vp8l), (width: 1200, height: 2500));

    // BMP BITMAPCOREHEADER (dibSize == 12): 16-bit LE width=640, height=480.
    final coreBmp = Uint8List(26)..setAll(0, ascii.encode('BM'));
    final coreBd = ByteData.sublistView(coreBmp);
    coreBd.setUint32(14, 12, Endian.little);
    coreBd.setUint16(18, 640, Endian.little);
    coreBd.setUint16(20, 480, Endian.little);
    expect(readImageDimensions(coreBmp), (width: 640, height: 480));

    // JPEG 120x180 with EXIF APP1 Orientation = 6 (90° CW -> swaps to 180x120).
    final baseJpeg = _jpeg(120, 180);
    final exifJpeg = _withExifOrientation(baseJpeg, 6);
    expect(readImageDimensions(exifJpeg), (width: 180, height: 120));
  });

  test('accounts cache properly on concurrent reads, guards ZIP64 bounds and zip bombs', () async {
    final p1 = _jpeg(100, 120);
    final p2 = _jpeg(110, 130);
    final archive = Archive()
      ..add(_file('001.jpg', p1))
      ..add(_file('002.jpg', p2));
    final path = await _write(temp, 'concurrent.cbz', _zipBytes(archive));
    final reader = await ZipArchiveReader.open(path);
    try {
      final concurrent = await Future.wait([
        reader.readPageBytes(0),
        reader.readPageBytes(0),
        reader.readPageBytes(1),
      ]);
      expect(concurrent[0], same(concurrent[1]));
      expect(concurrent[2], p2);
    } finally {
      await reader.dispose();
    }

    // Malformed ZIP64 extra field claiming a larger block than available bytes.
    final zip64BadExtra = Uint8List.fromList([
      0x01, 0x00, // ZIP64 tag
      0x18, 0x00, // 24-byte block size, but only 8 bytes remain
      0, 0, 0, 0, 0, 0, 0, 0,
    ]);
    final badZip64Path = await _write(
      temp,
      'bad64.cbz',
      _craftSingleEntryZip(
        'page.jpg',
        p1,
        compressionMethod: 0,
        uncompressedSize: 0xFFFFFFFF,
        cdExtra: zip64BadExtra,
      ),
    );
    final bad64Reader = await ZipArchiveReader.open(badZip64Path);
    try {
      // Truncated ZIP64 extra field must not cause RangeError; reading still works cleanly.
      expect(await bad64Reader.readPageBytes(0), p1);
    } finally {
      await bad64Reader.dispose();
    }

    // Deflate zip bomb expanding beyond 64 MB limit aborts early.
    final bombRaw = Uint8List.fromList(
      ZLibCodec(raw: true).encode(Uint8List(65 * 1024 * 1024)),
    );
    final bombPath = await _write(
      temp,
      'bomb.cbz',
      _craftSingleEntryZip(
        'bomb.jpg',
        bombRaw,
        compressionMethod: 8,
        uncompressedSize: 512,
      ),
    );
    final bombReader = await ZipArchiveReader.open(bombPath);
    try {
      await expectLater(
        bombReader.readPageBytes(0),
        throwsA(isA<ZipArchiveException>()),
      );
    } finally {
      await bombReader.dispose();
    }
  });
}

Uint8List _withExifOrientation(Uint8List jpeg, int orientation) {
  // TIFF header ('II' LE, 0x002A, IFD0 offset=8) + 1 entry (0x0112 SHORT 1 orientation).
  final tiff = Uint8List(26);
  tiff.setAll(0, ascii.encode('II'));
  final tbd = ByteData.sublistView(tiff);
  tbd.setUint16(2, 42, Endian.little);
  tbd.setUint32(4, 8, Endian.little);
  tbd.setUint16(8, 1, Endian.little); // 1 directory entry
  tbd.setUint16(10, 0x0112, Endian.little); // Orientation tag
  tbd.setUint16(12, 3, Endian.little); // SHORT
  tbd.setUint32(14, 1, Endian.little);
  tbd.setUint16(18, orientation, Endian.little);

  final payload = BytesBuilder()
    ..add(ascii.encode('Exif'))
    ..add([0, 0])
    ..add(tiff);
  final app1Data = payload.toBytes();
  final app1 = BytesBuilder()
    ..add([0xFF, 0xE1])
    ..add([
      ((app1Data.length + 2) >> 8) & 0xFF,
      (app1Data.length + 2) & 0xFF,
    ])
    ..add(app1Data);

  final out = BytesBuilder()
    ..add(jpeg.sublist(0, 2))
    ..add(app1.toBytes())
    ..add(jpeg.sublist(2));
  return Uint8List.fromList(out.toBytes());
}

Uint8List _craftSingleEntryZip(
  String name,
  Uint8List payload, {
  required int compressionMethod,
  required int uncompressedSize,
  Uint8List? cdExtra,
}) {
  final nameBytes = utf8.encode(name);
  final extra = cdExtra ?? Uint8List(0);
  final lfh = Uint8List(30 + nameBytes.length);
  final lbd = ByteData.sublistView(lfh);
  lbd.setUint32(0, 0x04034B50, Endian.little);
  lbd.setUint16(4, 20, Endian.little);
  lbd.setUint16(8, compressionMethod, Endian.little);
  lbd.setUint32(18, payload.length, Endian.little);
  lbd.setUint32(22, uncompressedSize, Endian.little);
  lbd.setUint16(26, nameBytes.length, Endian.little);
  lfh.setAll(30, nameBytes);

  final cdOffset = lfh.length + payload.length;
  final cdh = Uint8List(46 + nameBytes.length + extra.length);
  final cbd = ByteData.sublistView(cdh);
  cbd.setUint32(0, 0x02014B50, Endian.little);
  cbd.setUint16(4, 20, Endian.little);
  cbd.setUint16(6, 20, Endian.little);
  cbd.setUint16(10, compressionMethod, Endian.little);
  cbd.setUint32(20, payload.length, Endian.little);
  cbd.setUint32(24, uncompressedSize, Endian.little);
  cbd.setUint16(28, nameBytes.length, Endian.little);
  cbd.setUint16(30, extra.length, Endian.little);
  cdh.setAll(46, nameBytes);
  cdh.setAll(46 + nameBytes.length, extra);

  final eocd = Uint8List(22);
  final ebd = ByteData.sublistView(eocd);
  ebd.setUint32(0, 0x06054B50, Endian.little);
  ebd.setUint16(8, 1, Endian.little);
  ebd.setUint16(10, 1, Endian.little);
  ebd.setUint32(12, cdh.length, Endian.little);
  ebd.setUint32(16, cdOffset, Endian.little);

  return Uint8List.fromList([
    ...lfh,
    ...payload,
    ...cdh,
    ...eocd,
  ]);
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
