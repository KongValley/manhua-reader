import 'dart:math' as math;

/// A single continuous comic-reading time record on a calendar day.
/// 单次连续阅读的时间记录。
class ReadingSession {
  ReadingSession({
    required this.bookId,
    required this.bookTitle,
    required this.startedAt,
    required this.endedAt,
    required this.seconds,
    this.pages = 0,
  });

  final String bookId;
  final String bookTitle;
  final DateTime startedAt;
  final DateTime endedAt;
  final int seconds;
  final int pages;

  String get dateKey => ReadingStats.dateKey(startedAt);

  ReadingSession copyWith({
    String? bookTitle,
    DateTime? startedAt,
    DateTime? endedAt,
    int? seconds,
    int? pages,
  }) {
    return ReadingSession(
      bookId: bookId,
      bookTitle: bookTitle ?? this.bookTitle,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      seconds: seconds ?? this.seconds,
      pages: pages ?? this.pages,
    );
  }

  Map<String, Object?> toJson() => {
    'bookId': bookId,
    'bookTitle': bookTitle,
    'startedAt': startedAt.toIso8601String(),
    'endedAt': endedAt.toIso8601String(),
    'seconds': seconds,
    if (pages > 0) 'pages': pages,
  };

  static ReadingSession? fromJson(Map<String, Object?>? json) {
    if (json == null) return null;
    final bookId = (json['bookId'] as String? ?? '').trim();
    if (bookId.isEmpty) return null;
    final rawTitle = (json['bookTitle'] as String? ?? '').trim();
    final startedAt = DateTime.tryParse(json['startedAt'] as String? ?? '');
    final endedAt = DateTime.tryParse(json['endedAt'] as String? ?? '');
    final seconds = (json['seconds'] as num?)?.toInt() ?? 0;
    if (startedAt == null || endedAt == null || seconds <= 0) return null;
    final localStart = startedAt.isUtc ? startedAt.toLocal() : startedAt;
    final localEnd = endedAt.isUtc ? endedAt.toLocal() : endedAt;
    return ReadingSession(
      bookId: bookId,
      bookTitle: rawTitle.isEmpty ? '未命名漫画' : rawTitle,
      startedAt: localStart,
      endedAt: localEnd.isBefore(localStart) ? localStart : localEnd,
      seconds: seconds,
      pages: math.max(0, (json['pages'] as num?)?.toInt() ?? 0),
    );
  }
}

/// Daily reading activity used by the bookshelf statistics panel.
/// 书架统计面板使用的每日阅读记录。
class ReadingStats {
  ReadingStats({
    Map<String, int>? dailyPages,
    Map<String, int>? dailySeconds,
    Map<String, Map<String, int>>? dailyBookSeconds,
    Map<String, Map<String, int>>? dailyBookPages,
    List<ReadingSession>? sessions,
    int dailyGoalMinutes = 0,
  }) : dailyPages = dailyPages ?? <String, int>{},
       dailySeconds = dailySeconds ?? <String, int>{},
       dailyBookSeconds = dailyBookSeconds ?? <String, Map<String, int>>{},
       dailyBookPages = dailyBookPages ?? <String, Map<String, int>>{},
       sessions = sessions ?? <ReadingSession>[],
       dailyGoalMinutes = dailyGoalMinutes.clamp(0, maxDailyGoalMinutes);

  /// Pages read per local calendar day, keyed by `yyyy-MM-dd`.
  /// 每个本地自然日阅读的页数，键为 `yyyy-MM-dd`。
  final Map<String, int> dailyPages;

  /// Seconds spent reading per local calendar day, keyed by `yyyy-MM-dd`.
  /// 每个本地自然日的阅读时长（秒），键为 `yyyy-MM-dd`。
  final Map<String, int> dailySeconds;

  /// Seconds spent reading per book per day (`yyyy-MM-dd -> {bookId: seconds}`).
  /// 每天各本漫画的阅读时长（秒），键为 `yyyy-MM-dd -> {bookId: seconds}`。
  final Map<String, Map<String, int>> dailyBookSeconds;

  /// Pages read per book per day (`yyyy-MM-dd -> {bookId: pages}`).
  /// 每天各本漫画的翻页数，键为 `yyyy-MM-dd -> {bookId: pages}`。
  final Map<String, Map<String, int>> dailyBookPages;

  /// Recent reading sessions kept in chronological order.
  /// 近期阅读时段记录，按开始时间升序保存。
  final List<ReadingSession> sessions;

