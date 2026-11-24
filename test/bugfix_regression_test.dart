import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:manhua_reader/app.dart';
import 'package:manhua_reader/formats/comic_source.dart';
import 'package:manhua_reader/formats/comic_source_factory.dart';
import 'package:manhua_reader/models/bookmark.dart';
import 'package:manhua_reader/models/comic_book.dart';
import 'package:manhua_reader/models/library_folder.dart';
import 'package:manhua_reader/services/app_paths.dart';
import 'package:manhua_reader/services/library_repository.dart';
import 'package:manhua_reader/theme/app_theme.dart';
import 'package:manhua_reader/widgets/backup_sheet.dart';
import 'package:path/path.dart' as p;

Uint8List _sampleCbzBytes({int width = 80, int height = 120, int color = 200}) {
  final pic = image.Image(width: width, height: height);
  image.fill(pic, color: image.ColorRgb8(color, 180, 160));
  final jpg = image.encodeJpg(pic, quality: 80);
  final archive = Archive()..addFile(ArchiveFile('001.jpg', jpg.length, jpg));
  return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
}

ComicBook _seedBook({
  required String id,
  required String title,
  required String filePath,
  String? coverPath,
  ComicFormat format = ComicFormat.cbz,
  int pageCount = 10,
  bool favorite = false,
  List<String> tags = const [],
}) => ComicBook(
  id: id,
  title: title,
  originalName: '$id.${format.extension}',
  filePath: filePath,
  coverPath: coverPath,
  format: format,
  pageCount: pageCount,
  fileSize: 128,
  addedAt: DateTime(2026, 11, 1),
  favorite: favorite,
  tags: tags,
);

