import 'package:flutter_test/flutter_test.dart';
import 'package:manhua_reader/models/reading_stats.dart';

void main() {
  test('tracks daily, weekly and lifetime pages', () {
    final stats = ReadingStats();
    stats.addPages(10, DateTime(2026, 11, 16));
    stats.addPages(5, DateTime(2026, 11, 17));
    stats.addPages(7, DateTime(2026, 11, 20));
    stats.addPages(3, DateTime(2026, 11, 21));

    final now = DateTime(2026, 11, 21, 12);
    expect(stats.pagesOn(DateTime(2026, 11, 16)), 10);
    expect(stats.pagesToday(now), 3);
    expect(stats.pagesThisWeek(now), 25);
    expect(stats.totalPages, 25);
    expect(stats.lastSevenDays(now), [0, 10, 5, 0, 0, 7, 3]);
  });

  test('calculates current and longest streaks', () {
    final stats = ReadingStats();
    for (final day in [14, 15, 16, 18, 19, 20, 21]) {
      stats.addPages(1, DateTime(2026, 11, day));
    }
    final now = DateTime(2026, 11, 21);
    expect(stats.currentStreak(now), 4);
    expect(stats.longestStreak(), 4);

    final yesterdayOnly = ReadingStats()..addPages(2, DateTime(2026, 11, 20));
    expect(yesterdayOnly.currentStreak(now), 1);
    expect(ReadingStats().currentStreak(now), 0);
  });

  test('merges backups without double counting days', () {
    final first = ReadingStats()
      ..addPages(4, DateTime(2026, 11, 20))
      ..addPages(2, DateTime(2026, 11, 21));
    final backup = ReadingStats()
      ..addPages(6, DateTime(2026, 11, 20))
      ..addPages(1, DateTime(2026, 11, 21));
    first.merge(backup);
    expect(first.pagesOn(DateTime(2026, 11, 20)), 6);
    expect(first.pagesOn(DateTime(2026, 11, 21)), 2);
  });

  test('round-trips through JSON and prunes old days', () {
    final stats = ReadingStats()
      ..addPages(5, DateTime(2023, 1, 1))
      ..addPages(8, DateTime(2026, 11, 21));
    stats.addPages(1, DateTime(2026, 11, 21));
    expect(stats.pagesOn(DateTime(2023, 1, 1)), 0);

    final restored = ReadingStats.fromJson(stats.toJson());
    expect(restored.pagesOn(DateTime(2026, 11, 21)), 9);
    expect(restored.totalPages, 9);
  });
}
