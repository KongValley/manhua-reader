import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:manhua_reader/formats/mobi/mobi_book.dart';

void main() {
  final sample = File('test/VOL.001.mobi');

  group('MobiBook', () {
    test('reads comic metadata and the HTML reading order', () async {
      final book = await MobiBook.open(sample.path);

      expect(book.title, 'VOL.001');
      expect(book.pageCount, 196);
      expect(book.images, hasLength(196));
      expect(book.toc, isEmpty);

      // The color cover comes from EXTH and is not part of the HTML sequence.
      // 彩色封面来自 EXTH，不属于 HTML 阅读顺序。
      final cover = book.images.first;
      expect(cover.recordIndex, 111);
      expect(cover.length, 807199);
      expect(cover.type, MobiImageType.jpeg);
      expect(cover.hasSize, isTrue);
      expect(cover.width, greaterThan(500));
      expect(cover.height, greaterThan(500));

      // The HTML references pages out of physical record order:
      // recindex 47 -> record 53, recindex 61 -> record 67, ...
      // HTML 引用的页面与物理记录顺序不同：
      // recindex 47 -> 记录 53，recindex 61 -> 记录 67，……
      expect(book.images.take(3).map((image) => image.recordIndex).toList(), [
        111,
        53,
        67,
      ]);
      expect(book.images[1].length, 314483);
      expect(book.images[2].length, 175849);

      final sized = book.images.where((image) => image.hasSize).length;
      expect(sized, greaterThan(190));
    });

    test('loads page bytes lazily from disk', () async {
      final book = await MobiBook.open(sample.path);
      try {
        final bytes = await book.readPage(0);
        expect(bytes.length, book.images.first.length);
        expect(bytes[0], 0xFF);
        expect(bytes[1], 0xD8);
        expect(bytes[2], 0xFF);
        expect(await book.readPage(0), same(bytes));
        final concurrent = await Future.wait([
          book.readPage(3),
          book.readPage(3),
        ]);
        expect(concurrent[0], same(concurrent[1]));
      } finally {
        await book.dispose();
      }
      await expectLater(book.readPage(0), throwsA(isA<MobiException>()));
    });

    test('rejects non-MOBI files', () async {
      await expectLater(
        MobiBook.open('test/VOL.001.pdf'),
        throwsA(isA<MobiException>()),
      );
    });
  }, skip: sample.existsSync() ? null : 'test/VOL.001.mobi is missing');

  group('MobiBook bugfix regressions', () {
    late Directory temp;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('manhua_mobi_reg_');
    });

    tearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    test('decompresses PalmDOC LZ77 backreferences including overlap and guards zero distance', () async {
      final jpeg1 = _makeJpeg(40, 60);
      final jpeg2 = _makeJpeg(50, 70);
      // 1) '<img recindex="00001" alt="A' (28 bytes; bytes 5..14 == 'recindex="')
      // 2) overlap RLE: distance=1, len=4 -> appends 'AAAA' -> total 32 bytes
      // 3) '"/><img ' (8 bytes) -> total 40 bytes; distance from pos 5 = 35
      // 4) LZ77 copy: distance=35, len=10 -> copies 'recindex="'
      // 5) '00002"/><!-- ' + invalid distance=0 token + ' -->'
      final compressedText = BytesBuilder()
        ..add(ascii.encode('<img recindex="00001" alt="A'))
        ..add([0x80, (1 << 3) | 1])
        ..add(ascii.encode('"/><img '))
        ..add([0x80 | (35 >> 5), ((35 & 0x1F) << 3) | 7])
        ..add(ascii.encode('00002"/><!-- '))
        ..add([0x80, 0x00]) // invalid distance=0 token safely skipped
        ..add(ascii.encode(' -->'));

      final file = File('${temp.path}/lz77.mobi');
      await file.writeAsBytes(
        _buildSyntheticMobi(
          textRecords: [Uint8List.fromList(compressedText.toBytes())],
          imageRecords: [jpeg1, jpeg2],
          compression: 2,
          extraDataFlags: 0,
        ),
        flush: true,
      );

      final book = await MobiBook.open(file.path);
      try {
        expect(book.pageCount, 2);
        expect(book.images[0].width, 40);
        expect(book.images[1].width, 50);
      } finally {
        await book.dispose();
      }
    });

    test('strips PalmDOC extraDataFlags trailers before parsing HTML', () async {
      final jpeg1 = _makeJpeg(40, 60);
      final jpeg2 = _makeJpeg(50, 70);
      // Real body only references recindex=1; extra trailer hides a decoy recindex=2.
      final body = ascii.encode('<img recindex="00001"/>');
      final decoy = ascii.encode('<img recindex="00002"/>');
      // extraDataFlags = 0x03 (bit 1 backward varint section + bit 0 trailing overlap).
      // Bit 1 size includes the varint size byte itself: decoy.length + 1.
      final bit1Trailer = <int>[...decoy, (decoy.length + 1) | 0x80];
      const bit0Overlap = <int>[0x00]; // (0x00 & 0x03) + 1 = 1 byte overlap
      final recordBytes = Uint8List.fromList([
        ...body,
        ...bit0Overlap,
        ...bit1Trailer,
      ]);

      final file = File('${temp.path}/extra_flags.mobi');
      await file.writeAsBytes(
        _buildSyntheticMobi(
          textRecords: [recordBytes],
          imageRecords: [jpeg1, jpeg2],
          compression: 1,
          extraDataFlags: 0x03,
        ),
        flush: true,
      );

      final book = await MobiBook.open(file.path);
      try {
        // Decoy image 2 inside extraData trailer was stripped, leaving only page 1.
        expect(book.pageCount, 1);
        expect(book.images.single.width, 40);
      } finally {
        await book.dispose();
      }
    });

    test('handles short MOBI header and invalid record offsets safely', () async {
      final jpeg1 = _makeJpeg(40, 60);
      final shortFile = File('${temp.path}/short_header.mobi');
      await shortFile.writeAsBytes(
        _buildSyntheticMobi(
          textRecords: [ascii.encode('<img recindex="00001"/>')],
          imageRecords: [jpeg1],
          compression: 1,
          mobiHeaderLength: 48,
        ),
        flush: true,
      );
      final shortBook = await MobiBook.open(shortFile.path);
      try {
        expect(shortBook.pageCount, 1);
      } finally {
        await shortBook.dispose();
      }

      // Corrupt text record offset (record 1 at table offset 86) is safely skipped without OOB crash.
      final badBytes = _buildSyntheticMobi(
        textRecords: [ascii.encode('<img recindex="00001"/>')],
        imageRecords: [jpeg1],
        compression: 1,
      );
      final badTextCopy = Uint8List.fromList(badBytes);
      ByteData.sublistView(badTextCopy).setUint32(86, 0x7FFFFFFF, Endian.big);
      final badTextFile = File('${temp.path}/bad_text_offset.mobi');
      await badTextFile.writeAsBytes(badTextCopy, flush: true);
      final recovered = await MobiBook.open(badTextFile.path);
      try {
        expect(recovered.pageCount, 1);
      } finally {
        await recovered.dispose();
      }

      // Corrupt record 0 offset (at table offset 78) must throw MobiException.
      final badRootCopy = Uint8List.fromList(badBytes);
      ByteData.sublistView(badRootCopy).setUint32(78, 0x7FFFFFFF, Endian.big);
      final badRootFile = File('${temp.path}/bad_root_offset.mobi');
      await badRootFile.writeAsBytes(badRootCopy, flush: true);
      await expectLater(
        MobiBook.open(badRootFile.path),
        throwsA(isA<MobiException>()),
      );
    });
  });
}