  /// Optional daily reading time goal in minutes (`0` disables the goal).
  /// 每日阅读时长目标（分钟），`0` 表示不设目标。
  int dailyGoalMinutes;

  static const int maxDays = 730;
  static const int maxSessionDays = 90;
  static const int maxSessions = 500;
  static const int maxDailyGoalMinutes = 480;
  static const Duration sessionMergeGap = Duration(minutes: 2);

  static DateTime _day(DateTime date) =>
      DateTime.utc(date.year, date.month, date.day);

  static String dateKey(DateTime date) {
    final day = _day(date);
    final month = day.month.toString().padLeft(2, '0');
    final dayOfMonth = day.day.toString().padLeft(2, '0');
    return '${day.year}-$month-$dayOfMonth';
  }

  static DateTime? parseKey(String key) {
    final parsed = DateTime.tryParse(key);
    return parsed == null ? null : _day(parsed);
  }

  int get totalPages =>
      dailyPages.values.fold<int>(0, (sum, pages) => sum + pages);

  int get totalSeconds =>
      dailySeconds.values.fold<int>(0, (sum, seconds) => sum + seconds);

  int pagesOn(DateTime date) => dailyPages[dateKey(date)] ?? 0;

  int secondsOn(DateTime date) => dailySeconds[dateKey(date)] ?? 0;

  int pagesToday([DateTime? now]) => pagesOn(now ?? DateTime.now());

  int secondsToday([DateTime? now]) => secondsOn(now ?? DateTime.now());

  /// Progress toward [dailyGoalMinutes] for today, in `0.0..1.0`.
  /// 今日相对 [dailyGoalMinutes] 的目标完成度（0.0..1.0）。
  double goalProgressToday([DateTime? now]) {
    if (dailyGoalMinutes <= 0) return 0;
    return (secondsToday(now) / (dailyGoalMinutes * 60)).clamp(0.0, 1.0);
  }

  bool isGoalMetOn(DateTime date) =>
      dailyGoalMinutes > 0 && secondsOn(date) >= dailyGoalMinutes * 60;

  int pagesThisWeek([DateTime? now]) {
    final today = _day(now ?? DateTime.now());
    final start = today.subtract(Duration(days: today.weekday - 1));
    var total = 0;
    for (final entry in dailyPages.entries) {
      final day = parseKey(entry.key);
      if (day == null || day.isBefore(start) || day.isAfter(today)) continue;
      total += entry.value;
    }
    return total;
  }

  int secondsThisWeek([DateTime? now]) {
    final today = _day(now ?? DateTime.now());
    final start = today.subtract(Duration(days: today.weekday - 1));
    var total = 0;
    for (final entry in dailySeconds.entries) {
      final day = parseKey(entry.key);
      if (day == null || day.isBefore(start) || day.isAfter(today)) continue;
      total += entry.value;
    }
    return total;
  }

  /// Oldest-to-newest page counts for the last seven days.
  /// 最近七天（从旧到新）的翻页数。
  List<int> lastSevenDays([DateTime? now]) {
    final today = _day(now ?? DateTime.now());
    return [
      for (var offset = 6; offset >= 0; offset--)
        pagesOn(today.subtract(Duration(days: offset))),
    ];
  }

  /// Oldest-to-newest reading durations (in seconds) for the last seven days.
  /// 最近七天（从旧到新）的阅读时长（秒）。
  List<int> lastSevenDaysSeconds([DateTime? now]) {
    final today = _day(now ?? DateTime.now());
    return [
      for (var offset = 6; offset >= 0; offset--)
        secondsOn(today.subtract(Duration(days: offset))),
    ];
  }

  /// Seconds read for [bookId] on [date].
  /// 指定日期 [date] 阅读 [bookId] 的时长（秒）。
  int bookSecondsOn(String bookId, DateTime date) =>
      dailyBookSeconds[dateKey(date)]?[bookId] ?? 0;

  /// Lifetime seconds recorded for [bookId].
  /// 单本漫画累计记录的阅读时长（秒）。
  int bookSecondsTotal(String bookId) {
    var total = 0;
    for (final map in dailyBookSeconds.values) {
      total += map[bookId] ?? 0;
    }
    return total;
  }

  Map<String, int> bookSecondsByDay(DateTime date) => Map.unmodifiable(
    dailyBookSeconds[dateKey(date)] ?? const <String, int>{},
  );

  Map<String, int> bookPagesByDay(DateTime date) => Map.unmodifiable(
    dailyBookPages[dateKey(date)] ?? const <String, int>{},
  );

