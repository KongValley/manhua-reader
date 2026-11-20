import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// File-system locations used by the app.
///
/// Everything the app owns (imported copies, covers, library.json) lives under
/// [root] so the user's original files are never modified.
class AppPaths {
  AppPaths(this.root);

  final Directory root;

  Directory get booksDir => Directory(p.join(root.path, 'books'));

  Directory get coversDir => Directory(p.join(root.path, 'covers'));

  File get libraryFile => File(p.join(root.path, 'library.json'));

  Directory get cacheDir => Directory(p.join(root.path, 'cache'));

  static Future<AppPaths> resolve() async {
    final base = await getApplicationSupportDirectory();
    return create(Directory(p.join(base.path, 'ManhuaReader')));
  }

  /// Creates (or reuses) an app directory rooted at [root].
  static Future<AppPaths> create(Directory root) async {
    final paths = AppPaths(root);
    await paths.booksDir.create(recursive: true);
    await paths.coversDir.create(recursive: true);
    await paths.cacheDir.create(recursive: true);
    return paths;
  }
}
