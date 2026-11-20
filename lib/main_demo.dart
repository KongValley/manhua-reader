import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import 'app.dart';
import 'models/comic_book.dart';
import 'models/reader_settings.dart';
import 'screens/library_screen.dart';
import 'screens/reader_screen.dart';
import 'services/app_paths.dart';
import 'services/library_repository.dart';
import 'services/pdf_password_cache.dart';

/// Debug/demo entry point used for local verification and screenshots.
///
/// Usage (Windows):
///   flutter build windows --debug -t lib/main_demo.dart
///   manhua_reader.exe --open=pdf --mode=horizontal
Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await pdfrxFlutterInitialize();

  final paths = await AppPaths.resolve();
  final repository = LibraryRepository(paths);
  await repository.load();

  final mode = _arg(args, 'mode');
  if (mode == 'vertical') {
    repository.setReadingMode(ReadingMode.vertical);
  } else if (mode == 'horizontal') {
    repository.setReadingMode(ReadingMode.horizontal);
  }
  if (args.contains('--rtl')) repository.setRightToLeft(true);
  if (args.contains('--ltr')) repository.setRightToLeft(false);
  if (args.contains('--double')) repository.setDoublePage(true);
  if (args.contains('--single')) repository.setDoublePage(false);
  await repository.flush();

  for (final extension in ['pdf', 'mobi']) {
    final name = 'VOL.001.$extension';
    final sample = File('test/$name');
    if (!sample.existsSync()) continue;
    if (repository.books.any((book) => book.originalName == name)) continue;
    try {
      debugPrint('demo: importing ${sample.path}');
      await repository.importFile(sample.path);
      debugPrint('demo: imported $name');
    } catch (error) {
      debugPrint('demo: import failed for $name: $error');
    }
  }

  if (args.contains('--encrypted')) {
    final sample = File('test/encrypted_sample.pdf');
    if (sample.existsSync() &&
        !repository.books.any(
          (book) => book.originalName == 'encrypted_sample.pdf',
        )) {
      try {
        debugPrint('demo: importing encrypted sample');
        await repository.importFile(
          sample.path,
          // This fixture is only used for password-flow verification.
          pdfPasswordProvider: () async => 'manhua123',
        );
        debugPrint('demo: imported encrypted sample');
      } catch (error) {
        debugPrint('demo: import failed for encrypted sample: $error');
      }
    }
  }

  Widget? home;
  final open = _arg(args, 'open');
  if (open != null) {
    final format = ComicFormat.fromExtension(open);
    if (format != null) {
      final pageArg = int.tryParse(_arg(args, 'page') ?? '');
      final bookmarkPages = _arg(args, 'bookmarks');
      for (final book in repository.books) {
        if (book.format == format) {
          if (args.contains('--cached-password') &&
              book.originalName == 'encrypted_sample.pdf') {
            PdfPasswordCache.put(book.filePath, 'manhua123');
          }
          if (pageArg != null && pageArg >= 0 && pageArg < book.pageCount) {
            book.lastPage = pageArg;
          }
          if (bookmarkPages != null) {
            book.bookmarks.clear();
            for (final token in bookmarkPages.split(',')) {
              final page = int.tryParse(token.trim());
              if (page != null && page >= 0 && page < book.pageCount) {
                repository.toggleBookmark(book, page);
              }
            }
            await repository.flush();
          }
          if (args.contains('--named-bookmarks')) {
            book.bookmarks.clear();
            const samples = <({int page, String label, String note})>[
              (page: 1, label: '封面与扉页', note: '单行本封面与版权页'),
              (page: 10, label: '第一章高潮', note: '警察与暴走族的追逐场面'),
              (page: 50, label: '名场面', note: '这里的分镜很精彩'),
            ];
            for (final sample in samples) {
              if (sample.page < book.pageCount) {
                repository.setBookmark(
                  book,
                  sample.page,
                  label: sample.label,
                  note: sample.note,
                );
              }
            }
            await repository.flush();
          }
          home = _DemoReaderLauncher(book: book, repository: repository);
          break;
        }
      }
    }
  }

  runApp(ManhuaApp(repository: repository, home: home));
}

/// Pushes the reader onto the library route, mirroring the real navigation
/// stack so that the back button and dispose behavior can be verified.
class _DemoReaderLauncher extends StatefulWidget {
  const _DemoReaderLauncher({required this.book, required this.repository});

  final ComicBook book;
  final LibraryRepository repository;

  @override
  State<_DemoReaderLauncher> createState() => _DemoReaderLauncherState();
}

class _DemoReaderLauncherState extends State<_DemoReaderLauncher> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) =>
              ReaderScreen(book: widget.book, repository: widget.repository),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return LibraryScreen(repository: widget.repository);
  }
}

String? _arg(List<String> args, String name) {
  final prefix = '--$name=';
  for (final arg in args) {
    if (arg.startsWith(prefix)) return arg.substring(prefix.length);
  }
  return null;
}
