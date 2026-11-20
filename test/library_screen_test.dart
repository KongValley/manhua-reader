import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manhua_reader/app.dart';
import 'package:manhua_reader/services/app_paths.dart';
import 'package:manhua_reader/services/library_repository.dart';

void main() {
  testWidgets('empty library shows the import entry points', (tester) async {
    late Directory temp;
    late LibraryRepository repository;

    await tester.runAsync(() async {
      temp = await Directory.systemTemp.createTemp('manhua_ui_test_');
      final paths = await AppPaths.create(temp);
      repository = LibraryRepository(paths);
      await repository.load();
    });

    await tester.pumpWidget(ManhuaApp(repository: repository));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('漫阅'), findsOneWidget);
    expect(find.text('书架还是空的'), findsOneWidget);
    expect(find.text('导入漫画'), findsOneWidget);
    expect(find.text('导入'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    repository.dispose();
    await tester.runAsync(() => temp.delete(recursive: true));
  });
}
