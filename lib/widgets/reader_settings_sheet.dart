import 'package:flutter/material.dart';

import '../models/reader_settings.dart';
import '../theme/app_theme.dart';
import '../utils/adaptive_layout.dart';

typedef ReaderLayoutPreferences = ({
  ReadingMode mode,
  bool rightToLeft,
  bool doublePage,
  int spreadOffset,
});

/// Bottom sheet with reading comfort and navigation settings.
/// 包含阅读舒适度与翻页方式的底部设置面板。
class ReaderSettingsSheet extends StatefulWidget {
  const ReaderSettingsSheet({
    required this.mode,
    required this.rightToLeft,
    required this.doublePage,
    required this.keepAwake,
    required this.brightness,
    required this.warmth,
    required this.autoTurnSeconds,
    required this.volumeKeys,
    required this.pageTurnAnimation,
    required this.spreadOffset,
    required this.tapZoneWidth,
    required this.autoCrop,
    required this.hasBookPrefs,
    required this.isAndroid,
    this.canDoublePage = true,
    required this.onModeChanged,
    required this.onRightToLeftChanged,
    required this.onDoublePageChanged,
    required this.onKeepAwakeChanged,
    required this.onBrightnessChanged,
    required this.onWarmthChanged,
    required this.onAutoTurnChanged,
    required this.onVolumeKeysChanged,
    required this.onPageTurnAnimationChanged,
    required this.onSpreadOffsetChanged,
    required this.onTapZoneWidthChanged,
    required this.onAutoCropChanged,
    required this.onResetBookPrefs,
    super.key,
  });

  final ReadingMode mode;
  final bool rightToLeft;
  final bool doublePage;
  final bool keepAwake;
  final double brightness;
  final double warmth;
  final int autoTurnSeconds;
  final bool volumeKeys;
  final PageTurnAnimation pageTurnAnimation;
  final int spreadOffset;
  final TapZoneWidth tapZoneWidth;
  final bool autoCrop;

  /// Whether the current book keeps reading preferences of its own.
  /// 当前书是否保存了单独的阅读偏好。
  final bool hasBookPrefs;
  final bool isAndroid;
  final bool canDoublePage;

  final ValueChanged<ReadingMode> onModeChanged;
  final ValueChanged<bool> onRightToLeftChanged;
  final ValueChanged<bool> onDoublePageChanged;
  final ValueChanged<bool> onKeepAwakeChanged;
  final ValueChanged<double> onBrightnessChanged;
  final ValueChanged<double> onWarmthChanged;
  final ValueChanged<int> onAutoTurnChanged;
  final ValueChanged<bool> onVolumeKeysChanged;
  final ValueChanged<PageTurnAnimation> onPageTurnAnimationChanged;
  final ValueChanged<int> onSpreadOffsetChanged;
  final ValueChanged<TapZoneWidth> onTapZoneWidthChanged;
  final ValueChanged<bool> onAutoCropChanged;
  final ReaderLayoutPreferences Function() onResetBookPrefs;

  @override
  State<ReaderSettingsSheet> createState() => _ReaderSettingsSheetState();
}

class _ReaderSettingsSheetState extends State<ReaderSettingsSheet> {
  late bool _hasBookPrefs = widget.hasBookPrefs;
  late ReadingMode _mode = widget.mode;
  late bool _rightToLeft = widget.rightToLeft;
  late bool _doublePage = widget.doublePage;
  late bool _keepAwake = widget.keepAwake;
  late double _brightness = widget.brightness;
  late double _warmth = widget.warmth;
  late int _autoTurnSeconds = widget.autoTurnSeconds;
  late bool _volumeKeys = widget.volumeKeys;
  late PageTurnAnimation _animation = widget.pageTurnAnimation;
  late int _spreadOffset = widget.spreadOffset;
  late TapZoneWidth _tapZoneWidth = widget.tapZoneWidth;
  late bool _autoCrop = widget.autoCrop;

  void _setMode(ReadingMode value) {
    if (value == _mode) return;
    setState(() {
      _mode = value;
      _hasBookPrefs = true;
    });
    widget.onModeChanged(value);
  }

  void _setSpreadOffset(int value) {
    if (value == _spreadOffset) return;
    setState(() {
      _spreadOffset = value;
      _hasBookPrefs = true;
    });
    widget.onSpreadOffsetChanged(value);
  }

