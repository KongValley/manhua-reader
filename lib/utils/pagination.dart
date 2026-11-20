/// Spread pairing used by the double-page reader.
///
/// The first page is shown alone (typically the cover), then pages are paired
/// as (1, 2), (3, 4), ... — the convention used by most book readers.
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
int spreadIndexForPage(List<List<int>> spreads, int page) {
  for (var i = 0; i < spreads.length; i++) {
    final spread = spreads[i];
    if (spread.contains(page)) return i;
  }
  return spreads.isEmpty ? 0 : spreads.length - 1;
}
