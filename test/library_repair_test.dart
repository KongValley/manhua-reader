import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:manhua_reader/models/comic_book.dart';
import 'package:manhua_reader/services/app_paths.dart';
import 'package:manhua_reader/services/library_repository.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

void main() {
  final sample = File('test/encrypted_sample.pdf');
  final cache = Directory.systemTemp.createTempSync('manhua_repair_test_');

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    Pdfrx.cacheDirectoryPath ??= cache.path;
    await pdfrxFlutterInitialize();
  });

  tearDownAll(() async {
    try {
      await cache.delete(recursive: true);
    } catch (_) {}
  });

  group('File repair', () {
    late Directory temp;
    late AppPaths paths;
    late LibraryRepository repository;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('manhua_repair_');
      paths = await AppPaths.create(temp);
      repository = LibraryRepository(paths);
      await repository.load();
    });

    tearDown(() async {
      await repository.flush();
      repository.dispose();
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    Future<ComicBook> importSample() {
      return repository.importFile(
        sample.path,
        originalName: 'original.pdf',
        pdfPasswordProvider: () async => 'manhua123',
      );
    }

    Future<File> replacementCopy() async {
      final file = File(p.join(temp.path, 'replacement.pdf'));
      await sample.copy(file.path);
      return file;
    }

    test('imports a file into a shelf folder', () async {
      final folder = repository.ensureFolder('导入文件夹');
      final book = await repository.importFile(
        sample.path,
        originalName: 'foldered.pdf',
        folderId: folder.id,
        pdfPasswordProvider: () async => 'manhua123',
      );
      expect(book.folderId, folder.id);
      expect(repository.folderCounts[folder.id], 1);
      repository.renameFolder(folder, '改名文件夹');
      expect(folder.name, '改名文件夹');
    });

    test('relinks a file and keeps metadata, progress and bookmarks', () async {
      final book = await importSample();
      repository.renameBook(book, '加密漫画');
      repository.updateProgress(book, 0);
      repository.setBookmark(book, 0, label: '封面', note: '保留备注');

      final oldFile = book.filePath;
      final oldCover = book.coverPath!;
      final replacement = await replacementCopy();

      await repository.relinkFile(
        book,
        replacement.path,
        pdfPasswordProvider: () async => 'manhua123',
      );

      expect(book.title, '加密漫画');
      expect(book.pageCount, 1);
      expect(book.filePath, isNot(oldFile));
      expect(await File(book.filePath).exists(), isTrue);
      expect(await File(oldFile).exists(), isFalse);
      expect(book.coverPath, isNotNull);
      expect(book.coverPath, isNot(oldCover));
      expect(await File(book.coverPath!).exists(), isTrue);
      expect(await File(oldCover).exists(), isFalse);
      expect(book.bookmarkAt(0)?.label, '封面');
      expect(book.bookmarkAt(0)?.note, '保留备注');
      expect(await replacement.exists(), isTrue);
      expect(
        (await paths.booksDir.list().toList()).where(
          (entry) => entry.path.endsWith('.part'),
        ),
        isEmpty,
      );
    });

    test('a failed relink leaves the original book untouched', () async {
      final book = await importSample();
      final oldFile = book.filePath;
      final oldCover = book.coverPath!;
      final replacement = await replacementCopy();

      await expectLater(
        repository.relinkFile(book, replacement.path),
        throwsA(isA<ImportException>()),
      );

      expect(book.filePath, oldFile);
      expect(await File(oldFile).exists(), isTrue);
      expect(book.coverPath, oldCover);
      expect(await File(oldCover).exists(), isTrue);
      expect(
        (await paths.booksDir.list().toList()).where(
          (entry) =>
              entry.path.endsWith('.part') ||
              p.basename(entry.path).contains('_r'),
        ),
        isEmpty,
      );
    });

    test('rejects a replacement with a different format', () async {
      final book = await importSample();
      final wrong = File(p.join(temp.path, 'wrong.mobi'));
      await wrong.writeAsBytes([1, 2, 3]);

      await expectLater(
        repository.relinkFile(book, wrong.path),
        throwsA(
          isA<ImportException>().having(
            (error) => error.message,
            'message',
            contains('PDF'),
          ),
        ),
      );
    });

    test('regenerates the cover and reports a missing source file', () async {
      final book = await importSample();
      final oldCover = book.coverPath!;

      final regenerated = await repository.regenerateCover(
        book,
        pdfPasswordProvider: () async => 'manhua123',
      );

      expect(regenerated, isTrue);
      expect(book.coverPath, isNotNull);
      expect(book.coverPath, isNot(oldCover));
      expect(await File(book.coverPath!).exists(), isTrue);
      expect(await File(oldCover).exists(), isFalse);

      await File(book.filePath).delete();
      expect(await repository.regenerateCover(book), isFalse);
    });
  }, skip: sample.existsSync() ? null : 'test/encrypted_sample.pdf is missing');
}
