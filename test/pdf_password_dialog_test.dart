import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manhua_reader/services/pdf_password_flow.dart';
import 'package:manhua_reader/theme/app_theme.dart';
import 'package:manhua_reader/widgets/pdf_password_dialog.dart';

void main() {
  Future<void> open(
    WidgetTester tester,
    ValueChanged<PdfPasswordEntry?> onResult, {
    String? errorText,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  onResult(
                    await showPdfPasswordDialog(
                      context,
                      fileName: 'secret.pdf',
                      errorText: errorText,
                    ),
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
    await tester.pumpAndSettle();
  }

  testWidgets('returns a session-only password by default', (tester) async {
    PdfPasswordEntry? result;
    await open(tester, (entry) => result = entry);

    expect(find.text('PDF 已加密'), findsOneWidget);
    expect(find.textContaining('secret.pdf'), findsOneWidget);
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      isFalse,
    );

    await tester.enterText(find.byType(TextField), 'manhua123');
    await tester.pump();
    await tester.tap(find.text('解锁'));
    await tester.pumpAndSettle();

    expect(result?.password, 'manhua123');
    expect(result?.remember, isFalse);
  });

  testWidgets('the retry dialog requires a fresh opt-in', (tester) async {
    PdfPasswordEntry? result;
    await open(tester, (entry) => result = entry, errorText: '密码不正确，请重试');

    expect(find.text('密码不正确，请重试'), findsOneWidget);
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      isFalse,
    );
    await tester.tap(find.text('在此设备上记住此书密码'));
    await tester.enterText(find.byType(TextField), 'manhua123');
    await tester.pump();
    await tester.tap(find.text('解锁'));
    await tester.pumpAndSettle();

    expect(result?.password, 'manhua123');
    expect(result?.remember, isTrue);
  });

  testWidgets('canceling the password dialog returns null', (tester) async {
    PdfPasswordEntry? result = const PdfPasswordEntry('unset');
    await open(tester, (entry) => result = entry);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(result, isNull);
  });

  testWidgets('offers session-only unlocking on unsupported platforms', (
    tester,
  ) async {
    await open(tester, (_) {});
    expect(find.byType(CheckboxListTile), findsNothing);
  }, variant: const TargetPlatformVariant({TargetPlatform.iOS}));
}
