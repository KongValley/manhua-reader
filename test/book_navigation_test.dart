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
import 'package:manhua_reader/utils/book_navigation.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late LibraryRepository repository;
  late ComicBook album;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('manhua_book_nav_');
    final albumDir = Directory(p.join(temp.path, 'album'));
    await albumDir.create(recursive: true);
    await File(p.join(albumDir.path, '1.jpg')).writeAsBytes(_jpeg());
    final paths = await AppPaths.create(Directory(p.join(temp.path, 'app')));
    repository = LibraryRepository(paths);
    await repository.load();
    album = await repository.importAlbumDirectory(albumDir);
  });

  tearDown(() async {
    repository.dispose();
    try {
      if (await temp.exists()) await temp.delete(recursive: true);
    } on FileSystemException {
      // Ignore a brief Windows image handle.
      // 忽略 Windows 短暂的图片句柄占用。
    }
  });

  testWidgets('albums open the grid, regular books open the reader', (
    tester,
  ) async {
    late BuildContext pageContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            pageContext = context;
            return const Scaffold(body: SizedBox());
          },
        ),
      ),
    );

    openComicBook(pageContext, book: album, repository: repository);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(AlbumScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));

    final pdf = ComicBook(
      id: 'pdf',
      title: 'PDF',
      originalName: 'missing.pdf',
      filePath: p.join(temp.path, 'missing.pdf'),
      format: ComicFormat.pdf,
      pageCount: 10,
      fileSize: 1,
      addedAt: DateTime(2026, 1, 1),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            pageContext = context;
            return const Scaffold(body: SizedBox());
          },
        ),
      ),
    );
    openComicBook(pageContext, book: pdf, repository: repository);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(ReaderScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}

Uint8List _jpeg() {
  final picture = image.Image(width: 120, height: 180);
  image.fill(picture, color: image.ColorRgb8(220, 220, 220));
  return Uint8List.fromList(image.encodeJpg(picture, quality: 85));
}
