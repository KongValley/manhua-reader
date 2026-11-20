import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../models/toc_entry.dart';

/// Thrown when a MOBI file cannot be read as a comic.
class MobiException implements Exception {
  MobiException(this.message);

  final String message;

  @override
  String toString() => message;
}

enum MobiImageType { jpeg, png, gif, bmp, webp }

/// One image record inside a MOBI/PalmDB file. Each record is a complete
/// image, so pages can be read lazily straight from disk.
class MobiImage {
  const MobiImage({
    required this.recordIndex,
    required this.offset,
    required this.length,
    required this.type,
    this.width = 0,
    this.height = 0,
  });

  final int recordIndex;
  final int offset;
  final int length;
  final MobiImageType type;
  final int width;
  final int height;

  bool get hasSize => width > 0 && height > 0;

  double get aspectRatio {
    if (!hasSize) return 0.7;
    return width / height;
  }
}

/// A comic-style MOBI: metadata plus the ordered list of embedded images.
///
/// Only the PalmDB record table and the MOBI/EXTH header are read up-front.
/// Page bytes are fetched on demand, which keeps a 100 MB volume cheap to open.
class MobiBook {
  MobiBook._({
    required this.path,
    required this.title,
    required this.language,
    required this.images,
    required this.toc,
  });

  final String path;
  final String title;
  final String? language;

  /// Images in reading order (not necessarily physical record order). The
  /// first entry is the cover when the file declares one via EXTH.
  final List<MobiImage> images;
  final List<TocEntry> toc;

  int get pageCount => images.length;

  static Future<MobiBook> open(String path, {String? fallbackTitle}) async {
    final file = File(path);
    if (!await file.exists()) {
      throw MobiException('文件不存在：$path');
    }
    final fileLength = await file.length();
    if (fileLength < 88) {
      throw MobiException('MOBI 文件不完整');
    }

    final raf = await file.open();
    try {
      final header = await raf.read(78);
      if (header.length < 78) throw MobiException('MOBI 文件头不完整');

      final databaseType = _ascii(header, 60, 4);
      if (databaseType != 'BOOK') {
        throw MobiException('不是有效的 MOBI 文件（类型：$databaseType）');
      }

      final recordCount = _u16be(header, 76);
      if (recordCount <= 0) throw MobiException('MOBI 文件没有内容记录');

      final tableBytes = await raf.read(recordCount * 8);
      if (tableBytes.length < recordCount * 8) {
        throw MobiException('MOBI 记录表不完整');
      }
      final offsets = List<int>.filled(recordCount, 0);
      for (var i = 0; i < recordCount; i++) {
        offsets[i] = _u32be(tableBytes, i * 8);
      }

      int recordEnd(int i) => i + 1 < recordCount ? offsets[i + 1] : fileLength;

      if (offsets[0] < 78 || offsets[0] >= fileLength) {
        throw MobiException('MOBI 记录偏移无效');
      }

      final firstRecordLength = math.min(
        math.max(recordEnd(0) - offsets[0], 0),
        1024 * 1024,
      );
      await raf.setPosition(offsets[0]);
      final record0 = await raf.read(firstRecordLength);

      final info = _readMobiHeader(record0);
      final encrypted = _u16be(record0, 12);
      if (encrypted != 0) {
        throw MobiException('该 MOBI 受 DRM 保护，无法读取');
      }

      final recordImages = <MobiImage>[];
      final start =
          info.firstImageRecord > 0 && info.firstImageRecord < recordCount
          ? info.firstImageRecord
          : 1;
      await _collectImages(
        raf: raf,
        fileLength: fileLength,
        recordCount: recordCount,
        offsets: offsets,
        endOfRecord: recordEnd,
        start: start,
        target: recordImages,
      );

      // Some unusual files report a wrong first-image index; fall back to a
      // full scan so that image-only books still open.
      if (recordImages.isEmpty && start > 1) {
        await _collectImages(
          raf: raf,
          fileLength: fileLength,
          recordCount: recordCount,
          offsets: offsets,
          endOfRecord: recordEnd,
          start: 1,
          target: recordImages,
        );
      }

      if (recordImages.isEmpty) {
        throw MobiException('该 MOBI 不含图片，暂不支持纯文字书籍');
      }

      final textInfo = await _readMobiText(
        raf: raf,
        offsets: offsets,
        recordCount: recordCount,
        endOfRecord: recordEnd,
        firstImageRecord: start,
        textRecordCount: info.textRecordCount,
        compression: info.compression,
        encoding: info.encoding,
      );

      final readingOrder = _buildReadingOrder(
        recordImages: recordImages,
        firstImageRecord: start,
        textInfo: textInfo,
        coverEmbed: info.coverEmbed,
      );

      return MobiBook._(
        path: path,
        title: info.title?.trim().isNotEmpty == true
            ? info.title!.trim()
            : (fallbackTitle ?? _baseName(path)),
        language: info.language,
        images: readingOrder.images,
        toc: readingOrder.toc,
      );
    } on MobiException {
      rethrow;
    } on FileSystemException catch (error) {
      throw MobiException('无法读取 MOBI 文件：${error.message}');
    } finally {
      await raf.close();
    }
  }

