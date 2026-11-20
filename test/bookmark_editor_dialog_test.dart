import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manhua_reader/models/bookmark.dart';
import 'package:manhua_reader/theme/app_theme.dart';
import 'package:manhua_reader/widgets/bookmark_editor_dialog.dart';

void main() {
  testWidgets('bookmark editor prefills and returns a custom name and note', (
    tester,
  ) async {
    BookmarkEditResult? result;
    final existing = Bookmark(
      page: 4,
      createdAt: DateTime(2026, 11, 1),
      label: '旧名称',
      note: '旧备注',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  result = await showBookmarkEditorDialog(
                    context,
                    page: 4,
                    existing: existing,
                  );
                },
                child: const Text('edit'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('edit'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('编辑书签'), findsOneWidget);
    final fields = tester
        .widgetList<TextField>(find.byType(TextField))
        .toList(growable: false);
    expect(fields, hasLength(2));
    expect(fields[0].controller!.text, '旧名称');
    expect(fields[1].controller!.text, '旧备注');

    await tester.enterText(find.byType(TextField).at(0), '新名称');
    await tester.enterText(find.byType(TextField).at(1), '新备注');
    await tester.pump();
    await tester.tap(find.text('保存'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(result, isNotNull);
    expect(result!.label, '新名称');
    expect(result!.note, '新备注');
  });

  testWidgets('bookmark editor allows saving an empty default bookmark', (
    tester,
  ) async {
    BookmarkEditResult? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  result = await showBookmarkEditorDialog(context, page: 2);
                },
                child: const Text('add'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('add'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('添加书签'), findsOneWidget);

    await tester.tap(find.text('保存'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(result, isNotNull);
    expect(result!.label, isNull);
    expect(result!.note, isNull);
  });
}