class _HangingSaveFilePicker extends FilePickerPlatform {
  int saveCalls = 0;
  Completer<Uri?>? nextResult;

  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    String? dialogTitle,
    String? initialDirectory,
    Function(FilePickerStatus)? onFileSaving,
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) {
    saveCalls++;
    nextResult = Completer<Uri?>();
    return nextResult!.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Models and source errors', () {
    test('ComicBook.copyWith clones mutable lists and fromJson tolerates bad types', () {
      final bookmark = Bookmark(
        page: 2,
        label: '高能',
        note: '注释',
        createdAt: DateTime(2026, 11, 1),
      );
      final original = ComicBook(
        id: 'b1',
        title: '测试',
        originalName: 'test.cbz',
        filePath: '/tmp/test.cbz',
        format: ComicFormat.cbz,
        pageCount: 10,
        fileSize: 100,
        addedAt: DateTime(2026, 11, 1),
        tags: ['动作'],
        bookmarks: [bookmark],
      );
      final copied = original.copyWith();
      copied.tags.add('新增');
      copied.bookmarks.clear();
      expect(original.tags, ['动作']);
      expect(original.bookmarks, hasLength(1));

      final badBook = ComicBook.fromJson({
        'id': 123,
        'title': true,
        'originalName': null,
        'filePath': 456,
        'format': 'pdf',
        'pageCount': 5,
        'fileSize': 12.9,
        'favorite': 'yes',
        'tags': 'not-a-list',
        'bookmarks': [42, 'bad', {'page': 1, 'label': 'ok'}],
      });
      expect(badBook.id, '');
      expect(badBook.favorite, isFalse);
      expect(badBook.tags, isEmpty);
      expect(badBook.bookmarks.single.page, 1);

      final badCount = ComicBook.fromJson({'pageCount': 'not-int'});
      expect(badCount.pageCount, 0);

      final badFolder = LibraryFolder.fromJson({'id': 99, 'name': false});
      expect(badFolder.id, '');
      expect(badFolder.name, '文件夹');
    });

    test('ComicSourceFactory.open wraps album filesystem failures as ComicOpenException', () async {
      final missingAlbum = ComicBook(
        id: 'alb1',
        title: '缺失相册',
        originalName: 'missing_album',
        filePath: p.join(Directory.systemTemp.path, 'nonexistent_album_dir_xyz'),
        format: ComicFormat.album,
        pageCount: 1,
        fileSize: 0,
        addedAt: DateTime(2026, 11, 1),
      );
      await expectLater(
        ComicSourceFactory.open(missingAlbum),
        throwsA(isA<ComicOpenException>()),
      );
    });
  });

  group('LibraryRepository bugfix regressions', () {
    late Directory temp;
    late AppPaths paths;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('manhua_repo_reg_');
      paths = await AppPaths.create(Directory(p.join(temp.path, 'app')));
    });

    tearDown(() async {
      try {
        if (await temp.exists()) await temp.delete(recursive: true);
      } catch (_) {}
    });

    test('load skips corrupt individual book and folder entries cleanly', () async {
      final validFile = File(p.join(paths.booksDir.path, 'good.cbz'));
      await validFile.writeAsBytes(_sampleCbzBytes());
      await paths.libraryFile.writeAsString(
        jsonEncode({
          'version': 5,
          'folders': [
            'corrupt-folder-entry',
            {'id': 'f1', 'name': '有效目录', 'createdAt': '2026-11-01T00:00:00.000'},
          ],
          'books': [
            12345,
            _seedBook(id: 'good', title: '好书', filePath: validFile.path).toJson(),
          ],
        }),
      );

      final repo = LibraryRepository(paths);
      await repo.load();
      addTearDown(repo.dispose);
      expect(repo.books.single.id, 'good');
      expect(repo.folders.single.name, '有效目录');
    });

    test('updateProgress notify:false suppresses listener notifications until flush/notify', () async {
      final file = File(p.join(paths.booksDir.path, 'p.cbz'));
      await file.writeAsBytes(_sampleCbzBytes());
      await paths.libraryFile.writeAsString(
        jsonEncode({
          'version': 5,
          'books': [_seedBook(id: 'p', title: '进度', filePath: file.path).toJson()],
        }),
      );
      final repo = LibraryRepository(paths);
      await repo.load();
      addTearDown(repo.dispose);

      var notifications = 0;
      repo.addListener(() => notifications++);
      repo.updateProgress(repo.books.single, 4, notify: false);
      expect(notifications, 0);
      expect(repo.books.single.lastPage, 4);

      await repo.flush();
      final reloaded = LibraryRepository(paths);
      await reloaded.load();
      addTearDown(reloaded.dispose);
      expect(reloaded.books.single.lastPage, 4);
    });

    test('serializes concurrent cleanupStorage and importFile without losing newly imported files', () async {
      final repo = LibraryRepository(paths);
      await repo.load();
      addTearDown(repo.dispose);

      // Leave an orphan file on disk that cleanupStorage should remove.
      final orphan = File(p.join(paths.booksDir.path, 'orphan.cbz'));
      await orphan.writeAsBytes([1, 2, 3]);

      final src = File(p.join(temp.path, 'concurrent.cbz'));
      await src.writeAsBytes(_sampleCbzBytes(color: 120));

      final results = await Future.wait<Object?>([
        repo.cleanupStorage(),
        repo.importFile(src.path, originalName: 'concurrent.cbz'),
      ]);

      final imported = results[1]! as ComicBook;
      expect(await orphan.exists(), isFalse);
      expect(await File(imported.filePath).exists(), isTrue);
      expect(repo.books, hasLength(1));
    });

    test('stuck finalizingDeletion does not block re-importing same file and cleanup retries it', () async {
      final src = File(p.join(temp.path, 'reimport.cbz'));
      await src.writeAsBytes(_sampleCbzBytes(color: 90));
      final stuckFile = File(p.join(paths.booksDir.path, 'stuck.cbz'));
      await stuckFile.writeAsBytes(await src.readAsBytes());

      await paths.libraryFile.writeAsString(
        jsonEncode({
          'version': 5,
          'books': <Object?>[],
          'finalizingDeletion': [
            _seedBook(
              id: 'stuck',
              title: 'reimport',
              filePath: stuckFile.path,
            ).toJson(),
          ],
        }),
      );

      final repo = LibraryRepository(paths);
      await repo.load();
      addTearDown(repo.dispose);

      final imported = await repo.importFile(src.path, originalName: 'reimport.cbz');
      expect(repo.books.single.id, imported.id);
      await repo.cleanupStorage();
      expect(await stuckFile.exists(), isFalse);
      expect(await File(imported.filePath).exists(), isTrue);
    });

    test('preserve shared cover across relink and reject traversal / sanitize restoreBackupFile', () async {
      final sharedCover = File(p.join(paths.coversDir.path, 'shared.jpg'));
      await sharedCover.writeAsBytes(_sampleCbzBytes());
      final fileA = File(p.join(paths.booksDir.path, 'a.cbz'));
      final fileB = File(p.join(paths.booksDir.path, 'b.cbz'));
      await fileA.writeAsBytes(_sampleCbzBytes(color: 10));
      await fileB.writeAsBytes(_sampleCbzBytes(color: 20));
      await paths.libraryFile.writeAsString(
        jsonEncode({
          'version': 5,
          'books': [
            _seedBook(id: 'a', title: 'A', filePath: fileA.path, coverPath: sharedCover.path).toJson(),
            _seedBook(id: 'b', title: 'B', filePath: fileB.path, coverPath: sharedCover.path).toJson(),
          ],
        }),
      );

      final repo = LibraryRepository(paths);
      await repo.load();
      addTearDown(repo.dispose);

      final relinkSrc = File(p.join(temp.path, 'a_new.cbz'));
      await relinkSrc.writeAsBytes(_sampleCbzBytes(color: 30));
      await repo.relinkFile(repo.books.first, relinkSrc.path);
      // Shared cover is still referenced by book B, so it must remain on disk.
      expect(await sharedCover.exists(), isTrue);

      // Build a streaming .mrbackup file exercising traversal entries, bad IDs, and collisions.
      final cbzPayload = _sampleCbzBytes(color: 40);
      final coverImg = image.encodeJpg(image.Image(width: 8, height: 8));
      final manifest = jsonEncode({
        'format': LibraryRepository.backupFormat,
        'version': 5,
        'includeFiles': true,
        'books': [
          {
            'id': '../../bad-id',
            'title': '无格式字段',
            'originalName': 'first.cbz',
            'filePath': 'books/../../escape.cbz',
            'coverPath': 'covers/.',
            'pageCount': 1,
            'fileSize': cbzPayload.length,
            'addedAt': '2026-11-01T00:00:00.000',
          },
          {
            'id': 'dup-id',
            'title': '合法且同文件名',
            'originalName': 'same.cbz',
            'filePath': 'books/shared_name.cbz',
            'coverPath': 'covers/c1.jpg',
            'pageCount': 1,
            'fileSize': cbzPayload.length,
            'addedAt': '2026-11-01T00:00:00.000',
          },
          {
            'id': 'dup-other',
            'title': '第二本同封面路径',
            'originalName': 'other.cbz',
            'filePath': 'books/other.cbz',
            'coverPath': 'covers/c1.jpg',
            'pageCount': 1,
            'fileSize': cbzPayload.length,
            'addedAt': '2026-11-01T00:00:00.000',
          },
        ],
      });

      final restoreArchive = Archive()
        ..addFile(ArchiveFile.bytes('manifest.json', utf8.encode(manifest)))
        ..addFile(ArchiveFile.bytes('books/../../escape.cbz', cbzPayload))
        ..addFile(ArchiveFile.bytes('books/shared_name.cbz', cbzPayload))
        ..addFile(ArchiveFile.bytes('books/other.cbz', cbzPayload))
        ..addFile(ArchiveFile.bytes('covers/c1.jpg', coverImg));

      final restoreZip = File(p.join(temp.path, 'restore.mrbackup'));
      await restoreZip.writeAsBytes(ZipEncoder().encodeBytes(restoreArchive));

      final targetPaths = await AppPaths.create(Directory(p.join(temp.path, 'target')));
      await File(p.join(targetPaths.booksDir.path, 'shared_name.cbz')).writeAsBytes([1]);
      final targetRepo = LibraryRepository(targetPaths);
      await targetRepo.load();
      addTearDown(targetRepo.dispose);

      final result = await targetRepo.restoreBackupFile(restoreZip);
      expect(result.imported, 3);
      final bad = targetRepo.books.firstWhere((b) => b.title == '无格式字段');
      // Traversal filePath must be ignored (missing file), format inferred as cbz, ID sanitized.
      expect(bad.format, ComicFormat.cbz);
      expect(bad.id.contains('/'), isFalse);
      expect(bad.id.contains('..'), isFalse);
      expect(bad.filePath, '');
      expect(bad.coverPath, isNull);

      // Colliding archive filename keeps book id intact while saving under a disambiguated path.
      final dup = targetRepo.books.firstWhere((b) => b.id == 'dup-id');
      expect(await File(dup.filePath).exists(), isTrue);
      expect(p.basename(dup.filePath), isNot('shared_name.cbz'));

      // Shared cover entry in archive must not be shared between two books.
      final dupOther = targetRepo.books.firstWhere((b) => b.id == 'dup-other');
      expect(dup.coverPath, isNot(dupOther.coverPath));
    });
  });

  group('BackupSheet, LibraryScreen selection, and AppLifecycle regressions', () {
    late Directory temp;
    late AppPaths paths;
    late LibraryRepository repository;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('manhua_ui_reg_');
      paths = await AppPaths.create(Directory(p.join(temp.path, 'app')));
    });

    tearDown(() async {
      try {
        if (await temp.exists()) await temp.delete(recursive: true);
      } catch (_) {}
    });

    testWidgets('BackupSheet locks _exportJson and disables PopScope while saving', (tester) async {
      final prevPicker = FilePickerPlatform.instance;
      final fakePicker = _HangingSaveFilePicker();
      FilePickerPlatform.instance = fakePicker;
      addTearDown(() => FilePickerPlatform.instance = prevPicker);

      await tester.runAsync(() async {
        repository = LibraryRepository(paths);
        await repository.load();
      });
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(() async {
          await repository.flush();
          repository.dispose();
        });
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: BackupSheet(repository: repository),
          ),
        ),
      );

      PopScope<dynamic> currentPopScope() =>
          tester.widget<PopScope<dynamic>>(find.byType(PopScope<dynamic>));
      expect(currentPopScope().canPop, isTrue);

      await tester.tap(find.text('导出书架数据'));
      await tester.pump();
      expect(fakePicker.saveCalls, 1);
      expect(currentPopScope().canPop, isFalse);

      // Re-tapping while busy should be ignored.
      await tester.tap(find.text('导出书架数据'), warnIfMissed: false);
      await tester.pump();
      expect(fakePicker.saveCalls, 1);

      fakePicker.nextResult!.complete(null);
      await tester.pumpAndSettle();
      expect(currentPopScope().canPop, isTrue);
    });

    testWidgets('LibraryScreen prunes stale selections, handles subset select-all, and flushes on lifecycle pause', (tester) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.runAsync(() async {
        final f1 = File(p.join(paths.booksDir.path, 'b1.cbz'))
          ..writeAsBytesSync(_sampleCbzBytes());
        final f2 = File(p.join(paths.booksDir.path, 'b2.cbz'))
          ..writeAsBytesSync(_sampleCbzBytes());
        await paths.libraryFile.writeAsString(
          jsonEncode({
            'version': 5,
            'books': [
              _seedBook(id: 'b1', title: '漫画一', filePath: f1.path, favorite: true).toJson(),
              _seedBook(id: 'b2', title: '漫画二', filePath: f2.path, favorite: true).toJson(),
            ],
          }),
        );
        repository = LibraryRepository(paths);
        await repository.load();
      });
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(() async {
          await repository.flush();
          repository.dispose();
        });
      });

      await tester.pumpWidget(ManhuaApp(repository: repository));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Apply favorites filter, then select 漫画一.
      await tester.tap(find.byTooltip('排序与筛选'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.tap(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('只看收藏'),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('应用'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      await tester.longPress(find.text('漫画一'));
      await tester.pump();
      expect(find.text('已选 1 本'), findsOneWidget);

      // Unfavorite b1 externally: 1 visible item (漫画二) remains while b1 is still in _selectedIds.
      repository.toggleFavorite(repository.books.firstWhere((b) => b.id == 'b1'));
      await tester.pump();
      expect(find.text('已选 1 本'), findsOneWidget);

      // Tapping 全选 must select visible 漫画二 -> 已选 2 本 (not clear because counts matched!).
      await tester.tap(find.text('全选'));
      await tester.pump();
      expect(find.text('已选 2 本'), findsOneWidget);

      // Deleting b1 externally must prune _selectedIds -> 已选 1 本; deleting b2 exits selection.
      await tester.runAsync(() async {
        await repository.deleteBook(repository.books.firstWhere((b) => b.id == 'b1'));
      });
      await tester.pump();
      expect(find.text('已选 1 本'), findsOneWidget);

      // Update progress with notify:false and trigger AppLifecycleState.paused -> flushes to disk.
      repository.updateProgress(repository.books.first, 3, notify: false);
      await tester.runAsync(() async {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await Future<void>.delayed(const Duration(milliseconds: 200));
        final json = jsonDecode(await paths.libraryFile.readAsString()) as Map<String, dynamic>;
        final savedBooks = json['books'] as List<dynamic>;
        expect(savedBooks.single['lastPage'], 3);
      });

      await tester.runAsync(() async {
        await repository.deleteBook(repository.books.first);
      });
      await tester.pump();
      expect(find.textContaining('已选'), findsNothing);
    });
  });
}
