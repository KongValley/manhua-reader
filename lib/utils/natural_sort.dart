/// Compares two names by text and numeric chunks.
///
/// `page2.jpg` sorts before `page10.jpg` without relying on zero padding.
/// 按文本与数字块比较两个名称。
///
/// `page2.jpg` 会排在 `page10.jpg` 之前，不要求补零。
int naturalCompare(String a, String b) {
  var ai = 0;
  var bi = 0;
  while (ai < a.length && bi < b.length) {
    final aCode = a.codeUnitAt(ai);
    final bCode = b.codeUnitAt(bi);
    final aDigit = _isDigit(aCode);
    final bDigit = _isDigit(bCode);
    if (aDigit && bDigit) {
      var aEnd = ai;
      var bEnd = bi;
      while (aEnd < a.length && _isDigit(a.codeUnitAt(aEnd))) {
        aEnd++;
      }
      while (bEnd < b.length && _isDigit(b.codeUnitAt(bEnd))) {
        bEnd++;
      }
      var aStart = ai;
      var bStart = bi;
      while (aStart < aEnd - 1 && a.codeUnitAt(aStart) == 0x30) {
        aStart++;
      }
      while (bStart < bEnd - 1 && b.codeUnitAt(bStart) == 0x30) {
        bStart++;
      }
      final aLength = aEnd - aStart;
      final bLength = bEnd - bStart;
      if (aLength != bLength) return aLength.compareTo(bLength);
      final compared = a
          .substring(aStart, aEnd)
          .compareTo(b.substring(bStart, bEnd));
      if (compared != 0) return compared;
      ai = aEnd;
      bi = bEnd;
      continue;
    }
    final aLower = _lower(aCode);
    final bLower = _lower(bCode);
    if (aLower != bLower) return aLower.compareTo(bLower);
    ai++;
    bi++;
  }
  return (a.length - ai).compareTo(b.length - bi);
}

bool _isDigit(int code) => code >= 0x30 && code <= 0x39;

int _lower(int code) => code >= 0x41 && code <= 0x5A ? code + 0x20 : code;
