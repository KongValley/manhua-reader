import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manhua_reader/theme/app_theme.dart';
import 'package:manhua_reader/widgets/pdf_password_dialog.dart';

void main() {
  testWidgets('password dialog returns the entered password', (tester) async {
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  result = await showPdfPasswordDialog(
                    context,
                    fileName: 'secret.pdf',
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('PDF 已加密'), findsOneWidget);
    expect(find.textContaining('secret.pdf'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'manhua123');
    await tester.pump();
    await tester.tap(find.text('解锁'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(result, 'manhua123');
  });

  testWidgets('canceling the password dialog returns null', (tester) async {
    String? result = 'unset';
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  result = await showPdfPasswordDialog(
                    context,
                    fileName: 'secret.pdf',
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('取消'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(result, isNull);
  });
}
