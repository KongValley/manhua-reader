import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../../utils/natural_sort.dart';

/// A page image inside a ZIP/CBZ archive.
/// ZIP/CBZ 压缩包中的一页图片。
class ZipPage {
  const ZipPage({
    required this.path,
    required this.method,
    required this.flags,
    required this.compressedSize,
    required this.uncompressedSize,
    required this.localHeaderOffset,
  });

  final String path;
  final int method;
  final int flags;
  final int compressedSize;
  final int uncompressedSize;
  final int localHeaderOffset;

  String get name => path.split('/').last;
}

class ZipArchiveException implements Exception {
  ZipArchiveException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Random-access reader for ZIP/CBZ comic archives.
///
/// Only the central directory is loaded up front; page data is decompressed on
/// demand so a large volume never has to fit in memory.
/// ZIP/CBZ 漫画包的随机读取器。
///
/// 打开时只读取中央目录，页面数据按需解压，大文件无需整体读入内存。
class ZipArchiveReader {
  ZipArchiveReader._(this.path, this._file, this._length, this.pages);

  final String path;
  final RandomAccessFile _file;
  final int _length;
  final List<ZipPage> pages;

  final LinkedHashMap<int, Uint8List> _cache = LinkedHashMap<int, Uint8List>();
  Future<void> _tail = Future<void>.value();
  bool _disposed = false;
  int _cachedBytes = 0;

  static const int maxEntries = 5000;
  static const int maxPageBytes = 64 * 1024 * 1024;
  static const int maxProbeBytes = 128 * 1024;
  static const int _maxCentralDirectoryBytes = 32 * 1024 * 1024;
  static const int _cacheLimit = 6;
  static const int _cacheByteLimit = 48 * 1024 * 1024;
  static const int _eocdSignature = 0x06054B50;
  static const int _centralHeaderSignature = 0x02014B50;
  static const int _localHeaderSignature = 0x04034B50;
  static const int _zip64LocatorSignature = 0x07064B50;
  static const int _zip64EndSignature = 0x06064B50;
  static const Set<String> _imageExtensions = {
    'jpg',
    'jpeg',
    'png',
    'webp',
    'gif',
    'bmp',
  };

  static Future<ZipArchiveReader> open(String filePath) async {
    final file = await File(filePath).open(mode: FileMode.read);
    try {
      final length = await file.length();
      if (length < 22) {
        throw ZipArchiveException('压缩包不完整');
      }
      final directory = await _readDirectory(file, length);
      final pages = <ZipPage>[];
      for (final entry in directory.entries) {
        if (!_isImagePath(entry.path)) continue;
        if ((entry.flags & 0x1) != 0) {
          throw ZipArchiveException('暂不支持加密的 ZIP 漫画');
        }
        if (entry.method != 0 && entry.method != 8) {
          throw ZipArchiveException('不支持的 ZIP 压缩方式（${entry.method}）');
        }
        if (entry.uncompressedSize > maxPageBytes) {
          throw ZipArchiveException('压缩包内单页超过 64 MB');
        }
        pages.add(entry);
      }
      if (pages.isEmpty) {
        throw ZipArchiveException('压缩包里没有可显示的图片');
      }
      pages.sort((a, b) => naturalCompare(a.path, b.path));
      return ZipArchiveReader._(filePath, file, length, pages);
    } catch (_) {
      await file.close();
      rethrow;
    }
  }

  /// Reads one page and keeps a few recently used pages in memory.
  /// 读取一页，并在内存中保留少量最近使用的页面。
  Future<Uint8List> readPageBytes(int index) {
    if (index < 0 || index >= pages.length) {
      throw RangeError.index(index, pages, 'index');
    }
    final cached = _cache.remove(index);
    if (cached != null) {
      _cache[index] = cached;
      return Future<Uint8List>.value(cached);
    }
    return _exclusive(() async {
      _ensureOpen();
      final page = pages[index];
      final dataOffset = await _dataOffset(page);
      final compressed = await _read(_file, dataOffset, page.compressedSize);
      final bytes = _decompress(page, compressed);
      _cache[index] = bytes;
      _cachedBytes += bytes.length;
      while ((_cache.length > _cacheLimit || _cachedBytes > _cacheByteLimit) &&
          _cache.isNotEmpty) {
        final evicted = _cache.remove(_cache.keys.first)!;
        _cachedBytes -= evicted.length;
      }
      return bytes;
    });
  }

