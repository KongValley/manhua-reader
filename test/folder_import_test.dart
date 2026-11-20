import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:manhua_reader/services/folder_import.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('manhua_folder_test_');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('scans nested folders for supported files', () async {
    final nested = Directory(p.join(temp.path, 'nested'));
    await nested.create(recursive: true);
    await File(p.join(temp.path, 'a.pdf')).writeAsBytes([1]);
    await File(p.join(temp.path, 'b.MOBI')).writeAsBytes([1]);
    await File(p.join(temp.path, 'ignore.txt')).writeAsBytes([1]);
    await File(p.join(nested.path, 'c.pdf')).writeAsBytes([1]);

    final files = await FolderImportScanner.scanFolder(temp);
    expect(files.map((file) => p.basename(file.path)).toList(), [
      'a.pdf',
      'b.MOBI',
      'c.pdf',
    ]);
  });

  test('expands dropped files and folders without duplicates', () async {
    final nested = Directory(p.join(temp.path, 'nested'));
    await nested.create(recursive: true);
    final first = File(p.join(temp.path, 'a.pdf'));
    await first.writeAsBytes([1]);
    final second = File(p.join(nested.path, 'b.mobi'));
    await second.writeAsBytes([1]);

    final files = await FolderImportScanner.expandPaths([
      temp.path,
      first.path,
      second.path,
    ]);
    expect(files, hasLength(2));
    expect(files.map((file) => p.basename(file.path)).toSet(), {
      'a.pdf',
      'b.mobi',
    });
  });
}
