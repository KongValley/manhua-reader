import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../models/comic_book.dart';
import '../../services/saf_album_service.dart';
import '../../utils/natural_sort.dart';

/// One image page inside an album folder.
/// 相册文件夹中的一页图片。
class AlbumImage {
  const AlbumImage({
    required this.relativePath,
    required this.name,
    required this.size,
    required this.width,
    required this.height,
    this.created,
    this.modified,
    this.filePath,
    this.uri,
  });

  final String relativePath;
  final String name;
  final int size;
  final int width;
  final int height;
  final DateTime? created;
  final DateTime? modified;
  final String? filePath;
  final String? uri;
}

class AlbumSourceException implements Exception {
  AlbumSourceException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Lists and reads the images of a referenced album folder.
/// 列出并读取引用型相册文件夹中的图片。
abstract class AlbumStore {
  Future<List<AlbumImage>> list({
    AlbumSortField sort = AlbumSortField.name,
    bool descending = false,
  });

  Future<Uint8List> readBytes(AlbumImage image);

  /// Reads only the image header used to discover its dimensions.
  /// 仅读取用于识别图片尺寸的头部字节。
  Future<Uint8List> readPrefix(AlbumImage image);

  Future<void> dispose();
}

/// Sorts album pages by name, creation time or modification time.
/// 按名称、创建时间或修改时间排列相册页面。
List<AlbumImage> sortAlbumImages(
  List<AlbumImage> images,
  AlbumSortField sort,
  bool descending,
) {
  int compare(AlbumImage a, AlbumImage b) {
    var result = 0;
    if (sort == AlbumSortField.name) {
      result = naturalCompare(a.relativePath, b.relativePath);
    } else {
      final aTime = sort == AlbumSortField.created
          ? (a.created ?? a.modified)
          : a.modified;
      final bTime = sort == AlbumSortField.created
          ? (b.created ?? b.modified)
          : b.modified;
      if (aTime == null && bTime == null) {
        result = 0;
      } else if (aTime == null) {
        return 1;
      } else if (bTime == null) {
        return -1;
      } else {
        result = aTime.compareTo(bTime);
      }
    }
    if (result == 0) result = naturalCompare(a.relativePath, b.relativePath);
    return descending ? -result : result;
  }

  return images..sort(compare);
}

const int albumMaxImages = 2000;
const int albumMaxPageBytes = 64 * 1024 * 1024;
const int _albumMaxDepth = 24;
const int _albumHeaderBytes = 128 * 1024;
const int _albumMetadataConcurrency = 6;

const Set<String> albumImageExtensions = {
  'jpg',
  'jpeg',
  'png',
  'webp',
  'gif',
  'bmp',
};

bool isAlbumImagePath(String path) {
  if (path.endsWith('/')) return false;
  final segments = path.split('/');
  if (segments.length > _albumMaxDepth) return false;
  for (final segment in segments) {
    if (segment.isEmpty || segment.startsWith('.')) return false;
    if (segment.toLowerCase() == '__macosx') return false;
  }
  final name = segments.last.toLowerCase();
  final dot = name.lastIndexOf('.');
  if (dot <= 0 || dot == name.length - 1) return false;
  return albumImageExtensions.contains(name.substring(dot + 1));
}

/// Reads an ordinary folder from the local file system.
/// 读取本地文件系统中的普通文件夹。
class FileAlbumStore implements AlbumStore {
  FileAlbumStore(this.directoryPath);

  final String directoryPath;

  @override
  Future<List<AlbumImage>> list({
    AlbumSortField sort = AlbumSortField.name,
    bool descending = false,
  }) async {
    final root = Directory(directoryPath);
    if (!await root.exists()) {
      throw AlbumSourceException('相册文件夹不可用，请重新选择');
    }
    final entries = <({String relativePath, File file})>[];
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final relativePath = p
          .relative(entity.path, from: root.path)
          .replaceAll('\\', '/');
      if (!isAlbumImagePath(relativePath)) continue;
      if (entries.length >= albumMaxImages) {
        throw AlbumSourceException('相册图片超过 $albumMaxImages 张');
      }
      entries.add((relativePath: relativePath, file: entity));
    }
    if (entries.isEmpty) {
      throw AlbumSourceException('相册文件夹里没有可显示的图片');
    }
    final images = await _describe(entries);
    return sortAlbumImages(images, sort, descending);
  }

