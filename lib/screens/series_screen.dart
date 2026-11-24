import 'package:flutter/material.dart';

import '../models/comic_book.dart';
import '../services/library_repository.dart';
import '../theme/app_theme.dart';
import '../utils/adaptive_layout.dart';
import '../utils/book_navigation.dart';
import '../widgets/book_cover.dart';
import '../widgets/library_deletion_undo.dart';
import '../widgets/reading_progress_bar.dart';
import 'folder_screen.dart';

class SeriesScreen extends StatelessWidget {
  const SeriesScreen({required this.repository, this.onBookActions, super.key});

  final LibraryRepository repository;
  final ValueChanged<ComicBook>? onBookActions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: LibraryDeletionUndo(repository: repository),
      appBar: AppBar(
        title: const Text('系列合集'),
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListenableBuilder(
        listenable: repository,
        builder: (context, _) {
          final groups = _groupBooks(repository.books);
          if (groups.isEmpty) {
            return const _EmptySeries();
          }
          final width = MediaQuery.sizeOf(context).width;
          final hPad = AdaptiveLayout.horizontalPadding(width);
          final bottomSafe = MediaQuery.paddingOf(context).bottom;
          return GridView.builder(
            padding: EdgeInsets.fromLTRB(hPad, 16, hPad, 30 + bottomSafe),
            physics: const BouncingScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: AdaptiveLayout.seriesColumns(width),
              mainAxisSpacing: 18,
              crossAxisSpacing: 14,
              childAspectRatio: 0.76,
            ),
            itemCount: groups.length,
            itemBuilder: (context, index) {
              final group = groups[index];
              return _SeriesCard(
                name: group.name,
                books: group.books,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) => SeriesDetailScreen(
                      repository: repository,
                      name: group.name,
                      onBookActions: onBookActions,
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _SeriesGroup {
  const _SeriesGroup(this.name, this.books);

  final String name;
  final List<ComicBook> books;
}

List<_SeriesGroup> _groupBooks(List<ComicBook> books) {
  final groups = <String, List<ComicBook>>{};
  final labels = <String, String>{};
  for (final book in books) {
    final series = book.series?.trim();
    if (series == null || series.isEmpty) continue;
    final key = series.toLowerCase();
    labels.putIfAbsent(key, () => series);
    groups.putIfAbsent(key, () => <ComicBook>[]).add(book);
  }
  final result = [
    for (final entry in groups.entries)
      _SeriesGroup(
        labels[entry.key]!,
        entry.value..sort(LibraryRepository.compareVolumes),
      ),
  ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return result;
}

class _SeriesCard extends StatelessWidget {
  const _SeriesCard({
    required this.name,
    required this.books,
    required this.onTap,
  });

  final String name;
  final List<ComicBook> books;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final average = books.isEmpty
        ? 0.0
        : books.fold<double>(0, (sum, book) => sum + book.progress) /
              books.length;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Positioned(
                    left: 18,
                    top: 14,
                    right: 0,
                    bottom: 4,
                    child: Transform.rotate(
                      angle: 0.06,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFF35304A), Color(0xFF181622)],
                          ),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.06),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 8,
                    top: 8,
                    right: 8,
                    bottom: 8,
                    child: Transform.rotate(
                      angle: -0.035,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFF3C2E27), Color(0xFF1D1713)],
                          ),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.06),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 6,
                    top: 6,
                    right: 12,
                    bottom: 12,
                    child: BookCover(
                      book: books.first,
                      showProgress: false,
                      showFinishedBadge: books.every((book) => book.isFinished),
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.62),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.14),
                        ),
                      ),
                      child: Text(
                        '${books.length} 卷',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 9),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontSize: 13.5, height: 1.2),
            ),
            const SizedBox(height: 3),
            Row(
              children: [
                Expanded(
                  child: ReadingProgressBar(value: average, height: 5.5),
                ),
                const SizedBox(width: 8),
                Text(
                  '${(average * 100).round()}%',
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class SeriesDetailScreen extends StatelessWidget {
  const SeriesDetailScreen({
    required this.repository,
    required this.name,
    this.onBookActions,
    super.key,
  });

  final LibraryRepository repository;
  final String name;
  final ValueChanged<ComicBook>? onBookActions;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: repository,
      builder: (context, _) {
        final current = repository.seriesVolumes(name);
        return Scaffold(
          bottomNavigationBar: LibraryDeletionUndo(repository: repository),
          appBar: AppBar(
        title: Text(name),
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                '${current.length} 卷',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
      body: current.isEmpty
          ? const Center(child: Text('系列中没有书籍'))
          : () {
              final width = MediaQuery.sizeOf(context).width;
              final hPad = AdaptiveLayout.horizontalPadding(width);
              final bottomSafe = MediaQuery.paddingOf(context).bottom;
              return GridView.builder(
                padding: EdgeInsets.fromLTRB(hPad, 16, hPad, 30 + bottomSafe),
                physics: const BouncingScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: AdaptiveLayout.bookColumns(width),
                  mainAxisSpacing: 18,
                  crossAxisSpacing: 14,
                  childAspectRatio: 0.58,
                ),
                itemCount: current.length,
                itemBuilder: (context, index) {
                  final book = current[index];
                  final actions = onBookActions;
                  final missing = !repository.fileExists(book);
                  return FolderBookCard(
                    book: book,
                    missing: missing,
                    onMore: actions == null ? null : () => actions(book),
                    onTap: () {
                      if (missing) {
                        if (actions != null) {
                          actions(book);
                          return;
                        }
                        ScaffoldMessenger.of(context)
                          ..hideCurrentSnackBar()
                          ..showSnackBar(
                            const SnackBar(content: Text('文件丢失，请回书架重新定位')),
                          );
                        return;
                      }
                      openComicBook(context, book: book, repository: repository);
                    },
                  );
                },
              );
            }(),
        );
      },
    );
  }
}

class _EmptySeries extends StatelessWidget {
  const _EmptySeries();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.collections_bookmark_outlined,
                size: 32,
                color: Colors.white24,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              '还没有系列',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '在书籍菜单中打开「系列与标签」，\n给同一部漫画的卷设置相同系列名即可合并展示。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                height: 1.6,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.tonal(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('返回书架'),
            ),
          ],
        ),
      ),
    );
  }
}
