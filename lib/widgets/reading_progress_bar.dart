import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Rounded, gradient reading-progress bar used across the bookshelf.
class ReadingProgressBar extends StatelessWidget {
  const ReadingProgressBar({
    required this.value,
    this.height = 6,
    this.trackColor,
    this.gradient,
    this.animate = true,
    super.key,
  });

  final double value;
  final double height;
  final Color? trackColor;
  final Gradient? gradient;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final normalized = value.isFinite ? value.clamp(0.0, 1.0) : 0.0;
    final decoration = gradient ?? _defaultGradient;
    final bar = _ProgressBar(
      value: normalized,
      height: height,
      trackColor: trackColor ?? Colors.white.withValues(alpha: 0.08),
      gradient: decoration,
    );
    return Semantics(
      label: '阅读进度',
      value: '${(normalized * 100).round()}%',
      child: animate
          ? TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: normalized),
              duration: const Duration(milliseconds: 420),
              curve: Curves.easeOutCubic,
              builder: (context, animated, _) => _ProgressBar(
                value: animated,
                height: height,
                trackColor: trackColor ?? Colors.white.withValues(alpha: 0.08),
                gradient: decoration,
              ),
            )
          : bar,
    );
  }

  static const _defaultGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xFFFFD08A), AppColors.accent, AppColors.accentDeep],
  );
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({
    required this.value,
    required this.height,
    required this.trackColor,
    required this.gradient,
  });

  final double value;
  final double height;
  final Color trackColor;
  final Gradient gradient;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(height / 2);
    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final fillWidth = constraints.maxWidth * value;
          final visibleWidth = value <= 0
              ? 0.0
              : math.max(fillWidth, height * 0.9);
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: trackColor,
                    borderRadius: radius,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.045),
                    ),
                  ),
                ),
              ),
              if (visibleWidth > 0)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: visibleWidth,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: gradient,
                      borderRadius: radius,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.accentDeep.withValues(alpha: 0.35),
                          blurRadius: 7,
                          spreadRadius: 0.5,
                        ),
                      ],
                    ),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: FractionallySizedBox(
                        widthFactor: 0.72,
                        child: Container(
                          height: math.max(1, height * 0.16),
                          margin: EdgeInsets.only(top: height * 0.18),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(height),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
