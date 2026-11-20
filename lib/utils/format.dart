import 'dart:math' as math;

/// Formats a byte count for human readers.
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

/// "197 页" / "1,024 页"
String formatPageCount(int count) {
  if (count < 1000) return '$count 页';
  final text = count.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    if (i > 0 && (text.length - i) % 3 == 0) buffer.write(',');
    buffer.write(text[i]);
  }
  return '$buffer 页';
}

/// Relative day labels for the library.
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
int clampPage(int page, int pageCount) {
  if (pageCount <= 0) return 0;
  return math.max(0, math.min(page, pageCount - 1));
}
