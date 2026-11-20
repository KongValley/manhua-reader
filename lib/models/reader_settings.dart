enum ReadingMode {
  horizontal('横向翻页'),
  vertical('纵向滚动');

  const ReadingMode(this.label);

  final String label;

  static ReadingMode fromName(String name) {
    for (final mode in values) {
      if (mode.name == name) return mode;
    }
    return ReadingMode.horizontal;
  }
}

/// Reader preferences, persisted together with the library.
class ReaderSettings {
  ReaderSettings({
    this.mode = ReadingMode.horizontal,
    this.rightToLeft = false,
    this.doublePage = false,
  });

  ReadingMode mode;
  bool rightToLeft;

  /// Show two pages side by side in horizontal mode.
  bool doublePage;

  Map<String, Object?> toJson() => {
    'mode': mode.name,
    'rightToLeft': rightToLeft,
    'doublePage': doublePage,
  };

  factory ReaderSettings.fromJson(Map<String, Object?>? json) {
    if (json == null) return ReaderSettings();
    return ReaderSettings(
      mode: ReadingMode.fromName(json['mode'] as String? ?? ''),
      rightToLeft: json['rightToLeft'] as bool? ?? false,
      doublePage: json['doublePage'] as bool? ?? false,
    );
  }
}
