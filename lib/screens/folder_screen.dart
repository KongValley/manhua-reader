import 'package:flutter/material.dart';

import '../models/comic_book.dart';
import '../services/library_repository.dart';
import '../theme/app_theme.dart';
import '../utils/book_navigation.dart';
import '../utils/format.dart';
import '../widgets/book_cover.dart';
import '../widgets/folder_name_dialog.dart';
import '../widgets/library_deletion_undo.dart';

class FolderScreen extends StatelessWidget {
  const FolderScreen({
    required this.repository,
    required this.folderId,
    this.onBookActions,
    super.key,
  });

  final LibraryRepository repository;
  final String folderId;
  final ValueChanged<ComicBook>? onBookActions;

  Future<void> _rename(BuildContext context) async {
    final folder = repository.folderById(folderId);
    if (folder == null) return;
    final name = await showFolderNameDialog(context, initialName: folder.name);
    if (name == null || !context.mounted) return;
    final ok = repository.renameFolder(folder, name);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('文件夹名称已存在或没有变化')));
    }
  }

  Future<void> _delete(BuildContext context) async {
    final folder = repository.folderById(folderId);
    if (folder == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除文件夹？'),
        content: const Text('文件夹中的书籍会移回书架根目录，不会删除漫画文件、进度或书签。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除文件夹'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await repository.deleteFolder(folder);
    if (context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: repository,
      builder: (context, _) {
        final folder = repository.folderById(folderId);
        if (folder == null) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('文件夹'),
              backgroundColor: AppColors.background,
              surfaceTintColor: Colors.transparent,
            ),
            body: const Center(child: Text('文件夹已删除')),
          );
        }
        final books =
            repository.books.where((book) => book.folderId == folderId).toList()
              ..sort(LibraryRepository.compareVolumes);
        return Scaffold(
          bottomNavigationBar: LibraryDeletionUndo(repository: repository),
          appBar: AppBar(
            title: Text(folder.name),
            backgroundColor: AppColors.background,
            surfaceTintColor: Colors.transparent,
            actions: [
              IconButton(
                onPressed: () => _rename(context),
                tooltip: '重命名文件夹',
                icon: const IgnorePointer(
                  child: Icon(Icons.edit_outlined, size: 20),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: '文件夹操作',
                onSelected: (value) {
                  if (value == 'delete') _delete(context);
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(
                          Icons.delete_outline_rounded,
                          size: 19,
                          color: Color(0xFFE57373),
                        ),
                        SizedBox(width: 10),
                        Text(
                          '删除文件夹',
                          style: TextStyle(color: Color(0xFFE57373)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Center(
                  child: Text(
                    '${books.length} 本',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ],
          ),
          body: books.isEmpty
              ? const _EmptyFolder()
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
                  physics: const BouncingScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: _columns(context),
                    mainAxisSpacing: 18,
                    crossAxisSpacing: 14,
                    childAspectRatio: 0.58,
                  ),
                  itemCount: books.length,
                  itemBuilder: (context, index) {
                    final book = books[index];
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
                        openComicBook(
                          context,
                          book: book,
                          repository: repository,
                        );
                      },
                    );
                  },
                ),
        );
      },
    );
  }

  int _columns(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= 1180) return 6;
    if (width >= 940) return 5;
    if (width >= 700) return 4;
    if (width >= 520) return 3;
    return 2;
  }
}

class FolderBookCard extends StatelessWidget {
  const FolderBookCard({
    required this.book,
    required this.missing,
    required this.onTap,
    this.onMore,
    super.key,
  });

  final ComicBook book;
  final bool missing;
  final VoidCallback onTap;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onMore,
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  BookCover(book: book),
                  if (missing)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            color: Colors.black.withValues(alpha: 0.48),
                          ),
                          child: const Center(
                            child: Text(
                              '文件丢失',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFE57373),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (onMore != null)
                    Positioned(
                      right: 4,
                      bottom: 4,
                      child: IconButton.filled(
                        onPressed: onMore,
                        tooltip: '管理《${book.title}》',
                        icon: const Icon(Icons.more_horiz_rounded, size: 20),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black.withValues(alpha: 0.72),
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 7),
            Text(
              book.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontSize: 12.5, height: 1.2),
            ),
            const SizedBox(height: 3),
            Text(
              missing
                  ? '文件丢失'
                  : '${formatProgressLabel(book.safeLastPage, book.pageCount)} · '
                        '第 ${book.safeLastPage + 1} 页',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                color: missing
                    ? const Color(0xFFE57373)
                    : book.hasStarted
                    ? AppColors.accent.withValues(alpha: 0.9)
                    : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyFolder extends StatelessWidget {
  const _EmptyFolder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 66,
              height: 66,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.folder_open_outlined,
                size: 30,
                color: Colors.white24,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '文件夹是空的',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '从书架导入文件夹时，其中的书籍会保留在这里。',
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
