/// Daily reading activity used by the bookshelf statistics panel.
/// 书架统计面板使用的每日阅读记录。
class ReadingStats {
  ReadingStats({Map<String, int>? dailyPages, Map<String, int>? dailySeconds})
    : dailyPages = dailyPages ?? <String, int>{},
      dailySeconds = dailySeconds ?? <String, int>{};

  /// Pages read per local calendar day, keyed by `yyyy-MM-dd`.
  /// 每个本地自然日阅读的页数，键为 `yyyy-MM-dd`。
  final Map<String, int> dailyPages;

  /// Seconds spent reading per local calendar day, keyed by `yyyy-MM-dd`.
  /// 每个本地自然日的阅读时长（秒），键为 `yyyy-MM-dd`。
  final Map<String, int> dailySeconds;

  static const int maxDays = 730;

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

  void addPages(int pages, DateTime when) {
    if (pages <= 0) return;
    final key = dateKey(when);
    dailyPages[key] = (dailyPages[key] ?? 0) + pages;
    _prune(when);
  }

  void addSeconds(int seconds, DateTime when) {
    if (seconds <= 0) return;
    final key = dateKey(when);
    dailySeconds[key] = (dailySeconds[key] ?? 0) + seconds;
    _prune(when);
  }

  /// Merges a backup using per-day maxima so restoring the same backup twice
  /// does not double-count pages.
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
    if (dailyPages.isNotEmpty || dailySeconds.isNotEmpty) {
      final newest = {
        ...dailyPages.keys,
        ...dailySeconds.keys,
      }.reduce((a, b) => a.compareTo(b) >= 0 ? a : b);
      final date = parseKey(newest);
      if (date != null) _prune(date);
    }
  }

  Map<String, Object?> toJson() => {
    'dailyPages': Map<String, int>.from(dailyPages),
    'dailySeconds': Map<String, int>.from(dailySeconds),
  };

  factory ReadingStats.fromJson(Map<String, Object?>? json) {
    final stats = ReadingStats();
    final raw = json?['dailyPages'];
    if (raw is Map) {
      for (final entry in raw.entries) {
        final key = '${entry.key}';
        if (parseKey(key) == null) continue;
        final value = (entry.value as num?)?.toInt() ?? 0;
        if (value <= 0) continue;
        stats.dailyPages[key] = value;
      }
    }
    final rawSeconds = json?['dailySeconds'];
    if (rawSeconds is Map) {
      for (final entry in rawSeconds.entries) {
        final key = '${entry.key}';
        if (parseKey(key) == null) continue;
        final value = (entry.value as num?)?.toInt() ?? 0;
        if (value <= 0) continue;
        stats.dailySeconds[key] = value;
      }
    }
    return stats;
  }

  void _prune(DateTime now) {
    final cutoff = _day(now).subtract(const Duration(days: maxDays));
    bool expired(String key) {
      final day = parseKey(key);
      return day == null || day.isBefore(cutoff);
    }

    dailyPages.removeWhere((key, _) => expired(key));
    dailySeconds.removeWhere((key, _) => expired(key));
  }
}