  static Future<void> _collectImages({
    required RandomAccessFile raf,
    required int fileLength,
    required int recordCount,
    required List<int> offsets,
    required int Function(int) endOfRecord,
    required int start,
    required List<MobiImage> target,
  }) async {
    for (var i = start; i < recordCount; i++) {
      final offset = offsets[i];
      final end = endOfRecord(i);
      final length = end - offset;
      if (length <= 0 || offset < 0 || end > fileLength) continue;

      await raf.setPosition(offset);
      final probe = await raf.read(math.min(length, 8192));
      final type = _detectImageType(probe);
      if (type == null) continue;

      var sizeProbe = probe;
      var size = _imageSize(sizeProbe, type);
      if (size == null && length > sizeProbe.length) {
        final larger = math.min(length, 512 * 1024);
        await raf.setPosition(offset);
        sizeProbe = await raf.read(larger);
        size = _imageSize(sizeProbe, type);
      }

      target.add(
        MobiImage(
          recordIndex: i,
          offset: offset,
          length: length,
          type: type,
          width: size?.width ?? 0,
          height: size?.height ?? 0,
        ),
      );
    }
  }

  /// Reads the raw bytes of one page image.
  Future<Uint8List> readPage(int index) async {
    if (index < 0 || index >= images.length) {
      throw RangeError.index(index, images, 'index');
    }
    final image = images[index];
    final raf = await File(path).open();
    try {
      await raf.setPosition(image.offset);
      final bytes = await raf.read(image.length);
      if (bytes.length != image.length) {
        throw MobiException('读取第 ${index + 1} 页失败');
      }
      return bytes;
    } finally {
      await raf.close();
    }
  }
}

class _MobiHeaderInfo {
  const _MobiHeaderInfo({
    required this.firstImageRecord,
    required this.compression,
    required this.textRecordCount,
    required this.encoding,
    this.title,
    this.language,
    this.coverEmbed,
  });

  final int firstImageRecord;
  final int compression;
  final int textRecordCount;
  final int encoding;
  final String? title;
  final String? language;
  final String? coverEmbed;
}

