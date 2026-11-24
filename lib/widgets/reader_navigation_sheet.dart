import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../formats/comic_source.dart';
import '../models/bookmark.dart';
import '../models/comic_book.dart';
import '../models/toc_entry.dart';
import '../services/library_repository.dart';
import '../theme/app_theme.dart';
import '../utils/adaptive_layout.dart';
import '../utils/format.dart';
import 'bookmark_editor_dialog.dart';

/// Bottom sheet with chapter TOC, bookmarks and lazy page thumbnails.
/// 包含章节目录、书签和按需加载页面缩略图的底部面板。
class ReaderNavigationSheet extends StatelessWidget {
  const ReaderNavigationSheet({
    required this.source,
    required this.book,
    required this.repository,
    required this.tocFuture,
    required this.currentPage,
    required this.onJump,
    super.key,
  });

  final ComicSource source;
  final ComicBook book;
  final LibraryRepository repository;
  final Future<List<TocEntry>> tocFuture;
  final int currentPage;
  final ValueChanged<int> onJump;

  @override
  Widget build(BuildContext context) {
    return AdaptiveSheetShell(
      maxWidth: 640,
      fixedHeightFraction: 0.84,
      child: DefaultTabController(
          length: 3,
          child: ListenableBuilder(
            listenable: repository,
            builder: (context, _) {
              return Column(
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
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                book.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontSize: 16),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '第 ${currentPage + 1} / ${source.pageCount} 页 · '
                                '${book.bookmarks.length} 个书签',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
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
                  TabBar(
                    labelColor: AppColors.accent,
                    unselectedLabelColor: AppColors.textSecondary,
                    indicatorColor: AppColors.accent,
                    indicatorSize: TabBarIndicatorSize.label,
                    labelStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                    unselectedLabelStyle: const TextStyle(fontSize: 13),
                    tabs: [
                      const Tab(text: '目录'),
                      Tab(text: '书签 ${book.bookmarks.length}'),
                      const Tab(text: '缩略图'),
                    ],
                  ),
                  Divider(
                    height: 1,
                    color: Colors.white.withValues(alpha: 0.06),
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _TocTab(
                          tocFuture: tocFuture,
                          pageCount: source.pageCount,
                          currentPage: currentPage,
                          onJump: onJump,
                        ),
                        _BookmarksTab(
                          book: book,
                          repository: repository,
                          currentPage: currentPage,
                          onJump: onJump,
                        ),
                        _ThumbnailsTab(
                          source: source,
                          currentPage: currentPage,
                          onJump: onJump,
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
      ),
    );
  }
}

class _TocTab extends StatelessWidget {
  const _TocTab({
    required this.tocFuture,
    required this.pageCount,
    required this.currentPage,
    required this.onJump,
  });

  final Future<List<TocEntry>> tocFuture;
  final int pageCount;
  final int currentPage;
  final ValueChanged<int> onJump;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<TocEntry>>(
      future: tocFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: AppColors.accent,
              ),
            ),
          );
        }
        final entries = snapshot.data ?? const <TocEntry>[];
        if (entries.isEmpty) {
          return _PageRangeToc(
            pageCount: pageCount,
            currentPage: currentPage,
            onJump: onJump,
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
          itemCount: entries.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
                child: Text(
                  '共 ${entries.length} 个章节',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              );
            }
            final entry = entries[index - 1];
            final selected = entry.page == currentPage;
            final indent = math.min(entry.level, 4) * 18.0;
            return Padding(
              padding: EdgeInsets.only(left: indent),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => onJump(entry.page),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.accent.withValues(alpha: 0.1)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            entry.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: entry.level == 0 ? 14 : 13,
                              fontWeight: entry.level == 0
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: selected
                                  ? AppColors.accent
                                  : AppColors.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '第 ${entry.page + 1} 页',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _PageRangeToc extends StatelessWidget {
  const _PageRangeToc({
    required this.pageCount,
    required this.currentPage,
    required this.onJump,
  });

  final int pageCount;
  final int currentPage;
  final ValueChanged<int> onJump;

  static const _rangeSize = 20;

  @override
  Widget build(BuildContext context) {
    final ranges = <List<int>>[
      for (var start = 0; start < pageCount; start += _rangeSize)
        [start, math.min(start + _rangeSize, pageCount)],
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surfaceHigh,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 18,
                color: AppColors.accent,
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  '本卷没有内置章节信息。下面按每 20 页生成页码目录，'
                  '也可以使用「书签」标记自己的章节，或在「缩略图」中按画面跳转。',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.55,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text('页码导航', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        for (final range in ranges)
          _PageRangeTile(
            start: range[0],
            end: range[1],
            selected: currentPage >= range[0] && currentPage < range[1],
            onTap: () => onJump(range[0]),
          ),
      ],
    );
  }
}

class _PageRangeTile extends StatelessWidget {
  const _PageRangeTile({
    required this.start,
    required this.end,
    required this.selected,
    required this.onTap,
  });

  final int start;
  final int end;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = end - start <= 1
        ? '第 ${start + 1} 页'
        : '第 ${start + 1} – $end 页';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.accent.withValues(alpha: 0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${start + 1}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: selected
                        ? AppColors.accent
                        : AppColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: selected ? AppColors.accent : AppColors.textPrimary,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BookmarksTab extends StatelessWidget {
  const _BookmarksTab({
    required this.book,
    required this.repository,
    required this.currentPage,
    required this.onJump,
  });

  final ComicBook book;
  final LibraryRepository repository;
  final int currentPage;
  final ValueChanged<int> onJump;

  Future<void> _editBookmark(
    BuildContext context, {
    required int page,
    Bookmark? existing,
  }) async {
    final result = await showBookmarkEditorDialog(
      context,
      page: page,
      existing: existing,
    );
    if (!context.mounted || result == null) return;
    repository.setBookmark(book, page, label: result.label, note: result.note);
  }

  @override
  Widget build(BuildContext context) {
    final bookmarks = book.bookmarks;
    final currentBookmarked = book.isBookmarked(currentPage);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  bookmarks.isEmpty ? '还没有书签' : '共 ${bookmarks.length} 个书签',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: () => _editBookmark(
                  context,
                  page: currentPage,
                  existing: book.bookmarkAt(currentPage),
                ),
                icon: Icon(
                  currentBookmarked
                      ? Icons.edit_rounded
                      : Icons.bookmark_add_rounded,
                  size: 17,
                ),
                label: Text(currentBookmarked ? '编辑当前页' : '收藏当前页'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent.withValues(alpha: 0.12),
                  foregroundColor: AppColors.accent,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: bookmarks.isEmpty
              ? const _BookmarksEmpty()
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                  itemCount: bookmarks.length,
                  separatorBuilder: (context, index) => Divider(
                    height: 1,
                    color: Colors.white.withValues(alpha: 0.05),
                  ),
                  itemBuilder: (context, index) {
                    final bookmark = bookmarks[index];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      isThreeLine: bookmark.hasNote,
                      onTap: () => onJump(bookmark.page),
                      leading: Container(
                        width: 42,
                        height: 42,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.accent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Text(
                          '${bookmark.page + 1}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.accent,
                          ),
                        ),
                      ),
                      title: Text(
                        bookmark.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      subtitle: bookmark.hasNote
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  bookmark.note!,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    height: 1.4,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '收藏于 ${formatBookmarkTime(bookmark.createdAt)}',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(fontSize: 10.5),
                                ),
                              ],
                            )
                          : Text(
                              '收藏于 ${formatBookmarkTime(bookmark.createdAt)}',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(fontSize: 11),
                            ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            onPressed: () => _editBookmark(
                              context,
                              page: bookmark.page,
                              existing: bookmark,
                            ),
                            tooltip: '编辑名称 / 备注',
                            icon: const Icon(
                              Icons.edit_outlined,
                              size: 19,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          IconButton(
                            onPressed: () =>
                                repository.removeBookmark(book, bookmark.page),
                            tooltip: '删除书签',
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              size: 19,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _BookmarksEmpty extends StatelessWidget {
  const _BookmarksEmpty();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.04),
              ),
              child: const Icon(
                Icons.bookmark_border_rounded,
                size: 27,
                color: Colors.white24,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '还没有书签',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '阅读时点击顶部的书签图标可以快速收藏；\n在这里点击「收藏当前页」可以为书签命名、添加备注。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                height: 1.6,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThumbnailsTab extends StatelessWidget {
  const _ThumbnailsTab({
    required this.source,
    required this.currentPage,
    required this.onJump,
  });

  final ComicSource source;
  final int currentPage;
  final ValueChanged<int> onJump;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 820
            ? 8
            : constraints.maxWidth >= 520
            ? 6
            : 4;
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 30),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 8,
            mainAxisSpacing: 12,
            childAspectRatio: 0.68,
          ),
          itemCount: source.pageCount,
          itemBuilder: (context, index) {
            final selected = index == currentPage;
            return GestureDetector(
              onTap: () => onJump(index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                decoration: BoxDecoration(
                  color: const Color(0xFF101218),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: selected
                        ? AppColors.accent
                        : Colors.white.withValues(alpha: 0.09),
                    width: selected ? 2 : 1,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    source.buildThumbnail(context, index),
                    Positioned(
                      right: 4,
                      bottom: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.62),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${index + 1}',
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: Colors.white70,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
