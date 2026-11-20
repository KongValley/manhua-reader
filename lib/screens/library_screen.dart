import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/comic_book.dart';
import '../screens/reader_screen.dart';
import '../services/library_repository.dart';
import '../services/pdf_password_cache.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/book_cover.dart';
import '../widgets/pdf_password_dialog.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({required this.repository, super.key});

  final LibraryRepository repository;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  bool _importing = false;
  String _importLabel = '';
  double _importProgress = 0;

  LibraryRepository get _repository => widget.repository;

  Future<void> _pickAndImport() async {
    if (_importing) return;

    List<PlatformFile> files;
    try {
      files = await FilePicker.pickFiles(
        dialogTitle: '选择漫画文件',
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'mobi'],
      );
    } catch (error) {
      _toast('无法打开文件选择器：$error');
      return;
    }

    if (!mounted || files.isEmpty) return;

    setState(() {
      _importing = true;
      _importLabel = '准备导入';
      _importProgress = 0;
    });

    var imported = 0;
    final errors = <String>[];
    for (var i = 0; i < files.length; i++) {
      final file = files[i];
      final name = file.name;
      if (!mounted) return;
      setState(() {
        _importLabel = '正在导入 $name（${i + 1}/${files.length}）';
      });

      void progress(String label, double value) {
        if (mounted) {
          setState(() {
            _importLabel = files.length > 1
                ? '$label（${i + 1}/${files.length}）'
                : label;
            _importProgress = (i + value) / files.length;
          });
        }
      }

      var passwordAttempts = 0;
      String? lastPassword;
      Future<String?> passwordProvider() async {
        if (!mounted) return null;
        final password = await showPdfPasswordDialog(
          context,
          fileName: name,
          errorText: passwordAttempts > 0 ? '密码不正确，请重试' : null,
        );
        if (password != null) {
          passwordAttempts++;
          lastPassword = password;
        }
        return password;
      }

      try {
        final path = file.path;
        final ComicBook book;
        if (path != null && path.isNotEmpty) {
          book = await _repository.importFile(
            path,
            originalName: name,
            onProgress: progress,
            pdfPasswordProvider: passwordProvider,
          );
        } else {
          final totalSize = await file.length();
          if (!mounted) return;
          book = await _repository.importStream(
            originalName: name,
            stream: file.readAsByteStream(),
            totalSize: totalSize,
            onProgress: progress,
            pdfPasswordProvider: passwordProvider,
          );
        }
        PdfPasswordCache.put(book.filePath, lastPassword);
        imported++;
      } on ImportException catch (error) {
        errors.add('$name：${error.message}');
      } catch (error) {
        errors.add('$name：$error');
      }
    }

    if (!mounted) return;
    setState(() {
      _importing = false;
      _importProgress = 0;
    });

    if (imported > 0) {
      _toast(imported == 1 ? '已加入书架' : '已导入 $imported 本漫画');
    }
    if (errors.isNotEmpty) {
      await _showImportErrors(errors);
    }
  }

  Future<void> _openBook(ComicBook book) async {
    if (!_repository.fileExists(book)) {
      _toast('文件已丢失，请重新导入');
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ReaderScreen(book: book, repository: _repository),
      ),
    );
  }

  Future<void> _showBookActions(ComicBook book) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 52,
                      height: 72,
                      child: BookCover(
                        book: book,
                        showProgress: false,
                        borderRadius: const BorderRadius.all(
                          Radius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            book.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${book.format.label} · ${formatPageCount(book.pageCount)} · '
                            '${formatFileSize(book.fileSize)}'
                            '${book.bookmarks.isEmpty ? '' : ' · ${book.bookmarks.length} 个书签'}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.menu_book_rounded),
                  title: Text(book.hasStarted ? '继续阅读' : '开始阅读'),
                  subtitle: book.hasStarted
                      ? Text(
                          '上次读到第 ${book.safeLastPage + 1} 页 · '
                          '${formatActivity(book.lastReadAt)}',
                        )
                      : Text(formatPageCount(book.pageCount)),
                  onTap: () => Navigator.of(context).pop('read'),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.delete_outline_rounded,
                    color: Color(0xFFE57373),
                  ),
                  title: const Text(
                    '删除漫画',
                    style: TextStyle(color: Color(0xFFE57373)),
                  ),
                  subtitle: const Text('只删除应用内的副本，不影响原文件'),
                  onTap: () => Navigator.of(context).pop('delete'),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || action == null) return;
    if (action == 'read') {
      await _openBook(book);
    } else if (action == 'delete') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('删除这本漫画？'),
          content: Text(
            '《${book.title}》及其阅读进度、封面缓存都会被删除。'
            '导入时复制到应用内的文件会一并清理，原文件不受影响。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFB3453F),
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('删除'),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        await _repository.deleteBook(book);
        if (mounted) _toast('已删除《${book.title}》');
      }
    }
  }

  Future<void> _showImportErrors(List<String> errors) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(errors.length == 1 ? '导入失败' : '部分文件导入失败'),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final error in errors)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text('· $error'),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  void _showAbout() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const WarmLogo(size: 34),
            const SizedBox(width: 12),
            const Text('漫阅'),
          ],
        ),
        content: const SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('为手机与平板打造的本地漫画阅读器。'),
              SizedBox(height: 12),
              Text('· 支持 PDF 与 MOBI（漫画型电子书）'),
              Text('· 横向翻页 / 纵向滚动，双击可放大'),
              Text('· 自动保存阅读进度、阅读方向与模式'),
              Text('· 导入的文件只保存在本机'),
              SizedBox(height: 16),
              Text('版本 1.0.0'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_importing,
      child: Scaffold(
        body: Stack(
          children: [
            const Positioned.fill(child: _LibraryBackground()),
            SafeArea(
              bottom: false,
              child: ListenableBuilder(
                listenable: _repository,
                builder: (context, _) {
                  final books = _repository.books;
                  final lastRead = _repository.lastRead;
                  return CustomScrollView(
                    physics: const BouncingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics(),
                    ),
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 20, 12, 0),
                          child: _Header(onAbout: _showAbout),
                        ),
                      ),
                      if (lastRead != null)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                            child: _ContinueReadingCard(
                              book: lastRead,
                              onTap: () => _openBook(lastRead),
                            ),
                          ),
                        ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            20,
                            lastRead == null ? 32 : 30,
                            20,
                            books.isEmpty ? 12 : 14,
                          ),
                          child: Row(
                            children: [
                              Text(
                                '我的书架',
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontSize: 18),
                              ),
                              const SizedBox(width: 10),
                              if (books.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.06),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    '${books.length}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      if (books.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: _EmptyLibrary(onImport: _pickAndImport),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 110),
                          sliver: SliverGrid(
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: _columnCount(context),
                                  mainAxisSpacing: 22,
                                  crossAxisSpacing: 16,
                                  childAspectRatio: 0.57,
                                ),
                            delegate: SliverChildBuilderDelegate((
                              context,
                              index,
                            ) {
                              final book = books[index];
                              return _BookCard(
                                book: book,
                                onTap: () => _openBook(book),
                                onMore: () => _showBookActions(book),
                              );
                            }, childCount: books.length),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
            Positioned(
              right: 20,
              bottom: 24,
              child: SafeArea(
                child: FloatingActionButton.extended(
                  onPressed: _importing ? null : _pickAndImport,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('导入'),
                ),
              ),
            ),
            if (_importing)
              _ImportOverlay(label: _importLabel, progress: _importProgress),
          ],
        ),
      ),
    );
  }

  int _columnCount(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= 1180) return 6;
    if (width >= 940) return 5;
    if (width >= 700) return 4;
    if (width >= 520) return 3;
    return 2;
  }
}

