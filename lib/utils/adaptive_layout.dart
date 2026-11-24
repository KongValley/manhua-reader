import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Window size categories shared across adaptive screens and modal panels.
/// 用于统一适配手机、折叠屏、平板与桌面端的窗口尺寸分级。
enum ScreenClass { compact, medium, expanded }

/// Responsive layout breakpoints and shared sizing helpers for unified phone,
/// foldable, tablet and desktop builds.
/// 统一的响应式布局工具：在合并后的单包中自适应手机、折叠屏、平板与桌面端。
abstract final class AdaptiveLayout {
  static ScreenClass classify(double width) {
    if (width >= 900) return ScreenClass.expanded;
    if (width >= 600) return ScreenClass.medium;
    return ScreenClass.compact;
  }

  static bool isCompact(BuildContext context) =>
      classify(MediaQuery.sizeOf(context).width) == ScreenClass.compact;

  static bool isWide(BuildContext context) =>
      classify(MediaQuery.sizeOf(context).width) != ScreenClass.compact;

  /// Shelf grid column count across phone, foldable, tablet and desktop widths.
  /// 按屏幕可用宽度计算书架网格列数（2–6 列自适应）。
  static int bookColumns(double width) {
    if (width >= 1180) return 6;
    if (width >= 940) return 5;
    if (width >= 700) return 4;
    if (width >= 520) return 3;
    return 2;
  }

  /// Series overview card columns across breakpoints.
  /// 系列合集卡片列数自适应（2–5 列）。
  static int seriesColumns(double width) {
    if (width >= 1100) return 5;
    if (width >= 850) return 4;
    if (width >= 600) return 3;
    return 2;
  }

  /// Adaptive horizontal screen margin across mobile, tablet and desktop.
  /// 按屏幕宽度调整页面左右留白。
  static double horizontalPadding(double width) {
    if (width >= 960) return 32;
    if (width >= 640) return 24;
    return 20;
  }
}

/// Constrains bottom sheet width on tablets and desktop windows while keeping
/// full-width edge-to-edge sheets on phones.
/// 在手机端保持全宽底部弹窗，在平板和桌面宽屏下居中约束最大宽度，提升观感与操作效率。
class AdaptiveSheetShell extends StatelessWidget {
  const AdaptiveSheetShell({
    required this.child,
    this.maxWidth = 600,
    this.maxHeightFraction = 0.86,
    this.fixedHeightFraction,
    super.key,
  });

  final Widget child;
  final double maxWidth;
  final double maxHeightFraction;
  final double? fixedHeightFraction;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isWide = size.width >= 640;
    final horizontalMargin = isWide ? 24.0 : 0.0;
    final radius = isWide
        ? const BorderRadius.vertical(top: Radius.circular(26))
        : const BorderRadius.vertical(top: Radius.circular(26));
    final heightFraction = fixedHeightFraction;

    final container = Container(
      constraints: heightFraction != null
          ? BoxConstraints(maxWidth: isWide ? maxWidth : double.infinity)
          : BoxConstraints(
              maxWidth: isWide ? maxWidth : double.infinity,
              maxHeight: size.height * maxHeightFraction,
            ),
      height: heightFraction != null ? size.height * heightFraction : null,
      margin: EdgeInsets.symmetric(horizontal: horizontalMargin),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: radius,
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: child,
    );

    return SafeArea(
      top: false,
      child: isWide
          ? Align(
              alignment: Alignment.bottomCenter,
              heightFactor: 1,
              child: container,
            )
          : container,
    );
  }
}
