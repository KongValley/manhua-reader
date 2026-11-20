import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// One PDF/MOBI document discovered through Android's Storage Access
/// Framework.
/// 通过 Android Storage Access Framework 发现的一个 PDF/MOBI 文档。
class SafFile {
  const SafFile({required this.uri, required this.name, this.size});

  final String uri;
  final String name;
  final int? size;
}

/// Bridges Android SAF folder selection / recursive listing / copying to the
/// native side. On other platforms use [FolderImportScanner] with a local path.
/// 将 Android SAF 的文件夹选择 / 递归列表 / 复制桥接到原生侧。
/// 其他平台请使用 [FolderImportScanner] 处理本地路径。
class SafFolderService {
  static const MethodChannel _channel = MethodChannel('manhua/saf');

  static bool get isSupported => !kIsWeb && Platform.isAndroid;

  static Future<String?> pickDirectory() {
    return _channel.invokeMethod<String>('pickDirectory');
  }

  static Future<String> directoryName(String uri) async {
    try {
      final name = await _channel.invokeMethod<String>('directoryName', {
        'uri': uri,
      });
      if (name != null && name.trim().isNotEmpty) return name.trim();
    } catch (_) {}
    return '导入的文件夹';
  }

  static Future<List<SafFile>> listBooks(String directoryUri) async {
    final raw = await _channel.invokeListMethod<Object?>('listBooks', {
      'uri': directoryUri,
    });
    final files = <SafFile>[];
    for (final item in raw ?? const <Object?>[]) {
      if (item is! Map) continue;
      final uri = item['uri'] as String?;
      final name = item['name'] as String?;
      if (uri == null || name == null) continue;
      final size = item['size'];
      files.add(
        SafFile(uri: uri, name: name, size: size is num ? size.toInt() : null),
      );
    }
    files.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return files;
  }

  static Future<String?> copyToCache(SafFile file) {
    return _channel.invokeMethod<String>('copyToCache', {
      'uri': file.uri,
      'name': file.name,
    });
  }
}
