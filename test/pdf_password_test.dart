import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:manhua_reader/services/app_paths.dart';
import 'package:manhua_reader/services/library_repository.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  final encrypted = File('test/encrypted_sample.pdf');
  final cache = Directory.systemTemp.createTempSync('manhua_password_test_');

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

  group(
    'Encrypted PDF',
    () {
      test('opens with the correct password', () async {
        final document = await PdfDocument.openFile(
          encrypted.path,
          passwordProvider: () => 'manhua123',
        );
        try {
          expect(document.pages.length, 1);
        } finally {
          await document.dispose();
        }
      });

      test('retries after a wrong password', () async {
        var attempts = 0;
        final document = await PdfDocument.openFile(
          encrypted.path,
          passwordProvider: () {
            attempts++;
            return attempts == 1 ? 'wrong-password' : 'manhua123';
          },
        );
        try {
          expect(attempts, 2);
          expect(document.pages.length, 1);
        } finally {
          await document.dispose();
        }
      });

      test('throws PdfPasswordException when the user cancels', () async {
        await expectLater(
          PdfDocument.openFile(encrypted.path, passwordProvider: () => null),
          throwsA(isA<PdfPasswordException>()),
        );
      });

      test('imports with a password provider and creates a cover', () async {
        final temp = await Directory.systemTemp.createTemp(
          'manhua_pwd_import_',
        );
        addTearDown(() async {
          if (await temp.exists()) await temp.delete(recursive: true);
        });

        final paths = await AppPaths.create(temp);
        final repository = LibraryRepository(paths);
        await repository.load();

        final book = await repository.importFile(
          encrypted.path,
          pdfPasswordProvider: () async => 'manhua123',
        );

        expect(book.pageCount, 1);
        expect(book.title, 'encrypted_sample');
        expect(await File(book.filePath).exists(), isTrue);
        expect(book.coverPath, isNotNull);
        expect(await File(book.coverPath!).exists(), isTrue);
        expect(repository.books, hasLength(1));

        await repository.flush();
        repository.dispose();
      });

      test('cleans up when no password is supplied during import', () async {
        final temp = await Directory.systemTemp.createTemp('manhua_pwd_fail_');
        addTearDown(() async {
          if (await temp.exists()) await temp.delete(recursive: true);
        });

        final paths = await AppPaths.create(temp);
        final repository = LibraryRepository(paths);
        await repository.load();

        await expectLater(
          repository.importFile(encrypted.path),
          throwsA(isA<ImportException>()),
        );
        expect(repository.books, isEmpty);
        expect(await paths.booksDir.list().toList(), isEmpty);

        repository.dispose();
      });
    },
    skip: encrypted.existsSync()
        ? null
        : 'test/encrypted_sample.pdf is missing',
  );
}
