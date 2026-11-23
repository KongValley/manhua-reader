import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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
}