  /// Reading sessions on [date], sorted newest-first.
  /// 指定日期的阅读时段记录，按时间倒序排列。
  List<ReadingSession> sessionsOn(DateTime date) {
    final key = dateKey(date);
    final items = [
      for (final session in sessions)
        if (session.dateKey == key) session,
    ];
    items.sort((a, b) => b.endedAt.compareTo(a.endedAt));
    return items;
  }

  /// Local calendar dates that have any recorded pages, duration or sessions,
  /// sorted newest-first.
  /// 存在翻页、时长或时段记录的日期列表，按时间倒序排列。
  List<DateTime> activeDatesDescending() {
    final keys = <String>{
      for (final entry in dailyPages.entries)
        if (entry.value > 0) entry.key,
      for (final entry in dailySeconds.entries)
        if (entry.value > 0) entry.key,
      for (final entry in dailyBookSeconds.entries)
        if (entry.value.values.any((value) => value > 0)) entry.key,
      for (final session in sessions)
        if (session.seconds > 0) session.dateKey,
    };
    final dates = <DateTime>[
      for (final key in keys)
        if (parseKey(key) case final day?)
          DateTime(day.year, day.month, day.day),
    ];
    dates.sort((a, b) => b.compareTo(a));
    return dates;
  }

  /// Calendar years that have recorded reading activity (always includes
  /// [now]'s year), sorted newest-first.
  /// 存在阅读记录的自然年份列表（始终包含当前年份），按降序排列。
  List<int> availableYears([DateTime? now]) {
    final currentYear = (now ?? DateTime.now()).year;
    final years = <int>{currentYear};
    for (final day in activeDatesDescending()) {
      years.add(day.year);
    }
    return years.toList()..sort((a, b) => b.compareTo(a));
  }

  /// Aggregated reading totals across `[start, end]` (inclusive local dates).
  /// 统计起止自然日区间 `[start, end]`（含首尾）内的阅读汇总数据。
  ({int activeDays, int totalSeconds, int totalPages, int goalMetDays})
  summaryBetween(DateTime start, DateTime end) {
    final startUtc = _day(start);
    final endUtc = _day(end);
    if (endUtc.isBefore(startUtc)) {
      return (activeDays: 0, totalSeconds: 0, totalPages: 0, goalMetDays: 0);
    }
    var activeDays = 0;
    var totalSeconds = 0;
    var totalPages = 0;
    var goalMetDays = 0;
    for (
      var cursor = startUtc;
      !cursor.isAfter(endUtc);
      cursor = cursor.add(const Duration(days: 1))
    ) {
      final seconds = secondsOn(cursor);
      final pages = pagesOn(cursor);
      if (seconds > 0 || pages > 0) {
        activeDays++;
        totalSeconds += seconds;
        totalPages += pages;
        if (isGoalMetOn(cursor)) goalMetDays++;
      }
    }
    return (
      activeDays: activeDays,
      totalSeconds: totalSeconds,
      totalPages: totalPages,
      goalMetDays: goalMetDays,
    );
  }

  /// Whether the user read anything on [date], counted by pages or by time.
  /// 当天是否有阅读记录：翻过页或有时长都算。
  bool isActiveOn(DateTime date) => pagesOn(date) > 0 || secondsOn(date) > 0;

