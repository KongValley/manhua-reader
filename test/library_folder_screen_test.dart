import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manhua_reader/app.dart';
import 'package:manhua_reader/models/comic_book.dart';
import 'package:manhua_reader/services/app_paths.dart';
import 'package:manhua_reader/services/library_repository.dart';
import 'package:path/path.dart' as p;

class _Harness {
  late Directory temp;
  late AppPaths paths;
  late LibraryRepository repository;
}

Future<_Harness> _pumpLibrary(WidgetTester tester) async {
  final harness = _Harness();
  tester.view.physicalSize = const Size(1000, 1600);
  tester.view.devicePixelRatio = 1.0;

  await tester.runAsync(() async {
    harness.temp = await Directory.systemTemp.createTemp('manhua_folder_ui_');
    harness.paths = await AppPaths.create(harness.temp);

    Future<ComicBook> book(String id, String title, {String? folderId}) async {
      final file = File(p.join(harness.paths.booksDir.path, '$id.pdf'));
      await file.writeAsBytes([1]);
      return ComicBook(
        id: id,
        title: title,
        originalName: '$id.pdf',
        filePath: file.path,
        format: ComicFormat.pdf,
        pageCount: 10,
        fileSize: 1,
        addedAt: DateTime(2026, 11, 1),
        folderId: folderId,
      );
    }

    final books = [
      await book('in-folder-1', '文件夹中的书 1', folderId: 'folder-1'),
      await book('in-folder-2', '文件夹中的书 2', folderId: 'folder-1'),
      await book('root', '根目录书'),
    ];

    await harness.paths.libraryFile.writeAsString(
      jsonEncode({
        'version': 4,
        'settings': <String, Object?>{},
        'library': {'view': 'grid', 'sort': 'recentRead'},
        'folders': [
          {
            'id': 'folder-1',
            'name': '合集A',
            'createdAt': '2026-11-01T00:00:00.000',
          },
        ],
        'books': books.map((book) => book.toJson()).toList(),
      }),
    );

    harness.repository = LibraryRepository(harness.paths);
    await harness.repository.load();
  });

  await tester.pumpWidget(ManhuaApp(repository: harness.repository));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));

  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      await harness.repository.flush();
      harness.repository.dispose();
      if (await harness.temp.exists()) {
        await harness.temp.delete(recursive: true);
      }
    });
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  return harness;
}

void main() {
  testWidgets('keeps folder books grouped and renames from the folder screen', (
    tester,
  ) async {
    final harness = await _pumpLibrary(tester);

    expect(find.text('文件夹'), findsOneWidget);
    expect(find.text('合集A'), findsOneWidget);
    expect(find.text('2 本'), findsOneWidget);
    expect(find.text('根目录书'), findsOneWidget);
    expect(find.text('文件夹中的书 1'), findsNothing);
    expect(find.text('文件夹中的书 2'), findsNothing);

    await tester.tap(find.text('合集A'));
    await tester.pumpAndSettle();
    expect(find.text('文件夹中的书 1'), findsOneWidget);
    expect(find.text('文件夹中的书 2'), findsOneWidget);
    expect(find.text('根目录书'), findsNothing);

    await tester.tap(find.byTooltip('重命名文件夹'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    final field = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(field, '改名的文件夹');
    await tester.pump();
    await tester.tap(find.text('保存'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(harness.repository.folders.single.name, '改名的文件夹');
    expect(find.text('改名的文件夹'), findsWidgets);
    await tester.runAsync(harness.repository.flush);
  });

  testWidgets('renames and deletes a folder from the shelf card', (
    tester,
  ) async {
    final harness = await _pumpLibrary(tester);

    Future<void> openFolderMenu() async {
      await tester.tap(find.byTooltip('文件夹操作'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
    }

    await openFolderMenu();
    await tester.tap(find.text('重命名文件夹'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      '书架文件夹',
    );
    await tester.pump();
    await tester.tap(find.text('保存'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('书架文件夹'), findsOneWidget);
    expect(harness.repository.folders.single.name, '书架文件夹');

    await openFolderMenu();
    await tester.tap(find.text('删除文件夹'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.widgetWithText(FilledButton, '删除文件夹'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(harness.repository.folders, isEmpty);
    expect(find.text('文件夹'), findsNothing);
    expect(find.text('文件夹中的书 1'), findsOneWidget);
    expect(find.text('文件夹中的书 2'), findsOneWidget);
  });

  testWidgets('search includes books inside folders', (tester) async {
    await _pumpLibrary(tester);

    await tester.enterText(find.byType(TextField), '文件夹中的书 1');
    await tester.pump();
    expect(find.text('文件夹中的书 1').last, findsOneWidget);
    expect(find.text('文件夹中的书 2'), findsNothing);
    expect(find.text('合集A'), findsNothing);

    await tester.tap(find.byTooltip('清除搜索'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '合集A');
    await tester.pump();
    expect(find.text('文件夹中的书 1'), findsOneWidget);
    expect(find.text('文件夹中的书 2'), findsOneWidget);
    expect(find.text('根目录书'), findsNothing);
  });
}
