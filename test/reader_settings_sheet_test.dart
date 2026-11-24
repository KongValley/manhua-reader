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

    // The sheet is scrollable; bring the auto-turn controls into view first.
    // 设置面板可滚动，先把自动翻页控件滚到可见区域。
    await tester.ensureVisible(find.widgetWithText(SwitchListTile, '自动翻页'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(SwitchListTile, '自动翻页'));
    await tester.pump();
    expect(autoTurn, 10);

    await tester.ensureVisible(find.text('5 秒'));
    await tester.pumpAndSettle();
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

  testWidgets('changes spread pairing, tap zones and auto crop', (
    tester,
  ) async {
    int? spreadOffset;
    TapZoneWidth? tapZone;
    bool? autoCrop;
    await _pump(
      tester,
      onSpreadOffsetChanged: (value) => spreadOffset = value,
      onTapZoneWidthChanged: (value) => tapZone = value,
      onAutoCropChanged: (value) => autoCrop = value,
    );

    // Pairing only matters once double-page mode is on.
    // 只有开启双页模式后才需要选择配对方式。
    expect(find.text('封面单页'), findsNothing);
    await tester.tap(find.text('双页模式'));
    await tester.pump();
    expect(find.text('封面单页'), findsOneWidget);
    expect(find.text('前两页单独'), findsOneWidget);

    await tester.tap(find.text('前两页单独'));
    await tester.pump();
    expect(spreadOffset, 2);
    expect(find.text('前两页单独显示，之后两页一跨'), findsOneWidget);

    await tester.ensureVisible(find.text('适中'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('宽'));
    await tester.pump();
    expect(tapZone, TapZoneWidth.wide);

    await tester.ensureVisible(find.widgetWithText(SwitchListTile, '自动裁边'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(SwitchListTile, '自动裁边'));
    await tester.pump();
    expect(autoCrop, isTrue);
  });

  testWidgets('offers resetting per-book reading preferences', (tester) async {
    var resets = 0;
    await _pump(tester, hasBookPrefs: true, onResetBookPrefs: () => resets++);
    expect(find.text('本书使用单独的阅读设置'), findsOneWidget);
    await tester.tap(find.text('改回跟随全局'));
    await tester.pump();
    expect(resets, 1);
    expect(find.text('改回跟随全局'), findsNothing);
    expect(find.text('双页模式'), findsNothing);

    await _pump(tester);
    expect(find.text('阅读方式会按书记住'), findsOneWidget);
    expect(find.text('改回跟随全局'), findsNothing);
  });

  testWidgets('hides double-page mode for single-page comics', (tester) async {
    await _pump(tester, canDoublePage: false);
    expect(find.text('双页模式'), findsNothing);
  });
}

Future<void> _pump(
  WidgetTester tester, {
  bool isAndroid = false,
  bool hasBookPrefs = false,
  bool canDoublePage = true,
  ValueChanged<ReadingMode>? onModeChanged,
  ValueChanged<bool>? onRightToLeftChanged,
  ValueChanged<bool>? onDoublePageChanged,
  ValueChanged<bool>? onKeepAwakeChanged,
  ValueChanged<double>? onBrightnessChanged,
  ValueChanged<double>? onWarmthChanged,
  ValueChanged<int>? onAutoTurnChanged,
  ValueChanged<bool>? onVolumeKeysChanged,
  ValueChanged<PageTurnAnimation>? onPageTurnAnimationChanged,
  ValueChanged<int>? onSpreadOffsetChanged,
  ValueChanged<TapZoneWidth>? onTapZoneWidthChanged,
  ValueChanged<bool>? onAutoCropChanged,
  VoidCallback? onResetBookPrefs,
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
          canDoublePage: canDoublePage,
          keepAwake: true,
          brightness: 1,
          warmth: 0,
          autoTurnSeconds: 0,
          volumeKeys: false,
          pageTurnAnimation: PageTurnAnimation.paper,
          spreadOffset: 1,
          tapZoneWidth: TapZoneWidth.medium,
          autoCrop: false,
          hasBookPrefs: hasBookPrefs,
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
          onSpreadOffsetChanged: onSpreadOffsetChanged ?? (_) {},
          onTapZoneWidthChanged: onTapZoneWidthChanged ?? (_) {},
          onAutoCropChanged: onAutoCropChanged ?? (_) {},
          onResetBookPrefs: () {
            onResetBookPrefs?.call();
            return (
              mode: ReadingMode.vertical,
              rightToLeft: false,
              doublePage: false,
              spreadOffset: 1,
            );
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
