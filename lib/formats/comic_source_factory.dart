import 'dart:io';

import 'package:pdfrx/pdfrx.dart';

import '../models/comic_book.dart';
import 'album/album_store.dart';
import 'album_comic_source.dart';
import 'archive_comic_source.dart';
import 'comic_source.dart';
import 'mobi/mobi_book.dart';
import 'mobi_comic_source.dart';
import 'pdf_comic_source.dart';
import 'zip/zip_archive_reader.dart';

class ComicSourceFactory {
  static Future<ComicSource> open(
    ComicBook book, {
    PdfPasswordProvider? passwordProvider,
    AlbumSortField? albumSort,
    bool? albumSortDescending,
  }) async {
    if (book.format == ComicFormat.album) {
      try {
        return await AlbumComicSource.open(
          book.filePath,
          sort: albumSort ?? book.albumSort,
          descending: albumSortDescending ?? book.albumSortDescending,
        );
      } on AlbumSourceException catch (error) {
        throw ComicOpenException(error.message);
      }
    }
    if (!await File(book.filePath).exists()) {
      throw ComicOpenException('漫画文件已丢失，请重新导入');
    }
    try {
      switch (book.format) {
        case ComicFormat.pdf:
          final document = await PdfDocument.openFile(
            book.filePath,
            passwordProvider: passwordProvider,
          );
          if (document.pages.isEmpty) {
            await document.dispose();
            throw ComicOpenException('PDF 没有可显示的页面');
          }
          return PdfComicSource(document);
        case ComicFormat.mobi:
          final mobi = await MobiBook.open(
            book.filePath,
            fallbackTitle: book.title,
          );
          return MobiComicSource(mobi);
        case ComicFormat.cbz:
          return await ArchiveComicSource.open(book.filePath);
        case ComicFormat.album:
          return await AlbumComicSource.open(
            book.filePath,
            sort: albumSort ?? book.albumSort,
            descending: albumSortDescending ?? book.albumSortDescending,
          );
      }
    } on ComicOpenException {
      rethrow;
    } on AlbumSourceException catch (error) {
      throw ComicOpenException(error.message);
    } on ZipArchiveException catch (error) {
      throw ComicOpenException(error.message);
    } on MobiException catch (error) {
      throw ComicOpenException(error.message);
    } on PdfPasswordException catch (error) {
      final message = error.message.toLowerCase();
      if (message.contains('no password')) {
        throw ComicOpenException(
          passwordProvider == null ? 'PDF 已加密，需要输入密码' : '已取消输入密码',
        );
      }
      throw ComicOpenException('PDF 密码不正确或已取消输入');
    } catch (error) {
      final message = error.toString().toLowerCase();
      if (message.contains('password')) {
        throw ComicOpenException('PDF 密码不正确或已取消输入');
      }
      throw ComicOpenException('无法打开这本漫画：$error');
    }
  }
}
