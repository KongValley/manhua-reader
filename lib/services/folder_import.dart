import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/comic_book.dart';

/// Scans folders / dropped paths for importable PDF and MOBI files.
/// 扫描文件夹 / 拖拽路径中的可导入 PDF 与 MOBI 文件。
class FolderImportScanner {
  static const int defaultMaxFiles = 1000;

  static bool isImportableName(String name) {
    final extension = p.extension(name);
    return ComicFormat.fromExtension(extension) != null;
  }

  static Future<List<File>> scanFolder(
    Directory root, {
    int maxFiles = defaultMaxFiles,
  }) async {
    final files = <File>[];
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      if (!isImportableName(entity.path)) continue;
      files.add(entity);
      if (files.length >= maxFiles) break;
    }
    files.sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));
    return files;
  }

  /// Expands dropped files and directories into a de-duplicated file list.
  /// 将拖入的文件与目录展开为去重后的文件列表。
  static Future<List<File>> expandPaths(
    Iterable<String> paths, {
    int maxFiles = defaultMaxFiles,
  }) async {
    final files = <File>[];
    final seen = <String>{};
    for (final path in paths) {
      if (files.length >= maxFiles) break;
      final type = FileSystemEntity.typeSync(path, followLinks: false);
      if (type == FileSystemEntityType.directory) {
        final scanned = await scanFolder(
          Directory(path),
          maxFiles: maxFiles - files.length,
        );
        for (final file in scanned) {
          final key = _pathKey(file.path);
          if (seen.add(key)) files.add(file);
          if (files.length >= maxFiles) break;
        }
      } else if (type == FileSystemEntityType.file && isImportableName(path)) {
        final file = File(path);
        if (seen.add(_pathKey(file.path))) files.add(file);
      }
    }
    files.sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));
    return files;
  }

  static String _pathKey(String path) {
    final normalized = p.normalize(p.absolute(path));
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }
}