_MobiHeaderInfo _readMobiHeader(Uint8List record0) {
  if (record0.length < 24 || _ascii(record0, 16, 4) != 'MOBI') {
    throw MobiException('MOBI 头部缺失，可能是不支持的电子书格式');
  }

  final headerLength = _u32be(record0, 20);
  var firstImageRecord = 0;
  final compression = record0.length >= 2 ? _u16be(record0, 0) : 0;
  final textRecordCount = record0.length >= 10 ? _u16be(record0, 8) : 0;
  final encoding = record0.length >= 32 ? _u32be(record0, 28) : 65001;
  String? title;
  String? language;
  String? coverEmbed;

  if (record0.length >= 132) {
    firstImageRecord = _u32be(record0, 108);
    final fullNameOffset = _u32be(record0, 84);
    final fullNameLength = _u32be(record0, 88);
    if (fullNameOffset > 0 &&
        fullNameLength > 0 &&
        fullNameOffset + fullNameLength <= record0.length) {
      title = _decode(
        record0.sublist(fullNameOffset, fullNameOffset + fullNameLength),
      );
    }
  }

  final exthOffset = 16 + headerLength;
  if (exthOffset + 12 <= record0.length &&
      _ascii(record0, exthOffset, 4) == 'EXTH') {
    final exthLength = _u32be(record0, exthOffset + 4);
    final count = _u32be(record0, exthOffset + 8);
    final exthEnd = math.min(
      record0.length,
      math.min(exthOffset + exthLength, record0.length),
    );
    var cursor = exthOffset + 12;
    for (var i = 0; i < count && cursor + 8 <= exthEnd; i++) {
      final type = _u32be(record0, cursor);
      final length = _u32be(record0, cursor + 4);
      if (length < 8 || cursor + length > exthEnd) break;
      final value = record0.sublist(cursor + 8, cursor + length);
      switch (type) {
        case 129: // kindle:embed:XXXX cover
          coverEmbed = _decode(value);
        case 503: // updated title
          title = _decode(value);
        case 524: // language
          language = _decode(value);
      }
      cursor += length;
    }
  }

  return _MobiHeaderInfo(
    firstImageRecord: firstImageRecord,
    compression: compression,
    textRecordCount: textRecordCount,
    encoding: encoding,
    title: title,
    language: language,
    coverEmbed: coverEmbed,
  );
}

/// Detects an image by magic bytes.
MobiImageType? _detectImageType(Uint8List bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xFF &&
      bytes[1] == 0xD8 &&
      bytes[2] == 0xFF) {
    return MobiImageType.jpeg;
  }
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47 &&
      bytes[4] == 0x0D &&
      bytes[5] == 0x0A &&
      bytes[6] == 0x1A &&
      bytes[7] == 0x0A) {
    return MobiImageType.png;
  }
  if (bytes.length >= 6 &&
      bytes[0] == 0x47 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x38) {
    return MobiImageType.gif;
  }
  if (bytes.length >= 26 &&
      bytes[0] == 0x42 &&
      bytes[1] == 0x4D &&
      _u32le(bytes, 14) == 40) {
    return MobiImageType.bmp;
  }
  if (bytes.length >= 12 &&
      _ascii(bytes, 0, 4) == 'RIFF' &&
      _ascii(bytes, 8, 4) == 'WEBP') {
    return MobiImageType.webp;
  }
  return null;
}

class _ImageSize {
  const _ImageSize(this.width, this.height);

  final int width;
  final int height;
}

_ImageSize? _imageSize(Uint8List bytes, MobiImageType type) {
  switch (type) {
    case MobiImageType.jpeg:
      return _jpegSize(bytes);
    case MobiImageType.png:
      if (bytes.length < 24) return null;
      final width = _u32be(bytes, 16);
      final height = _u32be(bytes, 20);
      return width > 0 && height > 0 ? _ImageSize(width, height) : null;
    case MobiImageType.gif:
      if (bytes.length < 10) return null;
      final width = _u16le(bytes, 6);
      final height = _u16le(bytes, 8);
      return width > 0 && height > 0 ? _ImageSize(width, height) : null;
    case MobiImageType.bmp:
      if (bytes.length < 26) return null;
      final width = _i32le(bytes, 18).abs();
      final height = _i32le(bytes, 22).abs();
      return width > 0 && height > 0 ? _ImageSize(width, height) : null;
    case MobiImageType.webp:
      return _webpSize(bytes);
  }
}

