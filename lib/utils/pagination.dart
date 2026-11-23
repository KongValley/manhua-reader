/// Largest supported [buildSpreads] offset: two leading single pages cover
/// both pairing parities as well as "cover + blank page" scans.
/// 双页配对支持的最大偏移：前两页单独显示即可覆盖两种配对奇偶，
/// 以及「封面 + 空白页」的扫描件。
const int maxSpreadOffset = 2;

/// Spread pairing used by the double-page reader.
///
/// The first [offset] pages are shown alone (typically the cover), then the
/// remaining pages are paired two by one — the convention used by most book
/// readers. The default offset of 1 pairs pages as (1, 2), (3, 4), ...
/// 双页阅读器使用的跨页配对规则。
///
/// 前 [offset] 页单独显示（通常是封面），其余页面两两一组，与大多数
/// 书籍阅读器的习惯一致。默认偏移 1 时按 (1, 2)、(3, 4)…… 配对。
List<List<int>> buildSpreads(int pageCount, {int offset = 1}) {
  if (pageCount <= 0) return const [];
  final leading = offset.clamp(0, maxSpreadOffset);
  final spreads = <List<int>>[];
  var page = 0;
  while (page < pageCount && page < leading) {
    spreads.add([page]);
    page += 1;
  }
  while (page < pageCount) {
    if (page + 1 < pageCount) {
      spreads.add([page, page + 1]);
      page += 2;
    } else {
      spreads.add([page]);
      page += 1;
    }
  }
  return spreads;
}

/// Returns the spread index that contains [page].
/// 返回包含 [page] 的跨页索引。
int spreadIndexForPage(List<List<int>> spreads, int page) {
  for (var i = 0; i < spreads.length; i++) {
    final spread = spreads[i];
    if (spread.contains(page)) return i;
  }
  return spreads.isEmpty ? 0 : spreads.length - 1;
}
