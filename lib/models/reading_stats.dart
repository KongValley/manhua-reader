/// Daily reading activity used by the bookshelf statistics panel.
class ReadingStats {
  ReadingStats({Map<String, int>? dailyPages})
    : dailyPages = dailyPages ?? <String, int>{};

  /// Pages read per local calendar day, keyed by `yyyy-MM-dd`.
  final Map<String, int> dailyPages;

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

  int pagesOn(DateTime date) => dailyPages[dateKey(date)] ?? 0;

  int pagesToday([DateTime? now]) => pagesOn(now ?? DateTime.now());

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

  /// Oldest-to-newest page counts for the last seven days.
  List<int> lastSevenDays([DateTime? now]) {
    final today = _day(now ?? DateTime.now());
    return [
      for (var offset = 6; offset >= 0; offset--)
        pagesOn(today.subtract(Duration(days: offset))),
    ];
  }

  int currentStreak([DateTime? now]) {
    var cursor = _day(now ?? DateTime.now());
    if (pagesOn(cursor) == 0) {
      cursor = cursor.subtract(const Duration(days: 1));
    }
    var streak = 0;
    while (pagesOn(cursor) > 0) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  int longestStreak() {
    final days =
        dailyPages.entries
            .where((entry) => entry.value > 0)
            .map((entry) => parseKey(entry.key))
            .whereType<DateTime>()
            .toList()
          ..sort();
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

  /// Merges a backup using per-day maxima so restoring the same backup twice
  /// does not double-count pages.
  void merge(ReadingStats other) {
    for (final entry in other.dailyPages.entries) {
      final existing = dailyPages[entry.key] ?? 0;
      if (entry.value > existing) dailyPages[entry.key] = entry.value;
    }
    if (dailyPages.isNotEmpty) {
      final newest = dailyPages.keys.reduce(
        (a, b) => a.compareTo(b) >= 0 ? a : b,
      );
      final date = parseKey(newest);
      if (date != null) _prune(date);
    }
  }

  Map<String, Object?> toJson() => {
    'dailyPages': Map<String, int>.from(dailyPages),
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
    return stats;
  }

  void _prune(DateTime now) {
    final cutoff = _day(now).subtract(const Duration(days: maxDays));
    dailyPages.removeWhere((key, _) {
      final day = parseKey(key);
      return day == null || day.isBefore(cutoff);
    });
  }
}
