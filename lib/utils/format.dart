import 'dart:math' as math;

/// Formats a byte count for human readers.
/// 将字节数格式化为便于阅读的文本。
String formatFileSize(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = value >= 100 || unit == 0 ? 0 : (value >= 10 ? 1 : 1);
  return '${value.toStringAsFixed(digits)} ${units[unit]}';
}

/// Formats a non-negative integer with thousands separators ("1,024").
/// 用千位分隔符格式化整数（如 "1,024"）。
String formatGroupedNumber(int value) {
  final sign = value < 0 ? '-' : '';
  final text = value.abs().toString();
  final buffer = StringBuffer(sign);
  for (var i = 0; i < text.length; i++) {
    if (i > 0 && (text.length - i) % 3 == 0) buffer.write(',');
    buffer.write(text[i]);
  }
  return buffer.toString();
}

/// "197 页" / "1,024 页"
String formatPageCount(int count) => '${formatGroupedNumber(count)} 页';

/// Formats a reading duration in seconds for stats summaries ("45 秒", "12 分钟",
/// "1 小时 20 分钟").
/// 格式化阅读统计时长（如 "45 秒"、"12 分钟"、"1 小时 20 分钟"）。
String formatReadingDuration(int seconds) {
  final safe = math.max(0, seconds);
  if (safe < 60) return '${formatGroupedNumber(safe)} 秒';
  final hours = safe ~/ 3600;
  final minutes = (safe ~/ 60) % 60;
  if (hours == 0) return '$minutes 分钟';
  final hourLabel = '${formatGroupedNumber(hours)} 小时';
  return minutes == 0 ? hourLabel : '$hourLabel $minutes 分钟';
}

/// Compact reading duration for shelf badges and reader pills ("0 分钟", "15 分钟",
/// "1 小时 20 分").
/// 紧凑版阅读时长，用于书架和阅读器提示条（如 "0 分钟"、"15 分钟"、"1 小时 20 分"）。
String formatCompactReadingDuration(int seconds) {
  final safe = math.max(0, seconds);
  if (safe == 0) return '0 分钟';
  if (safe < 60) return '$safe 秒';
  final hours = safe ~/ 3600;
  final minutes = (safe ~/ 60) % 60;
  if (hours == 0) return '$minutes 分钟';
  final hourLabel = '${formatGroupedNumber(hours)} 小时';
  return minutes == 0 ? hourLabel : '$hourLabel $minutes 分';
}

/// Ultra-compact reading duration shown above daily chart bars ("45秒", "12分",
/// "1.5时").
/// 超紧凑时长标签，用于 7 天柱状图柱顶显示（如 "45秒"、"12分"、"1.5时"）。
String formatShortReadingDuration(int seconds) {
  if (seconds <= 0) return '';
  if (seconds < 60) return '$seconds秒';
  if (seconds < 3600) return '${seconds ~/ 60}分';
  final hours = seconds / 3600;
  if (hours >= 10 || seconds % 3600 < 360) {
    return '${hours.floor()}时';
  }
  return '${hours.toStringAsFixed(1)}时';
}

/// Formats a local time range like "21:10–21:38" (or "21:10" within the same
/// minute).
/// 格式化本地阅读时段，如 "21:10–21:38"（同一分钟内显示 "21:10"）。
String formatTimeRange(DateTime start, DateTime end) {
  String hhmm(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  final startText = hhmm(start);
  final endText = hhmm(end);
  return startText == endText ? startText : '$startText–$endText';
}

/// Formats a calendar day for the daily reading log ("今天", "昨天",
/// "11 月 21 日 周六").
/// 格式化每日阅读记录日期标签（如 "今天"、"昨天"、"11 月 21 日 周六"）。
String formatReadingDateLabel(DateTime date, [DateTime? now]) {
  const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  final reference = now ?? DateTime.now();
  final today = DateTime(reference.year, reference.month, reference.day);
  final target = DateTime(date.year, date.month, date.day);
  final diff = today.difference(target).inDays;
  if (diff == 0) return '今天';
  if (diff == 1) return '昨天';
  if (diff == 2) return '前天';
  final weekday = weekdays[target.weekday - 1];
  if (target.year == reference.year) {
    return '${target.month} 月 ${target.day} 日 $weekday';
  }
  return '${target.year} 年 ${target.month} 月 ${target.day} 日 $weekday';
}

/// Relative day labels for the library.
/// 书架使用的相对日期标签。
String formatActivity(DateTime? date) {
  if (date == null) return '尚未阅读';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final that = DateTime(date.year, date.month, date.day);
  final days = today.difference(that).inDays;
  if (days <= 0) return '今天阅读';
  if (days == 1) return '昨天阅读';
  if (days < 7) return '$days 天前阅读';
  if (date.year == now.year) return '${date.month} 月 ${date.day} 日阅读';
  return '${date.year} 年 ${date.month} 月 ${date.day} 日阅读';
}

String formatProgressLabel(int page, int pageCount) {
  if (pageCount <= 0) return '0%';
  final percent = ((page + 1) / pageCount * 100).clamp(0, 100).round();
  return '$percent%';
}

String formatBookmarkTime(DateTime date) {
  final now = DateTime.now();
  String two(int value) => value.toString().padLeft(2, '0');
  final prefix = date.year == now.year ? '' : '${date.year} 年 ';
  return '$prefix${date.month} 月 ${date.day} 日 '
      '${two(date.hour)}:${two(date.minute)}';
}

/// Clamps a page to a valid index for [pageCount].
/// 将页码限制在 [pageCount] 对应的有效索引范围内。
int clampPage(int page, int pageCount) {
  if (pageCount <= 0) return 0;
  return math.max(0, math.min(page, pageCount - 1));
}