  /// Returns the beginning of a page so image headers can be inspected without
  /// decompressing the whole picture.
  /// 返回页面开头，用于在不完整解压图片的情况下读取图片头。
  Future<Uint8List> readPagePrefix(int index, {int maxBytes = maxProbeBytes}) {
    if (index < 0 || index >= pages.length) {
      throw RangeError.index(index, pages, 'index');
    }
    return _exclusive(() async {
      _ensureOpen();
      final page = pages[index];
      final dataOffset = await _dataOffset(page);
      if (page.method == 0) {
        final available = math.min(_length - dataOffset, page.compressedSize);
        return _read(_file, dataOffset, math.min(available, maxBytes));
      }
      final output = _PrefixSink(maxBytes);
      final sink = ZLibDecoder(raw: true).startChunkedConversion(output);
      var offset = dataOffset;
      var remaining = page.compressedSize;
      var fed = 0;
      try {
        while (remaining > 0 && !output.isFull && fed < maxBytes * 8) {
          final length = math.min(16 * 1024, remaining);
          final chunk = await _read(_file, offset, length);
          sink.add(chunk);
          offset += length;
          remaining -= length;
          fed += length;
        }
      } catch (_) {
        // The stream is intentionally cut short after enough pixels were read.
        // 读到足够数据后会主动停止，忽略不完整流的尾部错误。
      } finally {
        try {
          sink.close();
        } catch (_) {}
      }
      return output.takeBytes();
    });
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _tail;
    await _file.close();
    _cache.clear();
    _cachedBytes = 0;
  }

  void _ensureOpen() {
    if (_disposed) throw ZipArchiveException('压缩包已关闭');
  }

  Future<T> _exclusive<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<int> _dataOffset(ZipPage page) async {
    final header = await _read(_file, page.localHeaderOffset, 30);
    if (_u32le(header, 0) != _localHeaderSignature) {
      throw ZipArchiveException('页面索引损坏');
    }
    final nameLength = _u16le(header, 26);
    final extraLength = _u16le(header, 28);
    final offset = page.localHeaderOffset + 30 + nameLength + extraLength;
    if (offset < 0 ||
        page.compressedSize < 0 ||
        offset + page.compressedSize > _length) {
      throw ZipArchiveException('压缩包数据不完整');
    }
    return offset;
  }

  static Uint8List _decompress(ZipPage page, Uint8List compressed) {
    if (page.method == 0) {
      if (compressed.length > maxPageBytes) {
        throw ZipArchiveException('压缩包内单页超过 64 MB');
      }
      return compressed;
    }
    try {
      final bytes = ZLibDecoder(raw: true).convert(compressed);
      if (bytes.length > maxPageBytes) {
        throw ZipArchiveException('压缩包内单页超过 64 MB');
      }
      return bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    } on ZipArchiveException {
      rethrow;
    } catch (_) {
      throw ZipArchiveException('页面解压失败，压缩包可能已损坏');
    }
  }

  static Future<Uint8List> _read(
    RandomAccessFile file,
    int offset,
    int length,
  ) async {
    if (offset < 0 || length < 0) {
      throw ZipArchiveException('压缩包索引损坏');
    }
    await file.setPosition(offset);
    final data = await file.read(length);
    if (data.length != length) {
      throw ZipArchiveException('压缩包数据不完整');
    }
    return data;
  }