  void _setTapZoneWidth(TapZoneWidth value) {
    if (value == _tapZoneWidth) return;
    setState(() => _tapZoneWidth = value);
    widget.onTapZoneWidthChanged(value);
  }

  void _resetBookPrefs() {
    final prefs = widget.onResetBookPrefs();
    setState(() {
      _mode = prefs.mode;
      _rightToLeft = prefs.rightToLeft;
      _doublePage = prefs.doublePage;
      _spreadOffset = prefs.spreadOffset;
      _hasBookPrefs = false;
    });
  }

  void _setAutoCrop(bool value) {
    setState(() => _autoCrop = value);
    widget.onAutoCropChanged(value);
  }

  void _setRightToLeft(bool value) {
    setState(() {
      _rightToLeft = value;
      _hasBookPrefs = true;
    });
    widget.onRightToLeftChanged(value);
  }

  void _setDoublePage(bool value) {
    setState(() {
      _doublePage = value;
      _hasBookPrefs = true;
    });
    widget.onDoublePageChanged(value);
  }

  void _setKeepAwake(bool value) {
    setState(() => _keepAwake = value);
    widget.onKeepAwakeChanged(value);
  }

  void _setBrightness(double value) {
    setState(() => _brightness = value);
    widget.onBrightnessChanged(value);
  }

  void _setWarmth(double value) {
    setState(() => _warmth = value);
    widget.onWarmthChanged(value);
  }

  void _setAutoTurn(int seconds) {
    setState(() => _autoTurnSeconds = seconds);
    widget.onAutoTurnChanged(seconds);
  }

  void _setVolumeKeys(bool value) {
    setState(() => _volumeKeys = value);
    widget.onVolumeKeysChanged(value);
  }