class _LibraryBackground extends StatelessWidget {
  const _LibraryBackground();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF12151C), AppColors.background],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -180,
            right: -120,
            child: IgnorePointer(
              child: Container(
                width: 460,
                height: 460,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.accent.withValues(alpha: 0.13),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 220,
            left: -160,
            child: IgnorePointer(
              child: Container(
                width: 380,
                height: 380,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF6B7BFF).withValues(alpha: 0.07),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onAbout});

  final VoidCallback onAbout;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const WarmLogo(),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '漫阅',
                    style: Theme.of(context).textTheme.headlineMedium
                        ?.copyWith(fontSize: 26),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.accent, AppColors.accentDeep],
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'PDF · MOBI',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF2A1500),
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '把喜欢的漫画，装进口袋',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: onAbout,
          tooltip: '关于漫阅',
          icon: const Icon(Icons.info_outline_rounded, size: 22),
          color: AppColors.textSecondary,
        ),
      ],
    );
  }
}

class _ContinueReadingCard extends StatelessWidget {
  const _ContinueReadingCard({required this.book, required this.onTap});

  final ComicBook book;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.surfaceHigh,
                AppColors.surface.withValues(alpha: 0.92),
              ],
            ),
            border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                SizedBox(
                  width: 64,
                  height: 88,
                  child: BookCover(
                    book: book,
                    showProgress: false,
                    borderRadius: const BorderRadius.all(Radius.circular(12)),
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 5,
                            height: 5,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.accent,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            '继续阅读',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2,
                              color: AppColors.accent,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 7),
                      Text(
                        book.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: book.progress,
                                minHeight: 3,
                                backgroundColor: Colors.white.withValues(
                                  alpha: 0.08,
                                ),
                                valueColor: const AlwaysStoppedAnimation(
                                  AppColors.accent,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '第 ${book.safeLastPage + 1} / ${book.pageCount} 页',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(fontSize: 11),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.06),
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    size: 20,
                    color: AppColors.accent,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BookCard extends StatelessWidget {
  const _BookCard({
    required this.book,
    required this.onTap,
    required this.onMore,
  });

  final ComicBook book;
  final VoidCallback onTap;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final subtitle = book.hasStarted
        ? '${formatProgressLabel(book.safeLastPage, book.pageCount)} · 第 ${book.safeLastPage + 1} 页'
        : '${formatPageCount(book.pageCount)} · 未读';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onMore,
        borderRadius: BorderRadius.circular(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  BookCover(book: book),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: onMore,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black.withValues(alpha: 0.42),
                        ),
                        child: const Icon(
                          Icons.more_horiz_rounded,
                          size: 17,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 9),
            Text(
              book.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontSize: 13.5, height: 1.2),
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontSize: 11,
                color: book.hasStarted
                    ? AppColors.accent.withValues(alpha: 0.9)
                    : AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 2),
          ],
        ),
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.onImport});

  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 110),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 190,
            height: 150,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Transform.rotate(
                  angle: -0.13,
                  child: Container(
                    width: 104,
                    height: 138,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF343B52), Color(0xFF181C26)],
                      ),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.07),
                      ),
                    ),
                  ),
                ),
                Transform.rotate(
                  angle: 0.1,
                  child: Container(
                    width: 104,
                    height: 138,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF4D3526), Color(0xFF241811)],
                      ),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.45),
                          blurRadius: 24,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.auto_stories_rounded,
                      size: 46,
                      color: AppColors.accent.withValues(alpha: 0.55),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 2,
                  right: 10,
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [AppColors.accent, AppColors.accentDeep],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.accentDeep.withValues(alpha: 0.4),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.add_rounded,
                      color: Color(0xFF2A1500),
                      size: 24,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 26),
          Text(
            '书架还是空的',
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontSize: 20),
          ),
          const SizedBox(height: 8),
          const SizedBox(
            width: 300,
            child: Text(
              '导入 PDF 或 MOBI 漫画，阅读进度会自动保存，随时接着看。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.6,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: onImport,
            icon: const Icon(Icons.add_rounded, size: 20),
            label: const Text('导入漫画'),
          ),
        ],
      ),
    );
  }
}

class _ImportOverlay extends StatelessWidget {
  const _ImportOverlay({required this.label, required this.progress});

  final String label;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final value = progress.isFinite ? progress.clamp(0.0, 1.0) : 0.0;
    return Positioned.fill(
      child: AbsorbPointer(
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.62),
          child: Center(
            child: Container(
              width: 320,
              margin: const EdgeInsets.symmetric(horizontal: 28),
              padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 40,
                    offset: const Offset(0, 18),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      WarmLogo(size: 30),
                      SizedBox(width: 10),
                      Text(
                        '导入漫画',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: value,
                      minHeight: 5,
                      backgroundColor: Colors.white.withValues(alpha: 0.08),
                      valueColor: const AlwaysStoppedAnimation(
                        AppColors.accent,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      '${(value * 100).round()}%',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
