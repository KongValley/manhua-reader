enum LibraryViewMode {
  grid('网格'),
  list('列表');

  const LibraryViewMode(this.label);

  final String label;

  static LibraryViewMode fromName(String name) {
    for (final mode in values) {
      if (mode.name == name) return mode;
    }
    return LibraryViewMode.grid;
  }
}

enum LibrarySort {
  recentRead('最近阅读'),
  recentlyAdded('最近导入'),
  title('书名'),
  progress('阅读进度');

  const LibrarySort(this.label);

  final String label;

  static LibrarySort fromName(String name) {
    for (final sort in values) {
      if (sort.name == name) return sort;
    }
    return LibrarySort.recentRead;
  }
}

/// Persistent bookshelf preferences (separate from reader settings).
/// 持久化的书架偏好（独立于阅读器设置）。
class LibrarySettings {
  LibrarySettings({
    this.view = LibraryViewMode.grid,
    this.sort = LibrarySort.recentRead,
  });

  LibraryViewMode view;
  LibrarySort sort;

  Map<String, Object?> toJson() => {'view': view.name, 'sort': sort.name};

  factory LibrarySettings.fromJson(Map<String, Object?>? json) {
    if (json == null) return LibrarySettings();
    return LibrarySettings(
      view: LibraryViewMode.fromName(json['view'] as String? ?? ''),
      sort: LibrarySort.fromName(json['sort'] as String? ?? ''),
    );
  }
}