_ImageSize? _jpegSize(Uint8List bytes) {
  if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) {
    return null;
  }
  var i = 2;
  while (i + 1 < bytes.length) {
    if (bytes[i] != 0xFF) {
      i++;
      continue;
    }
    while (i < bytes.length && bytes[i] == 0xFF) {
      i++;
    }
    if (i >= bytes.length) return null;
    final marker = bytes[i++];
    if (marker == 0x01 ||
        marker == 0xD8 ||
        marker == 0xD9 ||
        (marker >= 0xD0 && marker <= 0xD7)) {
      continue;
    }
    if (i + 2 > bytes.length) return null;
    final segmentLength = _u16be(bytes, i);
    if (segmentLength < 2) return null;

    final isStartOfFrame =
        marker >= 0xC0 &&
        marker <= 0xCF &&
        marker != 0xC4 &&
        marker != 0xC8 &&
        marker != 0xCC;
    if (isStartOfFrame) {
      if (i + 7 > bytes.length) return null;
      final height = _u16be(bytes, i + 3);
      final width = _u16be(bytes, i + 5);
      return width > 0 && height > 0 ? _ImageSize(width, height) : null;
    }
    i += segmentLength;
  }
  return null;
}

_ImageSize? _webpSize(Uint8List bytes) {
  if (bytes.length < 30) return null;
  final chunk = _ascii(bytes, 12, 4);
  if (chunk == 'VP8X') {
    final width = 1 + (bytes[24] | (bytes[25] << 8) | (bytes[26] << 16));
    final height = 1 + (bytes[27] | (bytes[28] << 8) | (bytes[29] << 16));
    return width > 0 && height > 0 ? _ImageSize(width, height) : null;
  }
  if (chunk == 'VP8 ') {
    // Lossy WebP stores the size after the 3-byte start code.
    for (var i = 20; i + 9 < bytes.length && i < 64; i++) {
      if (bytes[i] == 0x9D && bytes[i + 1] == 0x01 && bytes[i + 2] == 0x2A) {
        final width = _u16le(bytes, i + 3) & 0x3FFF;
        final height = _u16le(bytes, i + 5) & 0x3FFF;
        return width > 0 && height > 0 ? _ImageSize(width, height) : null;
      }
    }
  }
  if (chunk == 'VP8L' && bytes.length >= 25) {
    final b0 = bytes[21];
    final b1 = bytes[22];
    final b2 = bytes[23];
    final b3 = bytes[24];
    final width = 1 + (((b1 & 0x3F) << 8) | b0);
    final height = 1 + (((b3 & 0x0F) << 10) | (b2 << 2) | ((b1 & 0xC0) >> 6));
    return _ImageSize(width, height);
  }
  return null;
}

String _decode(List<int> bytes) =>
    utf8.decode(bytes, allowMalformed: true).replaceAll('\u0000', '').trim();

String _ascii(List<int> bytes, int start, int length) {
  final end = math.min(bytes.length, start + length);
  if (start >= end) return '';
  return String.fromCharCodes(
    bytes.sublist(start, end).map((c) => c >= 32 && c < 127 ? c : 46),
  );
}

String _baseName(String path) {
  final name = p.basenameWithoutExtension(path);
  return name.isEmpty ? '未命名漫画' : name;
}

int _u16be(List<int> bytes, int offset) =>
    (bytes[offset] << 8) | bytes[offset + 1];

int _u16le(List<int> bytes, int offset) =>
    bytes[offset] | (bytes[offset + 1] << 8);

int _u32be(List<int> bytes, int offset) =>
    (bytes[offset] << 24) |
    (bytes[offset + 1] << 16) |
    (bytes[offset + 2] << 8) |
    bytes[offset + 3];

int _u32le(List<int> bytes, int offset) =>
    bytes[offset] |
    (bytes[offset + 1] << 8) |
    (bytes[offset + 2] << 16) |
    (bytes[offset + 3] << 24);

int _i32le(List<int> bytes, int offset) {
  final value = _u32le(bytes, offset);
  return value >= 0x80000000 ? value - 0x100000000 : value;
}

