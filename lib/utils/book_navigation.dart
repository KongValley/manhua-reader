import 'package:flutter/material.dart';

import '../models/comic_book.dart';
import '../screens/album_screen.dart';
import '../screens/reader_screen.dart';
import '../services/library_repository.dart';

/// Opens an album's thumbnail wall or a regular comic reader.
///
/// Passing [page] always opens the reader directly, which is used by the
/// continue-reading card.
/// 打开相册缩略图墙或普通阅读器。
///
/// 传入 [page] 时总是直接进入阅读器，供“继续阅读”卡片使用。
Future<void> openComicBook(
  BuildContext context, {
  required ComicBook book,
  required LibraryRepository repository,
  int? page,
}) {
  final Widget screen;
  if (book.format == ComicFormat.album && page == null) {
    screen = AlbumScreen(book: book, repository: repository);
  } else {
    screen = ReaderScreen(
      book: book,
      repository: repository,
      initialPage: page,
    );
  }
  return Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (context) => screen));
}
