import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manhua_reader/models/reader_settings.dart';
import 'package:manhua_reader/theme/app_theme.dart';
import 'package:manhua_reader/widgets/reader_settings_sheet.dart';

void main() {
  testWidgets('changes reading mode and page animation', (tester) async {
    ReadingMode? mode;
    PageTurnAnimation? animation;
    await _pump(
      tester,
      onModeChanged: (value) => mode = value,
      onPageTurnAnimationChanged: (value) => animation = value,
    );

    await tester.tap(find.text('纵向滚动'));
    await tester.pump();
    expect(mode, ReadingMode.vertical);
    expect(find.text('双页模式'), findsNothing);

    await tester.tap(find.text('滑动翻页'));
    await tester.pump();
    expect(animation, PageTurnAnimation.slide);
  });

  testWidgets('updates display, brightness and auto-turn settings', (
    tester,
  ) async {
    bool? keepAwake;
    double? brightness;
    int? autoTurn;
    await _pump(
      tester,
      onKeepAwakeChanged: (value) => keepAwake = value,
      onBrightnessChanged: (value) => brightness = value,
      onAutoTurnChanged: (value) => autoTurn = value,
    );

    await tester.tap(find.text('屏幕常亮'));
    await tester.pump();
    expect(keepAwake, isFalse);

    await tester.drag(find.byType(Slider).first, const Offset(-70, 0));
    await tester.pump();
    expect(brightness, isNotNull);
    expect(brightness, lessThan(1));

    await tester.tap(find.widgetWithText(SwitchListTile, '自动翻页'));
    await tester.pump();
    expect(autoTurn, 10);

    await tester.tap(find.text('5 秒'));
    await tester.pump();
    expect(autoTurn, 5);
  });

  testWidgets('shows volume keys only on Android', (tester) async {
    bool? volumeKeys;
    await _pump(
      tester,
      isAndroid: true,
      onVolumeKeysChanged: (value) => volumeKeys = value,
    );
    expect(find.text('音量键翻页'), findsOneWidget);
    await tester.ensureVisible(find.text('音量键翻页'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('音量键翻页'));
    await tester.pump();
    expect(volumeKeys, isTrue);

    await _pump(tester, isAndroid: false);
    expect(find.text('音量键翻页'), findsNothing);
  });
}

Future<void> _pump(
  WidgetTester tester, {
  bool isAndroid = false,
  ValueChanged<ReadingMode>? onModeChanged,
  ValueChanged<bool>? onRightToLeftChanged,
  ValueChanged<bool>? onDoublePageChanged,
  ValueChanged<bool>? onKeepAwakeChanged,
  ValueChanged<double>? onBrightnessChanged,
  ValueChanged<double>? onWarmthChanged,
  ValueChanged<int>? onAutoTurnChanged,
  ValueChanged<bool>? onVolumeKeysChanged,
  ValueChanged<PageTurnAnimation>? onPageTurnAnimationChanged,
}) async {
  tester.view.physicalSize = const Size(430, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: ReaderSettingsSheet(
          mode: ReadingMode.horizontal,
          rightToLeft: false,
          doublePage: false,
          keepAwake: true,
          brightness: 1,
          warmth: 0,
          autoTurnSeconds: 0,
          volumeKeys: false,
          pageTurnAnimation: PageTurnAnimation.paper,
          isAndroid: isAndroid,
          onModeChanged: onModeChanged ?? (_) {},
          onRightToLeftChanged: onRightToLeftChanged ?? (_) {},
          onDoublePageChanged: onDoublePageChanged ?? (_) {},
          onKeepAwakeChanged: onKeepAwakeChanged ?? (_) {},
          onBrightnessChanged: onBrightnessChanged ?? (_) {},
          onWarmthChanged: onWarmthChanged ?? (_) {},
          onAutoTurnChanged: onAutoTurnChanged ?? (_) {},
          onVolumeKeysChanged: onVolumeKeysChanged ?? (_) {},
          onPageTurnAnimationChanged: onPageTurnAnimationChanged ?? (_) {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
