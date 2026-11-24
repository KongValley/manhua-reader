import 'package:flutter/material.dart';

import '../models/reading_stats.dart';
import '../services/library_repository.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import 'reading_progress_bar.dart';

class ReadingStatsSheet extends StatefulWidget {
  const ReadingStatsSheet({required this.repository, super.key});

  final LibraryRepository repository;

  @override
  State<ReadingStatsSheet> createState() => _ReadingStatsSheetState();
}

class _ReadingStatsSheetState extends State<ReadingStatsSheet> {
  static const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];
  static const _goalPresets = [0, 15, 30, 45, 60, 90, 120];
  static const int _initialHistoryLimit = 14;

  bool _showDurationChart = true;
  late DateTime _selectedDate;
  bool _hasManualSelection = false;
  bool _showAllHistory = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDate = _normalizeDay(now);
  }

  static DateTime _normalizeDay(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  DateTime _effectiveExpandedDate(
    ReadingStats stats,
    List<DateTime> activeDays,
    DateTime today,
  ) {
    if (_hasManualSelection) return _selectedDate;
    if (stats.isActiveOn(today)) return today;
    return activeDays.isNotEmpty ? activeDays.first : today;
  }

  void _selectDate(DateTime date) {
    final normalized = _normalizeDay(date);
    setState(() {
      _hasManualSelection = true;
      _selectedDate = normalized;
    });
  }

  Future<void> _pickDailyGoal() async {
    final current = widget.repository.stats.dailyGoalMinutes;
    var chosenPreset = _goalPresets.contains(current) ? current : -1;
    final controller = TextEditingController(
      text: current > 0 ? '$current' : '30',
    );
    String? errorText;

    final result = await showDialog<int>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return AlertDialog(
            title: const Text('每日阅读目标'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '选择每天计划看漫画的时长，统计面板和书架会自动追踪完成情况。',
                    style: TextStyle(fontSize: 12.5, height: 1.5),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final preset in _goalPresets)
                        ChoiceChip(
                          label: Text(preset == 0 ? '不设目标' : '$preset 分钟'),
                          selected: chosenPreset == preset,
                          onSelected: (_) {
                            setDialogState(() {
                              chosenPreset = preset;
                              errorText = null;
                              if (preset > 0) controller.text = '$preset';
                            });
                          },
                        ),
                    ],
                  ),
                  if (chosenPreset != 0) ...[
                    const SizedBox(height: 14),
                    TextField(
                      controller: controller,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: '自定义分钟数',
                        suffixText: '分钟 / 天',
                        helperText: '范围 1–${ReadingStats.maxDailyGoalMinutes} 分钟',
                        errorText: errorText,
                      ),
                      onChanged: (value) {
                        final parsed = int.tryParse(value.trim());
                        setDialogState(() {
                          errorText = null;
                          if (parsed != null && _goalPresets.contains(parsed)) {
                            chosenPreset = parsed;
                          } else {
                            chosenPreset = -1;
                          }
                        });
                      },
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  if (chosenPreset == 0) {
                    Navigator.of(dialogContext).pop(0);
                    return;
                  }
                  final parsed = int.tryParse(controller.text.trim());
                  if (parsed == null ||
                      parsed < 1 ||
                      parsed > ReadingStats.maxDailyGoalMinutes) {
                    setDialogState(() {
                      errorText = '请输入 1 到 ${ReadingStats.maxDailyGoalMinutes} 之间的整数';
                    });
                    return;
                  }
                  Navigator.of(dialogContext).pop(parsed);
                },
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    );
    controller.dispose();
    if (!mounted || result == null) return;
    widget.repository.setDailyReadingGoalMinutes(result);
  }

  String _resolveBookTitle(String bookId, List<ReadingSession> sessions) {
    final live = widget.repository.bookById(bookId);
    if (live != null) return live.title;
    for (final session in sessions) {
      if (session.bookId == bookId && session.bookTitle.trim().isNotEmpty) {
        return session.bookTitle;
      }
    }
    return '已移除的漫画';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.repository,
      builder: (context, _) {
        final stats = widget.repository.stats;
        final now = DateTime.now();
        final todayDate = _normalizeDay(now);
        final weekPages = stats.pagesThisWeek(now);
        final todayPages = stats.pagesToday(now);
        final todaySeconds = stats.secondsToday(now);
        final weekSeconds = stats.secondsThisWeek(now);
        final streak = stats.currentStreak(now);
        final longest = stats.longestStreak();
        final pageDays = stats.lastSevenDays(now);
        final secondDays = stats.lastSevenDaysSeconds(now);
        final activeDays = stats.activeDatesDescending();
        final selectedDay = _effectiveExpandedDate(stats, activeDays, todayDate);

        final maxPages = pageDays.fold<int>(0, (m, v) => v > m ? v : m);
        final maxSeconds = secondDays.fold<int>(0, (m, v) => v > m ? v : m);
        final visibleHistory = _showAllHistory
            ? activeDays
            : activeDays.take(_initialHistoryLimit).toList();

        return SafeArea(
          top: false,
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.88,
            ),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(26),
              ),
              border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _buildHeader(context, streak),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          label: '今日阅读',
                          value: formatGroupedNumber(todayPages),
                          unit: '页',
                          duration: formatReadingDuration(todaySeconds),
                          icon: Icons.today_rounded,
                          accent: AppColors.accent,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _StatCard(
                          label: '本周阅读',
                          value: formatGroupedNumber(weekPages),
                          unit: '页',
                          duration: formatReadingDuration(weekSeconds),
                          icon: Icons.date_range_rounded,
                          accent: const Color(0xFF6B7BFF),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          label: '连续阅读',
                          value: formatGroupedNumber(streak),
                          unit: '天',
                          icon: Icons.local_fire_department_rounded,
                          accent: const Color(0xFFE5A56B),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _StatCard(
                          label: '累计阅读',
                          value: formatGroupedNumber(stats.totalPages),
                          unit: '页',
                          duration: formatReadingDuration(stats.totalSeconds),
                          icon: Icons.auto_stories_rounded,
                          accent: const Color(0xFF7BC98B),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _DailyGoalCard(
                    todaySeconds: todaySeconds,
                    goalMinutes: stats.dailyGoalMinutes,
                    progress: stats.goalProgressToday(now),
                    goalMet: stats.isGoalMetOn(now),
                    onEdit: _pickDailyGoal,
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      const Text(
                        '最近 7 天',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const Spacer(),
                      _ChartModeSwitch(
                        showDuration: _showDurationChart,
                        onChanged: (value) =>
                            setState(() => _showDurationChart = value),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _buildSevenDayChart(
                    stats: stats,
                    todayDate: todayDate,
                    selectedDay: selectedDay,
                    pageDays: pageDays,
                    secondDays: secondDays,
                    maxPages: maxPages,
                    maxSeconds: maxSeconds,
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      const Text(
                        '每日时间记录',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        activeDays.isEmpty
                            ? '暂无记录'
                            : '共 ${activeDays.length} 天有记录',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (activeDays.isEmpty)
                    _buildEmptyHistoryCard()
                  else ...[
                    if (!activeDays.any((day) => _isSameDay(day, selectedDay)))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _buildSelectedEmptyDayBanner(selectedDay, now),
                      ),
                    for (final day in visibleHistory)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _DailyRecordCard(
                          date: day,
                          now: now,
                          seconds: stats.secondsOn(day),
                          pages: stats.pagesOn(day),
                          goalMet: stats.isGoalMetOn(day),
                          expanded: _isSameDay(day, selectedDay),
                          bookSeconds: stats.bookSecondsByDay(day),
                          bookPages: stats.bookPagesByDay(day),
                          sessions: stats.sessionsOn(day),
                          resolveTitle: _resolveBookTitle,
                          onTap: () => _selectDate(day),
                        ),
                      ),
                    if (activeDays.length > _initialHistoryLimit &&
                        !_showAllHistory)
                      Center(
                        child: TextButton(
                          onPressed: () =>
                              setState(() => _showAllHistory = true),
                          child: Text(
                            '查看全部记录（共 ${activeDays.length} 天）',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(
                        Icons.emoji_events_outlined,
                        size: 16,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        longest > 0 ? '最长连续阅读 $longest 天' : '还没有连续阅读记录',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const Spacer(),
                      const Text(
                        '数据仅保存在本地',
                        style: TextStyle(
                          fontSize: 10,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, int streak) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.insights_rounded,
            size: 19,
            color: AppColors.accent,
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '阅读统计',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                streak > 0 ? '连续阅读 $streak 天，继续保持' : '翻开一本漫画，开始记录',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const IgnorePointer(child: Icon(Icons.close_rounded, size: 20)),
          color: AppColors.textSecondary,
        ),
      ],
    );
  }

  Widget _buildSevenDayChart({
    required ReadingStats stats,
    required DateTime todayDate,
    required DateTime selectedDay,
    required List<int> pageDays,
    required List<int> secondDays,
    required int maxPages,
    required int maxSeconds,
  }) {
    final values = _showDurationChart ? secondDays : pageDays;
    final maxValue = _showDurationChart ? maxSeconds : maxPages;
    final selectedSeconds = stats.secondsOn(selectedDay);
    final selectedPages = stats.pagesOn(selectedDay);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 152,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (var index = 0; index < values.length; index++)
                        Expanded(
                          child: Builder(
                            builder: (context) {
                              final date = todayDate.subtract(
                                Duration(days: 6 - index),
                              );
                              final value = values[index];
                              return _DayBar(
                                label: _showDurationChart
                                    ? formatShortReadingDuration(value)
                                    : (value <= 0 ? '' : '$value'),
                                value: value,
                                maxValue: maxValue,
                                weekday: _weekdays[date.weekday - 1],
                                isToday: index == values.length - 1,
                                isSelected: _isSameDay(date, selectedDay),
                                goalMet: stats.isGoalMetOn(date),
                                onTap: () => _selectDate(date),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
                if (maxValue == 0)
                  Center(
                    child: Text(
                      _showDurationChart
                          ? '最近 7 天还没有阅读时长记录'
                          : '最近 7 天还没有翻页记录',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Text(
                  formatReadingDateLabel(selectedDay, todayDate),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '时长 ${formatReadingDuration(selectedSeconds)} · ${formatGroupedNumber(selectedPages)} 页',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                if (stats.isGoalMetOn(selectedDay))
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      '已达标',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.success,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyHistoryCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: const Row(
        children: [
          Icon(
            Icons.history_toggle_off_rounded,
            size: 18,
            color: AppColors.textSecondary,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              '还没有每日阅读时间记录，打开任意漫画开始阅读即可自动计时。',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.45,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedEmptyDayBanner(DateTime selectedDay, DateTime now) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Text(
        '${formatReadingDateLabel(selectedDay, now)}：这一天还没有阅读记录',
        style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.unit,
    required this.icon,
    required this.accent,
    this.duration,
  });

  final String label;
  final String value;
  final String unit;
  final IconData icon;
  final Color accent;
  final String? duration;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: accent),
              const SizedBox(width: 5),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                    color: AppColors.textPrimary,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  unit,
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          if (duration case final readingTime?) ...[
            const SizedBox(height: 4),
            Text(
              '时长 $readingTime',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DailyGoalCard extends StatelessWidget {
  const _DailyGoalCard({
    required this.todaySeconds,
    required this.goalMinutes,
    required this.progress,
    required this.goalMet,
    required this.onEdit,
  });

  final int todaySeconds;
  final int goalMinutes;
  final double progress;
  final bool goalMet;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final hasGoal = goalMinutes > 0;
    final accent = goalMet ? AppColors.success : AppColors.accent;
    final remainingSeconds = (goalMinutes * 60 - todaySeconds).clamp(
      0,
      goalMinutes * 60,
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(15),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.035),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: goalMet
                  ? AppColors.success.withValues(alpha: 0.25)
                  : Colors.white.withValues(alpha: 0.06),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    goalMet ? Icons.verified_rounded : Icons.flag_rounded,
                    size: 15,
                    color: accent,
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    '每日阅读目标',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      hasGoal ? '调整' : '设定目标',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: accent,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (!hasGoal)
                const Text(
                  '设置每天想阅读的分钟数，书架与阅读器会同步展示完成进度',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textSecondary,
                  ),
                )
              else ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${formatCompactReadingDuration(todaySeconds)} / $goalMinutes 分钟',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    Text(
                      goalMet
                          ? '今日目标已达成'
                          : '还差 ${formatCompactReadingDuration(remainingSeconds)}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: goalMet ? FontWeight.w600 : FontWeight.w400,
                        color: goalMet
                            ? AppColors.success
                            : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ReadingProgressBar(
                  value: progress,
                  height: 6,
                  gradient: goalMet ? ReadingProgressBar.successGradient : null,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ChartModeSwitch extends StatelessWidget {
  const _ChartModeSwitch({
    required this.showDuration,
    required this.onChanged,
  });

  final bool showDuration;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ChartModeOption(
            label: '时长',
            selected: showDuration,
            onTap: () => onChanged(true),
          ),
          _ChartModeOption(
            label: '页数',
            selected: !showDuration,
            onTap: () => onChanged(false),
          ),
        ],
      ),
    );
  }
}

class _ChartModeOption extends StatelessWidget {
  const _ChartModeOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.accent.withValues(alpha: 0.18)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? AppColors.accent : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _DayBar extends StatelessWidget {
  const _DayBar({
    required this.label,
    required this.value,
    required this.maxValue,
    required this.weekday,
    required this.isToday,
    required this.isSelected,
    required this.goalMet,
    required this.onTap,
  });

  final String label;
  final int value;
  final int maxValue;
  final String weekday;
  final bool isToday;
  final bool isSelected;
  final bool goalMet;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fraction = maxValue <= 0 ? 0.0 : value / maxValue;
    final height = value <= 0 ? 3.0 : 8.0 + 84.0 * fraction;
    final barColors = goalMet
        ? [const Color(0xFF4BA062), AppColors.success]
        : isToday || isSelected
        ? [AppColors.accentDeep, AppColors.accent]
        : [
            const Color(0xFF6B7BFF).withValues(alpha: 0.35),
            const Color(0xFF6B7BFF).withValues(alpha: 0.78),
          ];

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            SizedBox(
              height: 14,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: goalMet
                        ? AppColors.success
                        : (isToday || isSelected)
                        ? AppColors.accent
                        : AppColors.textSecondary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            AnimatedContainer(
              duration: const Duration(milliseconds: 280),
              height: height,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                border: isSelected
                    ? Border.all(
                        color: Colors.white.withValues(alpha: 0.55),
                        width: 1,
                      )
                    : null,
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: barColors,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              weekday,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: (isToday || isSelected)
                    ? FontWeight.w700
                    : FontWeight.w400,
                color: isSelected
                    ? AppColors.textPrimary
                    : isToday
                    ? AppColors.accent
                    : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DailyRecordCard extends StatelessWidget {
  const _DailyRecordCard({
    required this.date,
    required this.now,
    required this.seconds,
    required this.pages,
    required this.goalMet,
    required this.expanded,
    required this.bookSeconds,
    required this.bookPages,
    required this.sessions,
    required this.resolveTitle,
    required this.onTap,
  });

  final DateTime date;
  final DateTime now;
  final int seconds;
  final int pages;
  final bool goalMet;
  final bool expanded;
  final Map<String, int> bookSeconds;
  final Map<String, int> bookPages;
  final List<ReadingSession> sessions;
  final String Function(String bookId, List<ReadingSession> sessions)
  resolveTitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bookIds = <String>{...bookSeconds.keys, ...bookPages.keys}.toList()
      ..sort((a, b) {
        final secCmp = (bookSeconds[b] ?? 0).compareTo(bookSeconds[a] ?? 0);
        if (secCmp != 0) return secCmp;
        return (bookPages[b] ?? 0).compareTo(bookPages[a] ?? 0);
      });
    final maxBookSeconds = bookIds.fold<int>(
      0,
      (max, id) => (bookSeconds[id] ?? 0) > max ? (bookSeconds[id] ?? 0) : max,
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
          decoration: BoxDecoration(
            color: expanded
                ? Colors.white.withValues(alpha: 0.055)
                : Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: expanded
                  ? AppColors.accent.withValues(alpha: 0.28)
                  : Colors.white.withValues(alpha: 0.06),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            formatReadingDateLabel(date, now),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        if (goalMet) ...[
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.verified_rounded,
                            size: 14,
                            color: AppColors.success,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (pages > 0) ...[
                    Text(
                      '${formatGroupedNumber(pages)} 页',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      seconds > 0
                          ? formatCompactReadingDuration(seconds)
                          : '仅翻页',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.accent,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
              if (expanded) ...[
                const SizedBox(height: 10),
                Divider(
                  height: 1,
                  color: Colors.white.withValues(alpha: 0.07),
                ),
                const SizedBox(height: 10),
                if (bookIds.isEmpty && sessions.isEmpty)
                  Text(
                    seconds > 0
                        ? '共阅读 ${formatReadingDuration(seconds)}（早期记录未按书籍拆分）'
                        : '当天翻页 ${formatGroupedNumber(pages)} 页（暂无有效时长）',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                if (bookIds.isNotEmpty) ...[
                  const Text(
                    '按漫画分布',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 7),
                  for (final bookId in bookIds)
                    _BookDailyBreakdownRow(
                      title: resolveTitle(bookId, sessions),
                      seconds: bookSeconds[bookId] ?? 0,
                      pages: bookPages[bookId] ?? 0,
                      ratio: maxBookSeconds > 0
                          ? (bookSeconds[bookId] ?? 0) / maxBookSeconds
                          : 0,
                    ),
                ],
                if (sessions.isNotEmpty) ...[
                  if (bookIds.isNotEmpty) const SizedBox(height: 8),
                  const Text(
                    '阅读时段',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  for (final session in sessions)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Row(
                        children: [
                          Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.accent.withValues(alpha: 0.8),
                            ),
                          ),
                          const SizedBox(width: 7),
                          Text(
                            formatTimeRange(
                              session.startedAt,
                              session.endedAt,
                            ),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              resolveTitle(session.bookId, sessions),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            formatCompactReadingDuration(session.seconds),
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BookDailyBreakdownRow extends StatelessWidget {
  const _BookDailyBreakdownRow({
    required this.title,
    required this.seconds,
    required this.pages,
    required this.ratio,
  });

  final String title;
  final int seconds;
  final int pages;
  final double ratio;

  @override
  Widget build(BuildContext context) {
    final metrics = [
      if (seconds > 0) formatCompactReadingDuration(seconds),
      if (pages > 0) '$pages 页',
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                metrics,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          if (seconds > 0) ...[
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Container(
                height: 4,
                width: double.infinity,
                color: Colors.white.withValues(alpha: 0.06),
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: ratio.clamp(0.06, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      gradient: const LinearGradient(
                        colors: [AppColors.accentDeep, AppColors.accent],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
