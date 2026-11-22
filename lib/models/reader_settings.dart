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

enum PageTurnAnimation {
  paper('纸张翻页'),
  slide('滑动翻页');

  const PageTurnAnimation(this.label);

  final String label;

  static PageTurnAnimation fromName(String name) {
    for (final animation in values) {
      if (animation.name == name) return animation;
    }
    return PageTurnAnimation.paper;
  }
}

/// Reader preferences, persisted together with the library.
/// 阅读器偏好设置，与书架一起持久化。
class ReaderSettings {
  ReaderSettings({
    this.mode = ReadingMode.horizontal,
    this.rightToLeft = false,
    this.doublePage = false,
    this.keepAwake = true,
    this.brightness = 1,
    this.warmth = 0,
    this.autoTurnSeconds = 0,
    this.volumeKeys = false,
    this.pageTurnAnimation = PageTurnAnimation.paper,
  });

  ReadingMode mode;
  bool rightToLeft;

  /// Show two pages side by side in horizontal mode.
  /// 横向模式下并排显示两页。
  bool doublePage;

  /// Keep the display awake while reading.
  /// 阅读时保持屏幕常亮。
  bool keepAwake;

  /// Reading overlay brightness, from 0.4 to 1.0.
  /// 阅读遮罩亮度，范围 0.4 到 1.0。
  double brightness;

  /// Warm night-filter strength, from 0 to 0.4.
  /// 暖色夜间滤镜强度，范围 0 到 0.4。
  double warmth;

  /// Automatic page-turn interval. Zero disables it.
  /// 自动翻页间隔，0 表示关闭。
  int autoTurnSeconds;

  /// Whether Android volume keys turn pages while reading.
  /// Android 阅读时是否用音量键翻页。
  bool volumeKeys;

  PageTurnAnimation pageTurnAnimation;

  Map<String, Object?> toJson() => {
    'mode': mode.name,
    'rightToLeft': rightToLeft,
    'doublePage': doublePage,
    'keepAwake': keepAwake,
    'brightness': brightness,
    'warmth': warmth,
    'autoTurnSeconds': autoTurnSeconds,
    'volumeKeys': volumeKeys,
    'pageTurnAnimation': pageTurnAnimation.name,
  };

  factory ReaderSettings.fromJson(Map<String, Object?>? json) {
    if (json == null) return ReaderSettings();
    final autoTurn = (json['autoTurnSeconds'] as num?)?.toInt() ?? 0;
    return ReaderSettings(
      mode: ReadingMode.fromName(json['mode'] as String? ?? ''),
      rightToLeft: json['rightToLeft'] as bool? ?? false,
      doublePage: json['doublePage'] as bool? ?? false,
      keepAwake: json['keepAwake'] as bool? ?? true,
      brightness: ((json['brightness'] as num?)?.toDouble() ?? 1)
          .clamp(0.4, 1.0)
          .toDouble(),
      warmth: ((json['warmth'] as num?)?.toDouble() ?? 0)
          .clamp(0.0, 0.4)
          .toDouble(),
      autoTurnSeconds: const {0, 5, 10, 15, 30}.contains(autoTurn)
          ? autoTurn
          : 0,
      volumeKeys: json['volumeKeys'] as bool? ?? false,
      pageTurnAnimation: PageTurnAnimation.fromName(
        json['pageTurnAnimation'] as String? ?? '',
      ),
    );
  }
}