  int currentStreak([DateTime? now]) {
    var cursor = _day(now ?? DateTime.now());
    if (!isActiveOn(cursor)) {
      cursor = cursor.subtract(const Duration(days: 1));
    }
    var streak = 0;
    while (isActiveOn(cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  int longestStreak() {
    final days = <DateTime>{
      for (final entry in dailyPages.entries)
        if (entry.value > 0) ?parseKey(entry.key),
      for (final entry in dailySeconds.entries)
        if (entry.value > 0) ?parseKey(entry.key),
    }.toList()..sort();
    if (days.isEmpty) return 0;
    var longest = 1;
    var current = 1;
    for (var index = 1; index < days.length; index++) {
      final gap = days[index].difference(days[index - 1]).inDays;
      if (gap == 1) {
        current++;
        if (current > longest) longest = current;
      } else if (gap > 1) {
        current = 1;
      }
    }
    return longest;
  }

  void addPages(int pages, DateTime when, {String? bookId}) {
    if (pages <= 0) return;
    final key = dateKey(when);
    dailyPages[key] = (dailyPages[key] ?? 0) + pages;
    final cleanId = bookId?.trim() ?? '';
    if (cleanId.isNotEmpty) {
      final bookMap = dailyBookPages.putIfAbsent(key, () => <String, int>{});
      bookMap[cleanId] = (bookMap[cleanId] ?? 0) + pages;
      if (sessions.isNotEmpty) {
        final last = sessions.last;
        if (last.bookId == cleanId &&
            last.dateKey == key &&
            when.difference(last.endedAt).abs() <= sessionMergeGap) {
          sessions[sessions.length - 1] = last.copyWith(
            pages: last.pages + pages,
          );
        }
      }
    }
    _prune(when);
  }

  void addSeconds(
    int seconds,
    DateTime when, {
    String? bookId,
    String? bookTitle,
  }) {
    if (seconds <= 0) return;
    final key = dateKey(when);
    dailySeconds[key] = (dailySeconds[key] ?? 0) + seconds;

    final cleanId = bookId?.trim() ?? '';
    if (cleanId.isNotEmpty) {
      final rawTitle = bookTitle?.trim() ?? '';
      final title = rawTitle.isEmpty ? '未命名漫画' : rawTitle;
      final bookMap = dailyBookSeconds.putIfAbsent(key, () => <String, int>{});
      bookMap[cleanId] = (bookMap[cleanId] ?? 0) + seconds;
      _recordSession(cleanId, title, seconds, when, key);
    }
    _prune(when);
  }

  void _recordSession(
    String bookId,
    String bookTitle,
    int seconds,
    DateTime when,
    String key,
  ) {
    final dayStart = DateTime(when.year, when.month, when.day);
    final rawStart = when.subtract(Duration(seconds: seconds));
    final startedAt = rawStart.isBefore(dayStart) ? dayStart : rawStart;
    final endedAt = when.isBefore(startedAt) ? startedAt : when;

    if (sessions.isNotEmpty) {
      final last = sessions.last;
      if (last.bookId == bookId &&
          last.dateKey == key &&
          !startedAt.isBefore(last.startedAt) &&
          startedAt.difference(last.endedAt) <= sessionMergeGap) {
        sessions[sessions.length - 1] = last.copyWith(
          bookTitle: bookTitle,
          endedAt: endedAt.isAfter(last.endedAt) ? endedAt : last.endedAt,
          seconds: last.seconds + seconds,
        );
        return;
      }
    }

    final entry = ReadingSession(
      bookId: bookId,
      bookTitle: bookTitle,
      startedAt: startedAt,
      endedAt: endedAt,
      seconds: seconds,
    );
    sessions.add(entry);
    if (sessions.length > 1 &&
        sessions[sessions.length - 2].startedAt.isAfter(entry.startedAt)) {
      sessions.sort((a, b) => a.startedAt.compareTo(b.startedAt));
    }
  }

  /// Merges a backup using per-day maxima so restoring the same backup twice
  /// does not double-count pages or reading time.
  /// 按每日最大值合并备份，避免重复恢复同一备份时重复计数。
  void merge(ReadingStats other) {
    for (final entry in other.dailyPages.entries) {
      final existing = dailyPages[entry.key] ?? 0;
      if (entry.value > existing) dailyPages[entry.key] = entry.value;
    }
    for (final entry in other.dailySeconds.entries) {
      final existing = dailySeconds[entry.key] ?? 0;
      if (entry.value > existing) dailySeconds[entry.key] = entry.value;
    }
    _mergeNestedBookMap(dailyBookSeconds, other.dailyBookSeconds);
    _mergeNestedBookMap(dailyBookPages, other.dailyBookPages);
    if (other.sessions.isNotEmpty) {
      final merged = <String, ReadingSession>{};
      for (final session in [...sessions, ...other.sessions]) {
        final key =
            '${session.bookId}|${session.startedAt.millisecondsSinceEpoch}';
        final existing = merged[key];
        if (existing == null ||
            session.seconds > existing.seconds ||
            (session.seconds == existing.seconds &&
                session.pages > existing.pages)) {
          merged[key] = session;
        }
      }
      sessions
        ..clear()
        ..addAll(merged.values)
        ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
    }
    if (dailyGoalMinutes <= 0 && other.dailyGoalMinutes > 0) {
      dailyGoalMinutes = other.dailyGoalMinutes.clamp(0, maxDailyGoalMinutes);
    }

    final allKeys = {
      ...dailyPages.keys,
      ...dailySeconds.keys,
      ...dailyBookSeconds.keys,
      ...dailyBookPages.keys,
      for (final session in sessions) session.dateKey,
    };
    if (allKeys.isNotEmpty) {
      final newest = allKeys.reduce((a, b) => a.compareTo(b) >= 0 ? a : b);
      final date = parseKey(newest);
      if (date != null) _prune(date);
    }
  }

  static void _mergeNestedBookMap(
    Map<String, Map<String, int>> target,
    Map<String, Map<String, int>> source,
  ) {
    for (final dayEntry in source.entries) {
      final destDay = target.putIfAbsent(dayEntry.key, () => <String, int>{});
      for (final bookEntry in dayEntry.value.entries) {
        final existing = destDay[bookEntry.key] ?? 0;
        if (bookEntry.value > existing) destDay[bookEntry.key] = bookEntry.value;
      }
    }
  }

  Map<String, Object?> toJson() => {
    'dailyPages': Map<String, int>.from(dailyPages),
    'dailySeconds': Map<String, int>.from(dailySeconds),
    if (dailyBookSeconds.isNotEmpty)
      'dailyBookSeconds': {
        for (final entry in dailyBookSeconds.entries)
          entry.key: Map<String, int>.from(entry.value),
      },
    if (dailyBookPages.isNotEmpty)
      'dailyBookPages': {
        for (final entry in dailyBookPages.entries)
          entry.key: Map<String, int>.from(entry.value),
      },
    if (sessions.isNotEmpty)
      'sessions': [for (final session in sessions) session.toJson()],
    if (dailyGoalMinutes > 0) 'dailyGoalMinutes': dailyGoalMinutes,
  };

  factory ReadingStats.fromJson(Map<String, Object?>? json) {
    final stats = ReadingStats(
      dailyGoalMinutes: (json?['dailyGoalMinutes'] as num?)?.toInt() ?? 0,
    );
    _decodeDailyMap(json?['dailyPages'], stats.dailyPages);
    _decodeDailyMap(json?['dailySeconds'], stats.dailySeconds);
    _decodeDailyBookMap(json?['dailyBookSeconds'], stats.dailyBookSeconds);
    _decodeDailyBookMap(json?['dailyBookPages'], stats.dailyBookPages);
    final rawSessions = json?['sessions'];
    if (rawSessions is List) {
      for (final item in rawSessions) {
        if (item is! Map) continue;
        final session = ReadingSession.fromJson(
          item.map((key, value) => MapEntry('$key', value)),
        );
        if (session != null) stats.sessions.add(session);
      }
      stats.sessions.sort((a, b) => a.startedAt.compareTo(b.startedAt));
    }
    return stats;
  }

  static void _decodeDailyMap(Object? raw, Map<String, int> target) {
    if (raw is! Map) return;
    for (final entry in raw.entries) {
      final key = '${entry.key}';
      if (parseKey(key) == null) continue;
      final value = (entry.value as num?)?.toInt() ?? 0;
      if (value <= 0) continue;
      target[key] = value;
    }
  }

  static void _decodeDailyBookMap(
    Object? raw,
    Map<String, Map<String, int>> target,
  ) {
    if (raw is! Map) return;
    for (final dayEntry in raw.entries) {
      final dayKey = '${dayEntry.key}';
      if (parseKey(dayKey) == null) continue;
      final booksRaw = dayEntry.value;
      if (booksRaw is! Map) continue;
      final booksMap = <String, int>{};
      for (final bookEntry in booksRaw.entries) {
        final bookId = '${bookEntry.key}'.trim();
        if (bookId.isEmpty) continue;
        final value = (bookEntry.value as num?)?.toInt() ?? 0;
        if (value <= 0) continue;
        booksMap[bookId] = value;
      }
      if (booksMap.isNotEmpty) target[dayKey] = booksMap;
    }
  }

  void _prune(DateTime now) {
    final dayCutoff = _day(now).subtract(const Duration(days: maxDays));
    bool expiredDay(String key) {
      final day = parseKey(key);
      return day == null || day.isBefore(dayCutoff);
    }

    dailyPages.removeWhere((key, _) => expiredDay(key));
    dailySeconds.removeWhere((key, _) => expiredDay(key));
    dailyBookSeconds.removeWhere((key, _) => expiredDay(key));
    dailyBookPages.removeWhere((key, _) => expiredDay(key));

    final sessionCutoff = _day(
      now,
    ).subtract(const Duration(days: maxSessionDays));
    sessions.removeWhere((session) {
      final day = parseKey(session.dateKey);
      return day == null || day.isBefore(sessionCutoff);
    });
    if (sessions.length > maxSessions) {
      sessions.removeRange(0, sessions.length - maxSessions);
    }
  }
}