class _MobiHeading {
  const _MobiHeading(this.title, this.level, this.position);

  final String title;
  final int level;
  final int position;
}

class _MobiTextInfo {
  const _MobiTextInfo({
    required this.imageRefs,
    required this.imagePositions,
    required this.headings,
  });

  final List<int> imageRefs;
  final List<int> imagePositions;
  final List<_MobiHeading> headings;
}

class _MobiReadingOrder {
  const _MobiReadingOrder(this.images, this.toc);

  final List<MobiImage> images;
  final List<TocEntry> toc;
}

/// Reads the HTML text records to recover the real reading order.
///
/// Calibre and other tools may store image records in an order that differs
/// from the order of `<img recindex="...">` tags. Using the HTML sequence keeps
/// pages in the intended reading order and lets us drop cover thumbnails that
/// are not part of the book body.
Future<_MobiTextInfo?> _readMobiText({
  required RandomAccessFile raf,
  required List<int> offsets,
  required int recordCount,
  required int Function(int) endOfRecord,
  required int firstImageRecord,
  required int textRecordCount,
  required int compression,
  required int encoding,
}) async {
  if (textRecordCount <= 0 || recordCount <= 1) return null;
  if (compression != 0 && compression != 1 && compression != 2) return null;

  var lastRecord = math.min(textRecordCount, recordCount - 1);
  if (firstImageRecord > 1) {
    lastRecord = math.min(lastRecord, firstImageRecord - 1);
  }

  final builder = BytesBuilder(copy: false);
  var total = 0;
  for (var i = 1; i <= lastRecord; i++) {
    final offset = offsets[i];
    final end = endOfRecord(i);
    final length = end - offset;
    if (length <= 0) continue;
    await raf.setPosition(offset);
    final raw = await raf.read(length);
    final decoded = compression == 2 ? _palmDocDecompress(raw) : raw;
    total += decoded.length;
    if (total > 16 * 1024 * 1024) return null;
    builder.add(decoded);
  }
  if (total == 0) return null;

  final bytes = builder.toBytes();
  final html = (encoding == 65001 || encoding == 0)
      ? utf8.decode(bytes, allowMalformed: true)
      : latin1.decode(bytes, allowInvalid: true);
  if (!html.toLowerCase().contains('<img')) return null;

  final imageRegex = RegExp(
    r'''<img\b[^>]*\brecindex\s*=\s*["']?(\d+)''',
    caseSensitive: false,
  );
  final imageRefs = <int>[];
  final imagePositions = <int>[];
  for (final match in imageRegex.allMatches(html)) {
    final ref = int.tryParse(match.group(1)!);
    if (ref == null) continue;
    imageRefs.add(ref);
    imagePositions.add(match.start);
  }
  if (imageRefs.isEmpty) return null;

  final headingRegex = RegExp(
    r'<h([1-6])\b[^>]*>(.*?)</h\1>',
    caseSensitive: false,
    dotAll: true,
  );
  final headings = <_MobiHeading>[];
  for (final match in headingRegex.allMatches(html)) {
    final level = int.tryParse(match.group(1)!) ?? 1;
    final title = _plainText(match.group(2)!);
    if (title.isEmpty) continue;
    headings.add(_MobiHeading(title, (level - 1).clamp(0, 5), match.end));
  }

  return _MobiTextInfo(
    imageRefs: imageRefs,
    imagePositions: imagePositions,
    headings: headings,
  );
}

