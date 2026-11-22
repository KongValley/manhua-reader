import 'package:flutter_test/flutter_test.dart';
import 'package:manhua_reader/models/reader_settings.dart';

void main() {
  test('uses comfortable defaults', () {
    final settings = ReaderSettings();
    expect(settings.keepAwake, isTrue);
    expect(settings.brightness, 1);
    expect(settings.warmth, 0);
    expect(settings.autoTurnSeconds, 0);
    expect(settings.volumeKeys, isFalse);
    expect(settings.pageTurnAnimation, PageTurnAnimation.paper);
  });

  test('round-trips every new reading setting', () {
    final settings = ReaderSettings(
      mode: ReadingMode.vertical,
      rightToLeft: true,
      doublePage: true,
      keepAwake: false,
      brightness: 0.65,
      warmth: 0.2,
      autoTurnSeconds: 15,
      volumeKeys: true,
      pageTurnAnimation: PageTurnAnimation.slide,
    );

    final restored = ReaderSettings.fromJson(settings.toJson());
    expect(restored.mode, ReadingMode.vertical);
    expect(restored.rightToLeft, isTrue);
    expect(restored.doublePage, isTrue);
    expect(restored.keepAwake, isFalse);
    expect(restored.brightness, closeTo(0.65, 0.0001));
    expect(restored.warmth, closeTo(0.2, 0.0001));
    expect(restored.autoTurnSeconds, 15);
    expect(restored.volumeKeys, isTrue);
    expect(restored.pageTurnAnimation, PageTurnAnimation.slide);
  });

  test('clamps invalid values and ignores unknown intervals', () {
    final restored = ReaderSettings.fromJson({
      'brightness': 0.1,
      'warmth': 0.9,
      'autoTurnSeconds': 9,
      'pageTurnAnimation': 'unknown',
    });
    expect(restored.brightness, 0.4);
    expect(restored.warmth, 0.4);
    expect(restored.autoTurnSeconds, 0);
    expect(restored.pageTurnAnimation, PageTurnAnimation.paper);
  });

  test('older settings JSON keeps working', () {
    final restored = ReaderSettings.fromJson({
      'mode': 'horizontal',
      'rightToLeft': true,
      'doublePage': true,
    });
    expect(restored.rightToLeft, isTrue);
    expect(restored.doublePage, isTrue);
    expect(restored.keepAwake, isTrue);
    expect(restored.autoTurnSeconds, 0);
  });
}
