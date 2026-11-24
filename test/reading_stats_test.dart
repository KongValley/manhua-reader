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

  test('tracks per-book daily time, merges nearby sessions, and sets goals', () {
    final stats = ReadingStats();
    final day1 = DateTime(2026, 11, 21, 21, 10, 0);
    // Two ticks 15s apart for the same book merge into one continuous session.
    // 同一本书间隔 15 秒的连续记录会合并为同一时段。
    stats.addSeconds(15, day1, bookId: 'b1', bookTitle: '海贼王 第1卷');
    stats.addSeconds(
      15,
      day1.add(const Duration(seconds: 15)),
      bookId: 'b1',
      bookTitle: '海贼王 第1卷',
    );
    stats.addPages(4, day1.add(const Duration(seconds: 20)), bookId: 'b1');

    // A break longer than sessionMergeGap starts a new session.
    // 超过合并间隔的休息会记作新的阅读时段。
    stats.addSeconds(
      600,
      day1.add(const Duration(minutes: 15)),
      bookId: 'b1',
      bookTitle: '海贼王 第1卷',
    );
    // Reading another comic creates a separate session and book total.
    // 阅读另一本漫画会分开统计与记录。
    stats.addSeconds(
      300,
      day1.add(const Duration(minutes: 20)),
      bookId: 'b2',
      bookTitle: '日常',
    );

    expect(stats.secondsOn(day1), 930);
    expect(stats.bookSecondsOn('b1', day1), 630);
    expect(stats.bookSecondsOn('b2', day1), 300);
    expect(stats.bookSecondsTotal('b1'), 630);
    expect(stats.bookPagesByDay(day1), {'b1': 4});

    final daySessions = stats.sessionsOn(day1);
    expect(daySessions, hasLength(3));
    expect(daySessions.first.bookId, 'b2');
    expect(daySessions.first.seconds, 300);
    expect(daySessions.last.bookId, 'b1');
    expect(daySessions.last.seconds, 30);
    expect(daySessions.last.pages, 4);

    stats.dailyGoalMinutes = 15;
    expect(stats.isGoalMetOn(day1), isTrue);
    expect(stats.goalProgressToday(day1), 1.0);
    expect(stats.lastSevenDaysSeconds(day1), [0, 0, 0, 0, 0, 0, 930]);

    // Round-trips through JSON and merges without duplicating sessions.
    // JSON 往返与合并不会重复计算时段。
    final restored = ReadingStats.fromJson(stats.toJson());
    expect(restored.dailyGoalMinutes, 15);
    expect(restored.bookSecondsTotal('b1'), 630);
    expect(restored.sessionsOn(day1), hasLength(3));

    final backup = ReadingStats.fromJson(stats.toJson())
      ..addSeconds(
        120,
        day1.add(const Duration(hours: 1)),
        bookId: 'b2',
        bookTitle: '日常',
      );
    restored.merge(backup);
    expect(restored.bookSecondsOn('b2', day1), 420);
    expect(restored.sessionsOn(day1), hasLength(4));
  });

  test('clamps midnight-crossing sessions and prunes stale sessions', () {
    final stats = ReadingStats();
    final afterMidnight = DateTime(2026, 11, 22, 0, 0, 5);
    stats.addSeconds(30, afterMidnight, bookId: 'b1', bookTitle: '测试');
    final sessions = stats.sessionsOn(afterMidnight);
    expect(sessions, hasLength(1));
    expect(sessions.single.startedAt, DateTime(2026, 11, 22, 0, 0, 0));
    expect(sessions.single.endedAt, afterMidnight);

    // Older than maxSessionDays (90) gets pruned from session log while
    // dailyBookSeconds remains within maxDays (730).
    // 超过 90 天的明细时段会被裁剪，而 730 天内的每日按书总时长仍保留。
    final old = DateTime(2026, 5, 1, 10);
    stats.addSeconds(120, old, bookId: 'b1', bookTitle: '旧记录');
    stats.addSeconds(60, DateTime(2026, 11, 22, 10), bookId: 'b1', bookTitle: '新记录');
    expect(stats.sessionsOn(old), isEmpty);
    expect(stats.bookSecondsOn('b1', old), 120);
  });
}
