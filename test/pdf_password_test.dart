import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manhua_reader/models/comic_book.dart';
import 'package:manhua_reader/services/app_paths.dart';
import 'package:manhua_reader/services/library_repository.dart';
import 'package:manhua_reader/services/pdf_password_cache.dart';
import 'package:manhua_reader/services/pdf_password_flow.dart';
import 'package:manhua_reader/services/pdf_password_store.dart';
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

  group('Remembered PDF passwords', () {
    const channel = MethodChannel('manhua/pdf_password_store');
    final stored = <String, String>{};
    final operations = <String>[];
    var unavailable = false;

    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            operations.add(call.method);
            if (unavailable) throw PlatformException(code: 'unavailable');
            final args = call.arguments as Map;
            final key = args['key'] as String;
            final password = args['password'] as String?;
            switch (call.method) {
              case 'contains':
                return stored.containsKey(key);
              case 'read':
                return stored[key];
              case 'write':
                stored[key] = password!;
              case 'delete':
                if (password == null || stored[key] == password) {
                  stored.remove(key);
                }
            }
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      debugDefaultTargetPlatformOverride = null;
      PdfPasswordCache.clear();
      stored.clear();
      operations.clear();
      unavailable = false;
    });

    test('writes only the successfully used opted-in password', () async {
      final book = _book();
      final errors = <String?>[];
      final flow = PdfPasswordFlow(
        prompt: (errorText) async {
          errors.add(errorText);
          return PdfPasswordEntry(
            errorText == null ? 'wrong' : 'manhua123',
            remember: true,
          );
        },
      );
      final document = await PdfDocument.openFile(
        encrypted.path,
        passwordProvider: flow.provide,
      );
      addTearDown(document.dispose);
      expect(stored, isEmpty);
      expect(errors, [null, '密码不正确，请重试']);
      expect(await flow.onSuccess(book), isTrue);
      expect(stored.values, ['manhua123']);
      expect(operations, ['write']);
      expect(PdfPasswordCache.get(book.filePath), 'manhua123');
    });

    test(
      'tries the session before an independently remembered password',
      () async {
        final book = _book();
        await PdfPasswordStore.remember(book, 'manhua123');
        PdfPasswordCache.put(book.filePath, 'stale-session');
        operations.clear();
        final flow = PdfPasswordFlow(
          book: book,
          prompt: (_) async => throw StateError('Unexpected password dialog'),
        );
        expect(await flow.provide(), 'stale-session');
        expect(operations, isEmpty);
        expect(await flow.provide(), 'manhua123');
        expect(await flow.onSuccess(book), isTrue);
        expect(operations, ['read']);
      },
    );

    test(
      'rejects the shared stale value once and allows cancellation',
      () async {
        final book = _book();
        await PdfPasswordStore.remember(book, 'stale');
        PdfPasswordCache.put(book.filePath, 'stale');
        final flow = PdfPasswordFlow(
          book: book,
          prompt: (errorText) async {
            expect(errorText, '密码不正确，请重试');
            return null;
          },
        );
        expect(await flow.provide(), 'stale');
        expect(await flow.provide(), isNull);
        expect(stored, isEmpty);
        expect(PdfPasswordCache.get(book.filePath), isNull);
      },
    );

    test('prompts after a stale persisted value is rejected', () async {
      final book = _book();
      await PdfPasswordStore.remember(book, 'stale');
      final flow = PdfPasswordFlow(
        book: book,
        prompt: (errorText) async {
          expect(errorText, '密码不正确，请重试');
          return const PdfPasswordEntry('manhua123');
        },
      );
      expect(await flow.provide(), 'stale');
      expect(await flow.provide(), 'manhua123');
      expect(await flow.onSuccess(book), isTrue);
      expect(stored, isEmpty);
      expect(PdfPasswordCache.get(book.filePath), 'manhua123');
    });

    test(
      'forgotten credentials cannot be saved by an in-flight open',
      () async {
        final book = _book();
        final unrelated = _book(id: 'other');
        await PdfPasswordStore.remember(unrelated, 'unrelated');
        final flow = PdfPasswordFlow(
          book: book,
          prompt: (_) async => const PdfPasswordEntry('new', remember: true),
        );
        expect(await flow.provide(), 'new');
        expect(await PdfPasswordStore.forget(book), isTrue);
        expect(await flow.onSuccess(book), isTrue);
        expect(stored.values, ['unrelated']);
        expect(PdfPasswordCache.get(book.filePath), isNull);
      },
    );

    test('continues unlocking when secure storage is unavailable', () async {
      final book = _book();
      unavailable = true;
      final flow = PdfPasswordFlow(
        book: book,
        prompt: (_) async => const PdfPasswordEntry('new', remember: true),
      );
      expect(await flow.provide(), 'new');
      expect(await flow.onSuccess(book), isFalse);
      expect(PdfPasswordCache.get(book.filePath), 'new');
    });

    test(
      'relink and finalized deletion clear only the associated password',
      () async {
        final temp = await Directory.systemTemp.createTemp(
          'manhua_pwd_cleanup_',
        );
        addTearDown(() => temp.delete(recursive: true));
        final paths = await AppPaths.create(temp);
        final repository = LibraryRepository(paths);
        addTearDown(repository.dispose);
        await repository.load();
        final book = await repository.importFile(
          encrypted.path,
          pdfPasswordProvider: () => 'manhua123',
        );
        final oldPath = book.filePath;
        await PdfPasswordStore.remember(book, 'manhua123');
        PdfPasswordCache.put(oldPath, 'manhua123');
        expect(await PdfPasswordStore.hasRemembered(book), isTrue);
        expect(
          await paths.libraryFile.readAsString(),
          isNot(contains('manhua123')),
        );

        await expectLater(
          repository.relinkFile(book, encrypted.path),
          throwsA(isA<ImportException>()),
        );
        expect(await PdfPasswordStore.hasRemembered(book), isTrue);
        await repository.relinkFile(
          book,
          encrypted.path,
          pdfPasswordProvider: () => 'manhua123',
        );
        expect(PdfPasswordCache.get(oldPath), isNull);
        expect(stored, isEmpty);

        await PdfPasswordStore.remember(book, 'manhua123');
        repository.deleteBooksLater([book]);
        expect(await PdfPasswordStore.hasRemembered(book), isTrue);
        expect(repository.undoPendingDeletion(), 1);
        expect(await PdfPasswordStore.hasRemembered(book), isTrue);
        await repository.deleteBook(book);
        expect(stored, isEmpty);
        await repository.flush();
      },
    );
  });
}

ComicBook _book({String id = 'pdf'}) => ComicBook(
  id: id,
  title: 'Secret PDF',
  originalName: 'secret.pdf',
  filePath: '/books/$id.pdf',
  format: ComicFormat.pdf,
  pageCount: 1,
  fileSize: 1,
  addedAt: DateTime(2026),
);