  static Future<_ZipDirectory> _readDirectory(
    RandomAccessFile file,
    int length,
  ) async {
    final tailLength = math.min(length, 22 + 65535);
    final tail = await _read(file, length - tailLength, tailLength);
    int? eocd;
    for (var index = tail.length - 22; index >= 0; index--) {
      if (_u32le(tail, index) != _eocdSignature) continue;
      final commentLength = _u16le(tail, index + 20);
      if (index + 22 + commentLength <= tail.length) {
        eocd = index;
        break;
      }
    }
    if (eocd == null) {
      throw ZipArchiveException('不是有效的 ZIP / CBZ 文件');
    }

    final diskNumber = _u16le(tail, eocd + 4);
    final directoryDisk = _u16le(tail, eocd + 6);
    final entriesOnDisk = _u16le(tail, eocd + 8);
    var totalEntries = _u16le(tail, eocd + 10);
    var directorySize = _u32le(tail, eocd + 12);
    var directoryOffset = _u32le(tail, eocd + 16);
    if (diskNumber != 0 ||
        directoryDisk != 0 ||
        entriesOnDisk != totalEntries) {
      throw ZipArchiveException('暂不支持分卷 ZIP');
    }

    if (totalEntries == 0xFFFF ||
        directorySize == 0xFFFFFFFF ||
        directoryOffset == 0xFFFFFFFF) {
      final locatorOffset = length - tailLength + eocd - 20;
      if (locatorOffset < 0) throw ZipArchiveException('ZIP64 索引不完整');
      final locator = await _read(file, locatorOffset, 20);
      if (_u32le(locator, 0) != _zip64LocatorSignature) {
        throw ZipArchiveException('ZIP64 索引不完整');
      }
      final zip64Offset = _u64le(locator, 8);
      if (zip64Offset < 0 || zip64Offset + 56 > length) {
        throw ZipArchiveException('ZIP64 索引不完整');
      }
      final zip64 = await _read(file, zip64Offset, 56);
      if (_u32le(zip64, 0) != _zip64EndSignature) {
        throw ZipArchiveException('ZIP64 索引不完整');
      }
      totalEntries = _u64le(zip64, 32);
      directorySize = _u64le(zip64, 40);
      directoryOffset = _u64le(zip64, 48);
    }

    if (totalEntries > maxEntries) {
      throw ZipArchiveException('压缩包内文件过多');
    }
    if (directorySize < 0 ||
        directorySize > _maxCentralDirectoryBytes ||
        directoryOffset < 0 ||
        directoryOffset + directorySize > length) {
      throw ZipArchiveException('ZIP 中央目录超出文件范围');
    }
    if (totalEntries == 0) return const _ZipDirectory([]);

    final directory = await _read(file, directoryOffset, directorySize);
    final entries = <ZipPage>[];
    var cursor = 0;
    for (var index = 0; index < totalEntries; index++) {
      if (cursor + 46 > directory.length ||
          _u32le(directory, cursor) != _centralHeaderSignature) {
        throw ZipArchiveException('ZIP 中央目录损坏');
      }
      final flags = _u16le(directory, cursor + 8);
      final method = _u16le(directory, cursor + 10);
      var compressedSize = _u32le(directory, cursor + 20);
      var uncompressedSize = _u32le(directory, cursor + 24);
      final nameLength = _u16le(directory, cursor + 28);
      final extraLength = _u16le(directory, cursor + 30);
      final commentLength = _u16le(directory, cursor + 32);
      var localOffset = _u32le(directory, cursor + 42);
      final nameStart = cursor + 46;
      final extraStart = nameStart + nameLength;
      final next = extraStart + extraLength + commentLength;
      if (next > directory.length) {
        throw ZipArchiveException('ZIP 中央目录损坏');
      }

      if (uncompressedSize == 0xFFFFFFFF ||
          compressedSize == 0xFFFFFFFF ||
          localOffset == 0xFFFFFFFF) {
        final extraEnd = extraStart + extraLength;
        var extraCursor = extraStart;
        while (extraCursor + 4 <= extraEnd) {
          final id = _u16le(directory, extraCursor);
          final size = _u16le(directory, extraCursor + 2);
          var valueCursor = extraCursor + 4;
          if (id == 0x0001) {
            if (uncompressedSize == 0xFFFFFFFF &&
                valueCursor + 8 <= extraCursor + 4 + size) {
              uncompressedSize = _u64le(directory, valueCursor);
              valueCursor += 8;
            }
            if (compressedSize == 0xFFFFFFFF &&
                valueCursor + 8 <= extraCursor + 4 + size) {
              compressedSize = _u64le(directory, valueCursor);
              valueCursor += 8;
            }
            if (localOffset == 0xFFFFFFFF &&
                valueCursor + 8 <= extraCursor + 4 + size) {
              localOffset = _u64le(directory, valueCursor);
            }
            break;
          }
          extraCursor += 4 + size;
        }
      }

      final nameBytes = directory.sublist(nameStart, extraStart);
      final normalized = _decodeName(nameBytes, flags).replaceAll('\\', '/');
      if (!normalized.endsWith('/') &&
          compressedSize >= 0 &&
          uncompressedSize >= 0 &&
          localOffset >= 0 &&
          localOffset < length) {
        entries.add(
          ZipPage(
            path: normalized,
            method: method,
            flags: flags,
            compressedSize: compressedSize,
            uncompressedSize: uncompressedSize,
            localHeaderOffset: localOffset,
          ),
        );
      }
      cursor = next;
    }
    return _ZipDirectory(entries);
  }

  static String _decodeName(Uint8List bytes, int flags) {
    if ((flags & 0x800) != 0) {
      return utf8.decode(bytes, allowMalformed: true);
    }
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return latin1.decode(bytes);
    }
  }

  static bool _isImagePath(String path) {
    if (path.endsWith('/')) return false;
    final segments = path.split('/');
    for (final segment in segments) {
      if (segment.isEmpty || segment.startsWith('.')) return false;
      if (segment.toLowerCase() == '__macosx') return false;
      if (segment.startsWith('._')) return false;
    }
    final name = segments.last.toLowerCase();
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return false;
    return _imageExtensions.contains(name.substring(dot + 1));
  }
}

class _ZipDirectory {
  const _ZipDirectory(this.entries);

  final List<ZipPage> entries;
}

class _PrefixSink implements Sink<List<int>> {
  _PrefixSink(this.limit);

  final int limit;
  final BytesBuilder _builder = BytesBuilder(copy: false);
  int _length = 0;

  bool get isFull => _length >= limit;

  @override
  void add(List<int> data) {
    if (_length >= limit) return;
    final take = math.min(data.length, limit - _length);
    _builder.add(data.sublist(0, take));
    _length += take;
  }

  @override
  void close() {}

  Uint8List takeBytes() => _builder.takeBytes();
}

int _u16le(Uint8List bytes, int offset) =>
    bytes[offset] | (bytes[offset + 1] << 8);

int _u32le(Uint8List bytes, int offset) =>
    bytes[offset] |
    (bytes[offset + 1] << 8) |
    (bytes[offset + 2] << 16) |
    (bytes[offset + 3] << 24);

int _u64le(Uint8List bytes, int offset) =>
    _u32le(bytes, offset) | (_u32le(bytes, offset + 4) << 32);