_MobiReadingOrder _buildReadingOrder({
  required List<MobiImage> recordImages,
  required int firstImageRecord,
  required _MobiTextInfo? textInfo,
  required String? coverEmbed,
}) {
  final byRecIndex = <int, MobiImage>{};
  for (final image in recordImages) {
    final recIndex = image.recordIndex - firstImageRecord + 1;
    if (recIndex > 0) byRecIndex[recIndex] = image;
  }

  MobiImage? cover;
  final coverIndex = _decodeKindleEmbed(coverEmbed);
  if (coverIndex != null) cover = byRecIndex[coverIndex];

  final refs = textInfo?.imageRefs ?? const <int>[];
  final validRefCount = refs.where(byRecIndex.containsKey).length;
  final useHtmlOrder =
      refs.isNotEmpty && validRefCount * 2 >= recordImages.length;
  if (!useHtmlOrder) {
    return _MobiReadingOrder(List<MobiImage>.of(recordImages), const []);
  }

  final images = <MobiImage>[];
  final coverInHtml =
      cover != null && refs.any((ref) => identical(byRecIndex[ref], cover));
  if (cover != null && !coverInHtml) images.add(cover);

  final pageByRef = List<int>.filled(refs.length, -1);
  for (var i = 0; i < refs.length; i++) {
    final image = byRecIndex[refs[i]];
    if (image == null) continue;
    pageByRef[i] = images.length;
    images.add(image);
  }

  if (images.isEmpty) {
    return _MobiReadingOrder(List<MobiImage>.of(recordImages), const []);
  }

  final toc = <TocEntry>[];
  for (final heading in textInfo!.headings) {
    var page = -1;
    for (var i = 0; i < textInfo.imagePositions.length; i++) {
      if (textInfo.imagePositions[i] < heading.position) continue;
      if (pageByRef[i] >= 0) {
        page = pageByRef[i];
        break;
      }
    }
    if (page < 0) continue;
    if (toc.isNotEmpty &&
        toc.last.page == page &&
        toc.last.title == heading.title) {
      continue;
    }
    toc.add(TocEntry(title: heading.title, page: page, level: heading.level));
  }

  return _MobiReadingOrder(images, toc);
}

Uint8List _palmDocDecompress(Uint8List input) {
  final output = <int>[];
  var i = 0;
  const maxSize = 16 * 1024 * 1024;
  while (i < input.length && output.length < maxSize) {
    final c = input[i++];
    if (c == 0) {
      output.add(0);
    } else if (c <= 8) {
      for (var j = 0; j < c && i < input.length; j++) {
        output.add(input[i++]);
      }
    } else if (c <= 0x7F) {
      output.add(c);
    } else if (c <= 0xBF) {
      if (i >= input.length) break;
      final d = input[i++];
      final distance = ((c & 0x3F) << 8) | d;
      final length = 3 + ((c >> 3) & 0x07);
      final start = output.length - distance;
      if (start < 0) continue;
      for (var j = 0; j < length; j++) {
        output.add(output[start + j]);
      }
    } else {
      output.add(0x20);
      output.add(c ^ 0x80);
    }
  }
  return Uint8List.fromList(output);
}

int? _decodeKindleEmbed(String? value) {
  if (value == null || value.isEmpty) return null;
  final match = RegExp(
    r'kindle:embed:([0-9A-Va-v]+)',
    caseSensitive: false,
  ).firstMatch(value);
  if (match == null) return null;
  var result = 0;
  for (final code in match.group(1)!.toUpperCase().codeUnits) {
    final digit = code >= 0x30 && code <= 0x39
        ? code - 0x30
        : (code >= 0x41 && code <= 0x56 ? code - 0x41 + 10 : -1);
    if (digit < 0) return null;
    result = result * 32 + digit;
  }
  return result > 0 ? result : null;
}

String _plainText(String html) {
  var text = html.replaceAll(RegExp(r'<[^>]*>'), ' ');
  text = text
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&#39;', "'");
  text = text.replaceAllMapped(RegExp(r'&#x?([0-9a-fA-F]+);'), (match) {
    final token = match.group(1)!;
    final code = match.group(0)!.toLowerCase().startsWith('&#x')
        ? int.tryParse(token, radix: 16)
        : int.tryParse(token);
    return code == null ? match.group(0)! : String.fromCharCode(code);
  });
  text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (text.length > 160) {
    text = '${text.substring(0, 160)}…';
  }
  return text;
}
