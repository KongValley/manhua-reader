import 'package:flutter_test/flutter_test.dart';
import 'package:manhua_reader/utils/auto_turn.dart';

void main() {
  test('turns pages until the callback reports the end', () async {
    var turns = 0;
    final controller = AutoTurnController(
      onTurn: () {
        turns++;
        return turns < 3;
      },
    )..configure(const Duration(milliseconds: 20));
    addTearDown(controller.dispose);

    await Future<void>.delayed(const Duration(milliseconds: 130));
    expect(turns, 3);
    expect(controller.isRunning, isFalse);
  });

  test('waits while the canTurn guard is false', () async {
    var allowed = false;
    var turns = 0;
    final controller = AutoTurnController(
      onTurn: () {
        turns++;
        return true;
      },
      canTurn: () => allowed,
    )..configure(const Duration(milliseconds: 20));
    addTearDown(controller.dispose);

    await Future<void>.delayed(const Duration(milliseconds: 70));
    expect(turns, 0);
    allowed = true;
    await Future<void>.delayed(const Duration(milliseconds: 70));
    expect(turns, greaterThan(0));
  });

  test('pauses and resumes with the app lifecycle', () async {
    var turns = 0;
    final controller = AutoTurnController(
      onTurn: () {
        turns++;
        return true;
      },
    )..configure(const Duration(milliseconds: 20));
    addTearDown(controller.dispose);

    controller.setActive(false);
    await Future<void>.delayed(const Duration(milliseconds: 70));
    expect(turns, 0);
    controller.setActive(true);
    await Future<void>.delayed(const Duration(milliseconds: 70));
    expect(turns, greaterThan(0));
  });

  test('a zero interval disables the timer', () async {
    var turns = 0;
    final controller = AutoTurnController(
      onTurn: () {
        turns++;
        return true;
      },
    )..configure(const Duration(milliseconds: 20));
    addTearDown(controller.dispose);

    controller.configure(null);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(turns, 0);
    expect(controller.isRunning, isFalse);
  });
}
