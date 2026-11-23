import 'dart:io';

import 'package:flutter/material.dart';

import '../models/comic_book.dart';
import '../theme/app_theme.dart';

/// App logo used in the library and reader.
/// 书架和阅读器共用的应用标志。
class AppLogo extends StatelessWidget {
  const AppLogo({this.size = 46, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/app_icon.png',
      width: size,
      height: size,
      cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).ceil(),
      excludeFromSemantics: true,
    );
  }
}

class FormatBadge extends StatelessWidget {
  const FormatBadge({required this.format, this.compact = false, super.key});

  final ComicFormat format;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Text(
        format.label,
        style: TextStyle(
          fontSize: compact ? 8.5 : 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
          color: Colors.white.withValues(alpha: 0.9),
        ),
      ),
    );
  }
}

/// Green marker shown once a book has been read to its last page.
/// 读到最后一页后显示的绿色完成标记。
class FinishedBadge extends StatelessWidget {
  const FinishedBadge({this.compact = false, super.key});

  final bool compact;

  static const String _tooltip = '已读完 · 已看到最后一页';

  @override
  Widget build(BuildContext context) {
    final icon = Icon(
      Icons.done_rounded,
      size: compact ? 13 : 12,
      color: AppColors.success,
    );

    return Tooltip(
      message: _tooltip,
      child: Semantics(
        label: '已读完',
        child: Container(
          width: compact ? 22 : null,
          height: compact ? 22 : null,
          padding: compact
              ? EdgeInsets.zero
              : const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(compact ? 11 : 7),
            border: Border.all(color: AppColors.success.withValues(alpha: 0.6)),
          ),
          child: compact
              ? icon
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    icon,
                    const SizedBox(width: 3),
                    const Text(
                      '已读完',
                      style: TextStyle(
                        fontSize: 9.5,
                        height: 1,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.2,
                        color: AppColors.success,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Book cover with a graceful fallback when the thumbnail is missing.
/// 书籍封面：缩略图缺失时显示优雅的占位图。
class BookCover extends StatelessWidget {
  const BookCover({
    required this.book,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.showProgress = true,
    this.showFinishedBadge = true,
    super.key,
  });

  final ComicBook book;
  final BorderRadius borderRadius;
  final bool showProgress;
  final bool showFinishedBadge;

  @override
  Widget build(BuildContext context) {
    final coverPath = book.coverPath;
    final coverFile = coverPath == null || coverPath.isEmpty
        ? null
        : File(coverPath);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Small covers only have room for a check mark. Wider cards can show
        // the full label without touching the quick actions.
        // 小封面只显示勾选图标；较宽封面显示完整文字且避开快捷操作。
        final compactBadge = constraints.maxWidth < 156;
        return ClipRRect(
          borderRadius: borderRadius,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _CoverPlaceholder(book: book),
              if (coverFile != null)
                Image.file(
                  coverFile,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.medium,
                  gaplessPlayback: true,
                  errorBuilder: (context, error, stackTrace) =>
                      _CoverPlaceholder(book: book),
                ),
              Positioned(
                left: 8,
                top: 8,
                child: FormatBadge(format: book.format, compact: true),
              ),
              if (showFinishedBadge && book.isFinished)
                Positioned(
                  left: 6,
                  bottom: 8,
                  child: FinishedBadge(compact: compactBadge),
                ),
              if (showProgress)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    height: 3,
                    color: Colors.white.withValues(alpha: 0.12),
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: book.progress <= 0 ? 0.001 : book.progress,
                      child: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [AppColors.accent, AppColors.accentDeep],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: borderRadius,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0.55, 1],
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.18),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CoverPlaceholder extends StatelessWidget {
  const _CoverPlaceholder({required this.book});

  final ComicBook book;

  static const _palettes = [
    [Color(0xFF2B3A55), Color(0xFF141B28)],
    [Color(0xFF4A2E45), Color(0xFF1D121B)],
    [Color(0xFF2E4336), Color(0xFF111C15)],
    [Color(0xFF453620), Color(0xFF1C150B)],
    [Color(0xFF3A2E52), Color(0xFF171223)],
  ];

  @override
  Widget build(BuildContext context) {
    final hash = book.title.codeUnits.fold<int>(0, (sum, c) => sum + c);
    final palette = _palettes[hash % _palettes.length];
    final title = book.title.trim();
    final initial = title.isEmpty
        ? '漫'
        : String.fromCharCode(title.runes.first);

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: palette,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -18,
            bottom: -22,
            child: Icon(
              Icons.auto_stories_rounded,
              size: 118,
              color: Colors.white.withValues(alpha: 0.06),
            ),
          ),
          Center(
            child: Text(
              initial,
              style: TextStyle(
                fontSize: 56,
                fontWeight: FontWeight.w800,
                color: Colors.white.withValues(alpha: 0.22),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
