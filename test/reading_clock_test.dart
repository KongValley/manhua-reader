import 'package:flutter_test/flutter_test.dart';
import 'package:manhua_reader/utils/reading_clock.dart';

void main() {
  test('records only active intervals and retains fractions between them', () {
    var elapsed = Duration.zero;
    final clock = ReadingClock(now: () => elapsed);
    elapsed += const Duration(minutes: 2);
    expect(clock.takeSeconds(), 0);

    clock.start();
    elapsed += const Duration(milliseconds: 1750);
    expect(clock.takeSeconds(), 1);
    clock.pause();
    expect(clock.isRunning, isFalse);
    elapsed += const Duration(minutes: 3);
    expect(clock.takeSeconds(), 0);

    clock.start();
    elapsed += const Duration(milliseconds: 500);
    clock.start();
    clock.pause();
    expect(clock.takeSeconds(), 1);
    expect(clock.takeSeconds(), 0);
  });
}