Uint8List _makeJpeg(int width, int height) {
  final pic = image.Image(width: width, height: height);
  image.fill(pic, color: image.ColorRgb8(200, 180, 160));
  return Uint8List.fromList(image.encodeJpg(pic, quality: 80));
}

Uint8List _buildSyntheticMobi({
  required List<Uint8List> textRecords,
  required List<Uint8List> imageRecords,
  required int compression,
  int mobiHeaderLength = 232,
  int extraDataFlags = 0,
}) {
  final firstImageRecord = 1 + textRecords.length;
  final titleBytes = utf8.encode('SyntheticComic');
  final record0Len = 16 + mobiHeaderLength + titleBytes.length;
  final record0 = Uint8List(record0Len);
  final r0 = ByteData.sublistView(record0);
  r0.setUint16(0, compression, Endian.big);
  r0.setUint32(
    4,
    textRecords.fold<int>(0, (sum, r) => sum + r.length),
    Endian.big,
  );
  r0.setUint16(8, textRecords.length, Endian.big);
  r0.setUint16(10, 4096, Endian.big);
  record0.setAll(16, ascii.encode('MOBI'));
  r0.setUint32(20, mobiHeaderLength, Endian.big);
  r0.setUint32(28, 65001, Endian.big); // UTF-8
  if (mobiHeaderLength >= 76) {
    final titleOffset = 16 + mobiHeaderLength;
    r0.setUint32(84, titleOffset, Endian.big);
    r0.setUint32(88, titleBytes.length, Endian.big);
    record0.setAll(titleOffset, titleBytes);
  }
  if (mobiHeaderLength >= 96) {
    r0.setUint32(108, firstImageRecord, Endian.big);
  }
  if (mobiHeaderLength >= 228) {
    r0.setUint32(240, extraDataFlags, Endian.big);
  }

  final records = <Uint8List>[record0, ...textRecords, ...imageRecords];
  final tableOffset = 78;
  final dataStart = tableOffset + records.length * 8 + 2;
  final out = BytesBuilder();
  final header = Uint8List(78);
  header.setAll(0, ascii.encode('TestBook'));
  header.setAll(60, ascii.encode('BOOKMOBI'));
  ByteData.sublistView(header).setUint16(76, records.length, Endian.big);
  out.add(header);

  var cursor = dataStart;
  final table = Uint8List(records.length * 8);
  final tbd = ByteData.sublistView(table);
  for (var i = 0; i < records.length; i++) {
    tbd.setUint32(i * 8, cursor, Endian.big);
    tbd.setUint32(i * 8 + 4, i, Endian.big);
    cursor += records[i].length;
  }
  out.add(table);
  out.add(const [0, 0]);
  for (final rec in records) {
    out.add(rec);
  }
  return Uint8List.fromList(out.toBytes());
}
