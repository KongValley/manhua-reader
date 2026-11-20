/// Spread pairing used by the double-page reader.
///
/// The first page is shown alone (typically the cover), then pages are paired
/// as (1, 2), (3, 4), ... — the convention used by most book readers.
/// 双页阅读器使用的跨页配对规则。
///
/// 第一页单独显示（通常是封面），之后按 (1, 2)、(3, 4)…… 两页一组，
/// 与大多数书籍阅读器的习惯一致。
List<List<int>> buildSpreads(int pageCount) {
  if (pageCount <= 0) return const [];
  final spreads = <List<int>>[
    const [0],
  ];
  var page = 1;
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
