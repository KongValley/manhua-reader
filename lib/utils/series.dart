import 'package:path/path.dart' as p;

final _volumePatterns = <RegExp>[
  RegExp(
    r'^(.+?)[\s._·-]*(?:vol(?:ume)?|v)\.?[\s._·-]*\d+(?:\.\d+)?$',
    caseSensitive: false,
  ),
  RegExp(
    r'^(.+?)[\s._·-]*(?:第)?[\s._·-]*(?:\d+|[零〇一二三四五六七八九十百千两]+)[\s._·-]*(?:卷|册|冊|集|部|话|話|期)$',
  ),
  RegExp(
    r'^(.+?)[\s._·-]*(?:chapter|chap|ch)\.?[\s._·-]*\d+$',
    caseSensitive: false,
  ),
  RegExp(r'^(.+?)[\s._·-]+\d+$'),
  RegExp(
    r'^(.+?)\s*[\(\[（【]\s*(?:vol(?:ume)?|v)\.?\s*\d+\s*[\)\]）】]$',
    caseSensitive: false,
  ),
  RegExp(r'^(.+?)\s*[\(\[（【]\s*第?\s*\d+\s*[卷册冊集部]?\s*[\)\]）】]$'),
];

/// Attempts to derive a series name from a title or original file name.
///
/// Examples: `VOL.001` -> `VOL`, `海贼王 第12卷` -> `海贼王`,
/// `One Piece v03` -> `One Piece`. Returns null when no volume suffix exists.
/// 尝试从标题或原始文件名推导系列名。
///
/// 示例：`VOL.001` -> `VOL`，`海贼王 第12卷` -> `海贼王`，
/// `One Piece v03` -> `One Piece`。没有卷号后缀时返回 null。
String? deriveSeriesName(String title, String originalName) {
  final source = title.trim().isNotEmpty
      ? title.trim()
      : p.basenameWithoutExtension(originalName.trim());
  if (source.isEmpty) return null;

  for (final pattern in _volumePatterns) {
    final match = pattern.firstMatch(source);
    if (match == null) continue;
    var base = (match.group(1) ?? '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'^[\s._·-]+|[\s._·-]+$'), '')
        .trim();
    if (base.runes.length < 2) continue;
    if (base.toLowerCase() == source.toLowerCase()) continue;
    return base;
  }
  return null;
}
