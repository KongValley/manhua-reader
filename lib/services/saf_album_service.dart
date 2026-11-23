import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// One image document discovered below an Android SAF tree URI.
/// 在 Android SAF 目录树中发现的一张图片文档。
class SafAlbumImage {
  const SafAlbumImage({
    required this.uri,
    required this.relativePath,
    required this.name,
    this.size,
    this.width,
    this.height,
    this.lastModified,
  });

  final String uri;
  final String relativePath;
  final String name;
  final int? size;
  final int? width;
  final int? height;

  /// Last modification time in milliseconds since epoch.
  /// 最后修改时间，Unix 毫秒。
  final int? lastModified;
}

/// Bridges referenced image folders to Android's Storage Access Framework.
/// 将引用的图片文件夹桥接到 Android Storage Access Framework。
class SafAlbumService {
  static const MethodChannel _channel = MethodChannel('manhua/saf');

  static const int maxDocumentBytes = 64 * 1024 * 1024;

  static bool get isSupported => !kIsWeb && Platform.isAndroid;

  static Future<List<SafAlbumImage>> listImages(String treeUri) async {
    final raw = await _channel.invokeListMethod<Object?>('listImages', {
      'uri': treeUri,
    });
    final images = <SafAlbumImage>[];
    for (final item in raw ?? const <Object?>[]) {
      if (item is! Map) continue;
      final uri = item['uri'] as String?;
      final relativePath = item['relativePath'] as String?;
      final name = item['name'] as String?;
      if (uri == null || relativePath == null || name == null) continue;
      final size = item['size'];
      final width = item['width'];
      final height = item['height'];
      final lastModified = item['lastModified'];
      images.add(
        SafAlbumImage(
          uri: uri,
          relativePath: relativePath,
          name: name,
          size: size is num ? size.toInt() : null,
          width: width is num ? width.toInt() : null,
          height: height is num ? height.toInt() : null,
          lastModified: lastModified is num ? lastModified.toInt() : null,
        ),
      );
    }
    return images;
  }

  static Future<Uint8List> readDocument(
    String uri, {
    int maxBytes = maxDocumentBytes,
  }) async {
    final bytes = await _channel.invokeMethod<Uint8List>('readDocument', {
      'uri': uri,
      'maxBytes': maxBytes,
    });
    if (bytes == null) {
      throw StateError('无法读取图片');
    }
    return bytes;
  }

  static Future<Uint8List> readDocumentPrefix(
    String uri, {
    int maxBytes = 128 * 1024,
  }) async {
    final bytes = await _channel.invokeMethod<Uint8List>('readDocumentPrefix', {
      'uri': uri,
      'maxBytes': maxBytes,
    });
    if (bytes == null) {
      throw StateError('无法读取图片头部');
    }
    return bytes;
  }

  static Future<void> releaseTree(String uri) async {
    if (!isSupported || !uri.startsWith('content://')) return;
    try {
      await _channel.invokeMethod<void>('releaseTree', {'uri': uri});
    } catch (_) {
      // Permission cleanup is best effort.
      // 权限清理失败不影响书架操作。
    }
  }
}
