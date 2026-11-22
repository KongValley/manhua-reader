import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:manhua_reader/models/comic_book.dart';
import 'package:manhua_reader/screens/album_screen.dart';
import 'package:manhua_reader/screens/reader_screen.dart';
import 'package:manhua_reader/services/app_paths.dart';
import 'package:manhua_reader/services/library_repository.dart';
import 'package:manhua_reader/theme/app_theme.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late Directory albumDir;
  late LibraryRepository repository;
  late ComicBook book;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('manhua_album_screen_');
    albumDir = Directory(p.join(temp.path, 'images'));
    for (var index = 1; index <= 3; index++) {
      final file = File(p.join(albumDir.path, '$index.jpg'));
      await file.parent.create(recursive: true);
      await file.writeAsBytes(_jpeg(120, 180), flush: true);
    }
    final paths = await AppPaths.create(Directory(p.join(temp.path, 'app')));
    repository = LibraryRepository(paths);
    await repository.load();
    book = await repository.importAlbumDirectory(albumDir);
  });

  tearDown(() async {
    repository.dispose();
    try {
      if (await temp.exists()) await temp.delete(recursive: true);
    } on FileSystemException {
      // Windows may keep a decoded image handle briefly after unmount.
      // Windows 可能在组件卸载后短暂保留解码图片的句柄。
    }
  });

  testWidgets('shows the album grid and opens the tapped page', (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: AlbumScreen(book: book, repository: repository),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pump();

    expect(find.text('3 张 · 点击图片开始阅读'), findsOneWidget);
    expect(find.byType(GridView), findsOneWidget);
    expect(find.byTooltip('排序'), findsOneWidget);

    await tester.tap(find.text('2'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(ReaderScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}

Uint8List _jpeg(int width, int height) {
  final picture = image.Image(width: width, height: height);
  image.fill(picture, color: image.ColorRgb8(220, 220, 220));
  return Uint8List.fromList(image.encodeJpg(picture, quality: 85));
}
