import 'package:flutter/material.dart';

import '../services/library_repository.dart';
import '../theme/app_theme.dart';

class ReadingStatsSheet extends StatelessWidget {
  const ReadingStatsSheet({required this.repository, super.key});

  final LibraryRepository repository;

  static const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  String _number(int value) {
    final text = value.toString();
    final buffer = StringBuffer();
    for (var index = 0; index < text.length; index++) {
      if (index > 0 && (text.length - index) % 3 == 0) buffer.write(',');
      buffer.write(text[index]);
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final stats = repository.stats;
    final now = DateTime.now();
    final week = stats.pagesThisWeek(now);
    final today = stats.pagesToday(now);
    final streak = stats.currentStreak(now);
    final longest = stats.longestStreak();
    final days = stats.lastSevenDays(now);
    final maxPages = days.fold<int>(
      0,
      (max, value) => value > max ? value : max,
    );
    final todayDate = DateTime(now.year, now.month, now.day);

    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.86,
        ),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
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
              Row(
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
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontSize: 17),
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
                    icon: const IgnorePointer(
                      child: Icon(Icons.close_rounded, size: 20),
                    ),
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _StatCard(
                      label: '今日阅读',
                      value: _number(today),
                      unit: '页',
                      icon: Icons.today_rounded,
                      accent: AppColors.accent,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _StatCard(
                      label: '本周阅读',
                      value: _number(week),
                      unit: '页',
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
                      value: _number(streak),
                      unit: '天',
                      icon: Icons.local_fire_department_rounded,
                      accent: const Color(0xFFE5A56B),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _StatCard(
                      label: '累计阅读',
                      value: _number(stats.totalPages),
                      unit: '页',
                      icon: Icons.auto_stories_rounded,
                      accent: const Color(0xFF7BC98B),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Text(
                '最近 7 天',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.035),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.06),
                  ),
                ),
                child: SizedBox(
                  height: 150,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            for (var index = 0; index < days.length; index++)
                              Expanded(
                                child: _DayBar(
                                  value: days[index],
                                  maxValue: maxPages,
                                  weekday:
                                      _weekdays[(todayDate.weekday -
                                              7 +
                                              index) %
                                          7],
                                  isToday: index == days.length - 1,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (maxPages == 0)
                        const Center(
                          child: Text(
                            '最近 7 天还没有翻页记录',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
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
                    '按翻页页数统计',
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
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.unit,
    required this.icon,
    required this.accent,
  });

  final String label;
  final String value;
  final String unit;
  final IconData icon;
  final Color accent;

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
        ],
      ),
    );
  }
}

class _DayBar extends StatelessWidget {
  const _DayBar({
    required this.value,
    required this.maxValue,
    required this.weekday,
    required this.isToday,
  });

  final int value;
  final int maxValue;
  final String weekday;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final fraction = maxValue <= 0 ? 0.0 : value / maxValue;
    final height = value <= 0 ? 3.0 : 8.0 + 86.0 * fraction;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            value <= 0 ? '' : '$value',
            style: TextStyle(
              fontSize: 9,
              color: isToday ? AppColors.accent : AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          AnimatedContainer(
            duration: const Duration(milliseconds: 280),
            height: height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: isToday
                    ? [AppColors.accentDeep, AppColors.accent]
                    : [
                        const Color(0xFF6B7BFF).withValues(alpha: 0.35),
                        const Color(0xFF6B7BFF).withValues(alpha: 0.75),
                      ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            weekday,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
              color: isToday ? AppColors.accent : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