  @override
  Future<Uint8List> readBytes(AlbumImage image) async {
    final path = image.filePath;
    if (path == null) throw AlbumSourceException('图片路径无效');
    final file = File(path);
    if (!await file.exists()) {
      throw AlbumSourceException('图片已丢失：${image.name}');
    }
    final length = await file.length();
    if (length > albumMaxPageBytes) {
      throw AlbumSourceException('图片超过 64 MB：${image.name}');
    }
    return file.readAsBytes();
  }

  @override
  Future<Uint8List> readPrefix(AlbumImage image) async {
    final path = image.filePath;
    if (path == null) throw AlbumSourceException('图片路径无效');
    return _readPrefixFile(File(path));
  }

  @override
  Future<void> dispose() async {}

  Future<List<AlbumImage>> _describe(
    List<({String relativePath, File file})> entries,
  ) async {
    final images = List<AlbumImage?>.filled(entries.length, null);
    var cursor = 0;

    Future<void> worker() async {
      while (true) {
        final index = cursor++;
        if (index >= entries.length) return;
        final entry = entries[index];
        final stat = await entry.file.stat();
        if (stat.size > albumMaxPageBytes) {
          throw AlbumSourceException('相册中有超过 64 MB 的图片');
        }
        images[index] = AlbumImage(
          relativePath: entry.relativePath,
          name: p.posix.basename(entry.relativePath),
          size: stat.size,
          width: 0,
          height: 0,
          created: stat.changed,
          modified: stat.modified,
          filePath: entry.file.path,
        );
      }
    }

    await Future.wait([
      for (
        var index = 0;
        index < math.min(_albumMetadataConcurrency, entries.length);
        index++
      )
        worker(),
    ]);
    return images.cast<AlbumImage>();
  }

  Future<Uint8List> _readPrefixFile(File file) async {
    RandomAccessFile? handle;
    try {
      handle = await file.open();
      final length = await handle.length();
      final readLength = length < _albumHeaderBytes
          ? length
          : _albumHeaderBytes;
      await handle.setPosition(0);
      return await handle.read(readLength);
    } finally {
      await handle?.close();
    }
  }
}

/// Reads a folder through Android's Storage Access Framework.
/// 通过 Android Storage Access Framework 读取文件夹。
class SafAlbumStore implements AlbumStore {
  SafAlbumStore(this.treeUri);

  final String treeUri;

  @override
  Future<List<AlbumImage>> list({
    AlbumSortField sort = AlbumSortField.name,
    bool descending = false,
  }) async {
    final documents = await SafAlbumService.listImages(treeUri);
    final images = [
      for (final document in documents)
        AlbumImage(
          relativePath: document.relativePath,
          name: document.name,
          size: document.size ?? 0,
          width: document.width ?? 0,
          height: document.height ?? 0,
          created: document.lastModified == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(document.lastModified!),
          modified: document.lastModified == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(document.lastModified!),
          uri: document.uri,
        ),
    ];
    if (images.isEmpty) {
      throw AlbumSourceException('相册文件夹里没有可显示的图片');
    }
    return sortAlbumImages(images, sort, descending);
  }

  @override
  Future<Uint8List> readBytes(AlbumImage image) async {
    final uri = image.uri;
    if (uri == null) throw AlbumSourceException('图片路径无效');
    try {
      return await SafAlbumService.readDocument(uri);
    } catch (error) {
      throw AlbumSourceException('无法读取图片 ${image.name}：$error');
    }
  }

  @override
  Future<Uint8List> readPrefix(AlbumImage image) async {
    final bytes = await readBytes(image);
    return bytes.length <= _albumHeaderBytes
        ? bytes
        : Uint8List.sublistView(bytes, 0, _albumHeaderBytes);
  }

  @override
  Future<void> dispose() async {}
}

AlbumStore createAlbumStore(String source) => source.startsWith('content://')
    ? SafAlbumStore(source)
    : FileAlbumStore(source);