  void _setAnimation(PageTurnAnimation value) {
    setState(() => _animation = value);
    widget.onPageTurnAnimationChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveSheetShell(
      maxWidth: 580,
      fixedHeightFraction: 0.86,
      child: Material(
          type: MaterialType.transparency,
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '阅读设置',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      tooltip: '关闭',
                      icon: const Icon(Icons.close_rounded, size: 21),
                      color: AppColors.textSecondary,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _SectionTitle('阅读方式'),
                      SegmentedButton<ReadingMode>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(
                            value: ReadingMode.horizontal,
                            icon: Icon(Icons.swap_horiz_rounded, size: 18),
                            label: Text('横向翻页'),
                          ),
                          ButtonSegment(
                            value: ReadingMode.vertical,
                            icon: Icon(Icons.swap_vert_rounded, size: 18),
                            label: Text('纵向滚动'),
                          ),
                        ],
                        selected: {_mode},
                        onSelectionChanged: (value) => _setMode(value.first),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 4, bottom: 2),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _hasBookPrefs ? '本书使用单独的阅读设置' : '阅读方式会按书记住',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                            if (_hasBookPrefs)
                              TextButton(
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                  minimumSize: const Size(0, 32),
                                  visualDensity: VisualDensity.compact,
                                  textStyle: const TextStyle(fontSize: 12),
                                ),
                                onPressed: _resetBookPrefs,
                                child: const Text('改回跟随全局'),
                              ),
                          ],
                        ),
                      ),
                      if (_mode == ReadingMode.horizontal) ...[
                        if (widget.canDoublePage) ...[
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('双页模式'),
                            subtitle: Text(
                              _spreadOffset == 0
                                  ? '从首页开始两页一跨'
                                  : _spreadOffset >= 2
                                  ? '前两页单独显示，之后两页一跨'
                                  : '封面单独显示，之后两页一跨',
                            ),
                            value: _doublePage,
                            onChanged: _setDoublePage,
                          ),
                          if (_doublePage)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 0, 6),
                              child: SegmentedButton<int>(
                                showSelectedIcon: false,
                                style: ButtonStyle(
                                  visualDensity: VisualDensity.compact,
                                  textStyle: WidgetStatePropertyAll(
                                    const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  padding: WidgetStatePropertyAll(
                                    const EdgeInsets.symmetric(horizontal: 6),
                                  ),
                                ),
                                segments: const [
                                  ButtonSegment(value: 0, label: Text('首页起成对')),
                                  ButtonSegment(value: 1, label: Text('封面单页')),
                                  ButtonSegment(value: 2, label: Text('前两页单独')),
                                ],
                                selected: {_spreadOffset},
                                onSelectionChanged: (value) =>
                                    _setSpreadOffset(value.first),
                              ),
                            ),
                        ],
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('从右向左'),
                          subtitle: const Text('适合日式漫画的阅读方向'),
                          value: _rightToLeft,
                          onChanged: _setRightToLeft,
                        ),
                      ],
                      const SizedBox(height: 4),
                      const _SectionTitle('点击翻页'),
                      SegmentedButton<TapZoneWidth>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(
                            value: TapZoneWidth.narrow,
                            icon: Icon(
                              Icons.horizontal_distribute_rounded,
                              size: 16,
                            ),
                            label: Text('窄'),
                          ),
                          ButtonSegment(
                            value: TapZoneWidth.medium,
                            icon: Icon(Icons.compare_arrows_rounded, size: 16),
                            label: Text('适中'),
                          ),
                          ButtonSegment(
                            value: TapZoneWidth.wide,
                            icon: Icon(Icons.swap_horiz_rounded, size: 16),
                            label: Text('宽'),
                          ),
                        ],
                        selected: {_tapZoneWidth},
                        onSelectionChanged: (value) =>
                            _setTapZoneWidth(value.first),
                      ),
                      const Padding(
                        padding: EdgeInsets.only(top: 2, bottom: 8),
                        child: Text(
                          '屏幕左右两侧点击翻页区域的宽度，中间点按显示菜单。',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const _SectionTitle('翻页动画'),
                      SegmentedButton<PageTurnAnimation>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(
                            value: PageTurnAnimation.paper,
                            icon: Icon(Icons.auto_stories_rounded, size: 18),
                            label: Text('纸张翻页'),
                          ),
                          ButtonSegment(
                            value: PageTurnAnimation.slide,
                            icon: Icon(Icons.swipe_rounded, size: 18),
                            label: Text('滑动翻页'),
                          ),
                        ],
                        selected: {_animation},
                        onSelectionChanged: (value) =>
                            _setAnimation(value.first),
                      ),
                      const SizedBox(height: 12),
                      const _SectionTitle('显示'),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('屏幕常亮'),
                        subtitle: const Text('阅读时不自动熄屏'),
                        value: _keepAwake,
                        onChanged: _setKeepAwake,
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('自动裁边'),
                        subtitle: const Text('裁掉扫描页四周的空白边距'),
                        value: _autoCrop,
                        onChanged: _setAutoCrop,
                      ),
                      _SettingSlider(
                        title: '画面亮度',
                        valueLabel: '${(_brightness * 100).round()}%',
                        value: _brightness,
                        min: 0.4,
                        max: 1,
                        divisions: 12,
                        onChanged: _setBrightness,
                      ),
                      _SettingSlider(
                        title: '暖色滤镜',
                        valueLabel: _warmth <= 0
                            ? '关闭'
                            : '${(_warmth / 0.4 * 100).round()}%',
                        value: _warmth,
                        min: 0,
                        max: 0.4,
                        divisions: 8,
                        onChanged: _setWarmth,
                      ),
                      const Padding(
                        padding: EdgeInsets.only(top: 2, bottom: 8),
                        child: Text(
                          '只影响漫画画面，不改变系统亮度。',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const _SectionTitle('自动翻页'),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('自动翻页'),
                        subtitle: Text(
                          _autoTurnSeconds == 0
                              ? '当前关闭'
                              : '每 $_autoTurnSeconds 秒翻一页',
                        ),
                        value: _autoTurnSeconds > 0,
                        onChanged: (value) => _setAutoTurn(value ? 10 : 0),
                      ),
                      if (_autoTurnSeconds > 0)
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final seconds in const [5, 10, 15, 30])
                              ChoiceChip(
                                label: Text('$seconds 秒'),
                                selected: _autoTurnSeconds == seconds,
                                onSelected: (_) => _setAutoTurn(seconds),
                              ),
                          ],
                        ),
                      if (widget.isAndroid) ...[
                        const SizedBox(height: 20),
                        const _SectionTitle('按键'),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('音量键翻页'),
                          subtitle: const Text('音量减 = 下一页，音量加 = 上一页'),
                          value: _volumeKeys,
                          onChanged: _setVolumeKeys,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _SettingSlider extends StatelessWidget {
  const _SettingSlider({
    required this.title,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  final String title;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Text(
                valueLabel,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
