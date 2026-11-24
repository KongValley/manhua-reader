import 'package:flutter/material.dart';

import '../models/comic_book.dart';
import '../screens/album_screen.dart';
import '../screens/reader_screen.dart';
import '../services/external_open_channel.dart';
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
  final route = book.format == ComicFormat.album && page == null
      ? MaterialPageRoute<void>(
          builder: (context) => AlbumScreen(book: book, repository: repository),
        )
      : _readerRoute(book: book, repository: repository, page: page);
  return Navigator.of(context).push(route).whenComplete(() {
    // Refresh listeners after the reader route finishes disposing its timer.
    // 阅读器关闭并结算最后阅读时长后，通知书架刷新今日统计。
    Future<void>.microtask(repository.notifyReadingSessionEnded);
  });
}

MaterialPageRoute<void> _readerRoute({
  required ComicBook book,
  required LibraryRepository repository,
  int? page,
}) => MaterialPageRoute<void>(
  settings: const RouteSettings(name: readerRouteName),
  builder: (context) => ReaderScreen(
    book: book,
    repository: repository,
    initialPage: page,
  ),
);
