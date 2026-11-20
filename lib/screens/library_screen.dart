import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../models/comic_book.dart';
import '../models/library_folder.dart';
import '../models/library_settings.dart';
import '../services/folder_import.dart';
import '../services/library_repository.dart';
import '../services/pdf_password_cache.dart';
import '../services/saf_folder_service.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/backup_sheet.dart';
import '../widgets/book_cover.dart';
import '../widgets/book_organization_dialog.dart';
import '../widgets/folder_name_dialog.dart';
import '../widgets/library_storage_sheet.dart';
import '../widgets/pdf_password_dialog.dart';
import '../widgets/reading_progress_bar.dart';
import '../widgets/reading_stats_sheet.dart';
import 'folder_screen.dart';
import 'reader_screen.dart';
import 'series_screen.dart';

class _ImportCandidate {
  const _ImportCandidate({
    required this.name,
    this.path,
    this.file,
    this.saf,
    this.folderId,
  });

  final String name;
  final String? path;
  final PlatformFile? file;
  final SafFile? saf;
  final String? folderId;
}

enum _ReadFilter {
  all('全部'),
  unread('未读'),
  reading('阅读中'),
  finished('已读完');

  const _ReadFilter(this.label);

  final String label;
}

class _LibraryFilterResult {
  const _LibraryFilterResult({
    required this.sort,
    required this.format,
    required this.readFilter,
    required this.series,
    required this.tag,
    required this.favoritesOnly,
  });

  final LibrarySort sort;
  final ComicFormat? format;
  final _ReadFilter readFilter;
  final String? series;
  final String? tag;
  final bool favoritesOnly;
}

class _ProgressState {
  const _ProgressState(this.label, this.value);

  final String label;
  final double value;
}

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({required this.repository, super.key});

  final LibraryRepository repository;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _selectedIds = {};

  String _query = '';
  ComicFormat? _formatFilter;
  _ReadFilter _readFilter = _ReadFilter.all;
  String? _seriesFilter;
  String? _tagFilter;
  bool _favoritesOnly = false;
  bool _selectionMode = false;
  bool _dragActive = false;

  bool _importing = false;
  bool _cancelImport = false;
  String _importLabel = '';
  double _importProgress = 0;
  int _importSuccess = 0;
  int _importFailure = 0;

  LibraryRepository get _repository => widget.repository;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool get _supportsDesktopDrop =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  bool get _hasActiveFilters =>
      _query.trim().isNotEmpty ||
      _formatFilter != null ||
      _readFilter != _ReadFilter.all ||
      _seriesFilter != null ||
      _tagFilter != null ||
      _favoritesOnly;

  List<ComicBook> _visibleBooks(List<ComicBook> books) {
    final query = _query.trim().toLowerCase();
    final filtered = books.where((book) {
      if (_formatFilter != null && book.format != _formatFilter) return false;
      if (_favoritesOnly && !book.favorite) return false;
      if (_seriesFilter != null &&
          (book.series ?? '').toLowerCase() != _seriesFilter!.toLowerCase()) {
        return false;
      }
      if (_tagFilter != null && !book.tags.contains(_tagFilter)) return false;
      if (!_matchesReadFilter(book)) return false;
      if (query.isNotEmpty && !_repository.matchesSearch(book, query)) {
        return false;
      }
      return true;
    }).toList();

    final sort = _repository.librarySettings.sort;
    filtered.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      switch (sort) {
        case LibrarySort.recentRead:
          return b.lastActivity.compareTo(a.lastActivity);
        case LibrarySort.recentlyAdded:
          return b.addedAt.compareTo(a.addedAt);
        case LibrarySort.title:
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
        case LibrarySort.progress:
          final result = b.progress.compareTo(a.progress);
          return result != 0
              ? result
              : b.lastActivity.compareTo(a.lastActivity);
      }
    });
    return filtered;
  }

  bool _matchesReadFilter(ComicBook book) {
    switch (_readFilter) {
      case _ReadFilter.all:
        return true;
      case _ReadFilter.unread:
        return book.lastReadAt == null;
      case _ReadFilter.reading:
        return book.lastReadAt != null &&
            book.pageCount > 0 &&
            book.safeLastPage < book.pageCount - 1;
      case _ReadFilter.finished:
        return book.lastReadAt != null &&
            book.pageCount > 0 &&
            book.safeLastPage >= book.pageCount - 1;
    }
  }

  void _onSearchChanged(String value) {
    setState(() {
      _query = value;
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  void _clearQuery() {
    _searchController.clear();
    setState(() {
      _query = '';
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  void _clearSearchAndFilters() {
    _searchController.clear();
    setState(() {
      _query = '';
      _formatFilter = null;
      _readFilter = _ReadFilter.all;
      _seriesFilter = null;
      _tagFilter = null;
      _favoritesOnly = false;
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  void _clearFormatFilter() {
    setState(() {
      _formatFilter = null;
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  void _clearReadFilter() {
    setState(() {
      _readFilter = _ReadFilter.all;
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  void _clearSeriesFilter() {
    setState(() {
      _seriesFilter = null;
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  void _clearTagFilter() {
    setState(() {
      _tagFilter = null;
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  void _clearFavoritesFilter() {
    setState(() {
      _favoritesOnly = false;
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  void _toggleView() {
    _repository.setLibraryView(
      _repository.librarySettings.view == LibraryViewMode.grid
          ? LibraryViewMode.list
          : LibraryViewMode.grid,
    );
  }

  Future<void> _showFilterSheet() async {
    final result = await showModalBottomSheet<_LibraryFilterResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _LibraryFilterSheet(
        initialSort: _repository.librarySettings.sort,
        initialFormat: _formatFilter,
        initialReadFilter: _readFilter,
        initialSeries: _seriesFilter,
        initialTag: _tagFilter,
        initialFavoritesOnly: _favoritesOnly,
        seriesCounts: _repository.seriesCounts,
        tagCounts: _repository.tagCounts,
      ),
    );
    if (!mounted || result == null) return;
    _repository.setLibrarySort(result.sort);
    setState(() {
      _formatFilter = result.format;
      _readFilter = result.readFilter;
      _seriesFilter = result.series;
      _tagFilter = result.tag;
      _favoritesOnly = result.favoritesOnly;
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  void _enterSelection(ComicBook book) {
    setState(() {
      _selectionMode = true;
      _selectedIds.add(book.id);
    });
  }

  void _toggleSelection(ComicBook book) {
    setState(() {
      if (!_selectionMode) {
        _selectionMode = true;
        _selectedIds.add(book.id);
        return;
      }
      if (_selectedIds.contains(book.id)) {
        _selectedIds.remove(book.id);
        if (_selectedIds.isEmpty) _selectionMode = false;
      } else {
        _selectedIds.add(book.id);
      }
    });
  }

  void _exitSelection() {
    if (!_selectionMode && _selectedIds.isEmpty) return;
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelectAll(List<ComicBook> visible) {
    final ids = visible.map((book) => book.id).toSet();
    setState(() {
      if (ids.isNotEmpty && _selectedIds.length == ids.length) {
        _selectedIds.clear();
      } else {
        _selectedIds
          ..clear()
          ..addAll(ids);
      }
    });
  }

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
    await _runImportCandidates([
      for (final file in files) _ImportCandidate(name: file.name, file: file),
    ]);
  }

  Future<void> _showImportOptions() async {
    if (_importing) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.insert_drive_file_outlined),
                title: const Text('选择文件'),
                subtitle: const Text('可多选 PDF / MOBI'),
                onTap: () => Navigator.of(context).pop('files'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.create_new_folder_outlined),
                title: const Text('选择文件夹'),
                subtitle: const Text('递归导入文件夹中的 PDF / MOBI'),
                onTap: () => Navigator.of(context).pop('folder'),
              ),
              if (_supportsDesktopDrop)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    '也可以直接把文件或文件夹拖进书架',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'files') {
      await _pickAndImport();
    } else {
      await _pickFolderAndImport();
    }
  }

  Future<void> _pickFolderAndImport() async {
    if (_importing) return;
    if (SafFolderService.isSupported) {
      String? uri;
      List<SafFile> files;
      String folderName;
      try {
        uri = await SafFolderService.pickDirectory();
        if (uri == null) return;
        files = await SafFolderService.listBooks(uri);
        folderName = await SafFolderService.directoryName(uri);
      } catch (error) {
        _toast('无法读取文件夹：$error');
        return;
      }
      if (!mounted) return;
      if (files.isEmpty) {
        _toast('文件夹里没有找到 PDF / MOBI');
        return;
      }
      final folder = _repository.ensureFolder(folderName);
      await _runImportCandidates([
        for (final file in files)
          _ImportCandidate(name: file.name, saf: file, folderId: folder.id),
      ]);
      await _removeFolderIfEmpty(folder);
      return;
    }

    Uri? uri;
    try {
      uri = await FilePicker.pickDirectory(dialogTitle: '选择漫画文件夹');
    } catch (error) {
      _toast('无法打开文件夹选择器：$error');
      return;
    }
    if (!mounted || uri == null) return;
    if (uri.scheme != 'file') {
      _toast('当前平台无法直接读取该文件夹，请改用多选文件');
      return;
    }

    final directory = Directory(uri.toFilePath());
    List<File> files;
    try {
      files = await FolderImportScanner.scanFolder(directory);
    } catch (error) {
      _toast('无法扫描文件夹：$error');
      return;
    }
    if (!mounted) return;
    if (files.isEmpty) {
      _toast('文件夹里没有找到 PDF / MOBI');
      return;
    }
    final folderName = p.basename(directory.path).trim();
    final folder = _repository.ensureFolder(
      folderName.isEmpty ? '导入的文件夹' : folderName,
    );
    await _runImportCandidates([
      for (final file in files)
        _ImportCandidate(
          name: p.basename(file.path),
          path: file.path,
          folderId: folder.id,
        ),
    ]);
    await _removeFolderIfEmpty(folder);
  }

  Future<void> _removeFolderIfEmpty(LibraryFolder folder) async {
    if (!mounted) return;
    if ((_repository.folderCounts[folder.id] ?? 0) == 0) {
      await _repository.deleteFolder(folder);
    }
  }

  Future<void> _importDropped(List<String> paths) async {
    if (_importing || paths.isEmpty) return;
    final candidates = <_ImportCandidate>[];
    final createdFolders = <LibraryFolder>[];
    try {
      for (final path in paths) {
        if (candidates.length >= FolderImportScanner.defaultMaxFiles) break;
        final type = FileSystemEntity.typeSync(path, followLinks: false);
        if (type == FileSystemEntityType.directory) {
          final files = await FolderImportScanner.scanFolder(
            Directory(path),
            maxFiles: FolderImportScanner.defaultMaxFiles - candidates.length,
          );
          if (files.isEmpty) continue;
          final name = p.basename(path).trim();
          final folder = _repository.ensureFolder(
            name.isEmpty ? '导入的文件夹' : name,
          );
          createdFolders.add(folder);
          candidates.addAll([
            for (final file in files)
              _ImportCandidate(
                name: p.basename(file.path),
                path: file.path,
                folderId: folder.id,
              ),
          ]);
        } else if (type == FileSystemEntityType.file &&
            FolderImportScanner.isImportableName(path)) {
          candidates.add(_ImportCandidate(name: p.basename(path), path: path));
        }
      }
    } catch (error) {
      _toast('无法读取拖入的文件：$error');
      return;
    }
    if (!mounted) return;
    if (candidates.isEmpty) {
      _toast('拖入的内容里没有 PDF / MOBI');
      return;
    }
    await _runImportCandidates(candidates);
    for (final folder in createdFolders) {
      await _removeFolderIfEmpty(folder);
    }
  }

  Future<void> _runImportCandidates(List<_ImportCandidate> candidates) async {
    if (candidates.isEmpty || _importing) return;
    _searchController.clear();
    setState(() {
      _query = '';
      _formatFilter = null;
      _readFilter = _ReadFilter.all;
      _seriesFilter = null;
      _tagFilter = null;
      _favoritesOnly = false;
      _selectionMode = false;
      _selectedIds.clear();
      _importing = true;
      _cancelImport = false;
      _importLabel = '准备导入';
      _importProgress = 0;
      _importSuccess = 0;
      _importFailure = 0;
    });

    var imported = 0;
    var cancelled = false;
    final errors = <String>[];
    for (var i = 0; i < candidates.length; i++) {
      if (_cancelImport) {
        cancelled = true;
        break;
      }
      final candidate = candidates[i];
      final name = candidate.name;
      if (!mounted) return;
      setState(() {
        _importLabel = '正在导入 $name（${i + 1}/${candidates.length}）';
        _importProgress = i / candidates.length;
      });

      void progress(String label, double value) {
        if (mounted) {
          setState(() {
            _importLabel = candidates.length > 1
                ? '$label（${i + 1}/${candidates.length}）'
                : label;
            _importProgress = (i + value) / candidates.length;
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

      String? stagedPath;
      try {
        final ComicBook book;
        final saf = candidate.saf;
        final picked = candidate.file;
        if (saf != null) {
          progress('正在准备 $name', 0);
          stagedPath = await SafFolderService.copyToCache(saf);
          if (stagedPath == null || stagedPath.isEmpty) {
            throw ImportException('无法读取文件夹中的文件');
          }
          book = await _repository.importFile(
            stagedPath,
            originalName: name,
            folderId: candidate.folderId,
            onProgress: progress,
            pdfPasswordProvider: passwordProvider,
          );
        } else if (picked != null) {
          final path = picked.path;
          if (path != null && path.isNotEmpty) {
            book = await _repository.importFile(
              path,
              originalName: name,
              folderId: candidate.folderId,
              onProgress: progress,
              pdfPasswordProvider: passwordProvider,
            );
          } else {
            final totalSize = await picked.length();
            if (!mounted) return;
            book = await _repository.importStream(
              originalName: name,
              stream: picked.readAsByteStream(),
              totalSize: totalSize,
              folderId: candidate.folderId,
              onProgress: progress,
              pdfPasswordProvider: passwordProvider,
            );
          }
        } else if (candidate.path != null) {
          book = await _repository.importFile(
            candidate.path!,
            originalName: name,
            folderId: candidate.folderId,
            onProgress: progress,
            pdfPasswordProvider: passwordProvider,
          );
        } else {
          throw ImportException('无法读取文件');
        }
        PdfPasswordCache.put(book.filePath, lastPassword);
        imported++;
      } on ImportException catch (error) {
        errors.add('$name：${error.message}');
      } catch (error) {
        errors.add('$name：$error');
      } finally {
        if (stagedPath != null) {
          try {
            final temp = File(stagedPath);
            if (await temp.exists()) await temp.delete();
          } catch (_) {}
        }
      }
      if (mounted) {
        setState(() {
          _importSuccess = imported;
          _importFailure = errors.length;
        });
      }
    }

    if (!mounted) return;
    setState(() {
      _importing = false;
      _cancelImport = false;
      _importProgress = 0;
    });

    if (imported > 0 || cancelled) {
      final parts = <String>[];
      if (imported > 0) parts.add('已导入 $imported 本');
      if (cancelled) parts.add('已取消剩余文件');
      _toast(parts.join('，'));
    }
    if (errors.isNotEmpty) {
      await _showImportErrors(errors);
    }
  }

  void _cancelRemainingImports() {
    if (_cancelImport) return;
    setState(() {
      _cancelImport = true;
      _importLabel = '正在取消剩余导入…';
    });
  }

  Future<void> _openBook(ComicBook book) async {
    if (_selectionMode) {
      _toggleSelection(book);
      return;
    }
    if (!_repository.fileExists(book)) {
      await _showBookActions(book);
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ReaderScreen(book: book, repository: _repository),
      ),
    );
  }

  Future<void> _showBookActions(ComicBook book) async {
    final missing = !_repository.fileExists(book);
    final organization = [
      if (book.series != null) '系列：${book.series}',
      if (book.tags.isNotEmpty) book.tags.map((tag) => '#$tag').join(' '),
    ].join(' · ');
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: SingleChildScrollView(
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
                if (missing) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE57373).withValues(alpha: 0.09),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFFE57373).withValues(alpha: 0.22),
                      ),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.folder_off_outlined,
                          size: 18,
                          color: Color(0xFFE57373),
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '文件已丢失。可以重新定位一个 PDF/MOBI 文件，或删除此条目。',
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.5,
                              color: Color(0xFFE57373),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).pop('favorite'),
                        icon: IgnorePointer(
                          child: Icon(
                            book.favorite
                                ? Icons.star_rounded
                                : Icons.star_border_rounded,
                            size: 17,
                            color: book.favorite
                                ? AppColors.accent
                                : AppColors.textSecondary,
                          ),
                        ),
                        label: Text(book.favorite ? '已收藏' : '收藏'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: book.favorite
                              ? AppColors.accent
                              : AppColors.textPrimary,
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).pop('pin'),
                        icon: IgnorePointer(
                          child: Icon(
                            book.pinned
                                ? Icons.push_pin_rounded
                                : Icons.push_pin_outlined,
                            size: 17,
                            color: book.pinned
                                ? AppColors.accent
                                : AppColors.textSecondary,
                          ),
                        ),
                        label: Text(book.pinned ? '已置顶' : '置顶'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: book.pinned
                              ? AppColors.accent
                              : AppColors.textPrimary,
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                if (!missing)
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
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('重命名'),
                  subtitle: const Text('只修改书架显示名称，不改变原文件'),
                  onTap: () => Navigator.of(context).pop('rename'),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.collections_bookmark_outlined),
                  title: const Text('系列与标签'),
                  subtitle: Text(
                    organization.isEmpty ? '用于系列合并展示与标签筛选' : organization,
                  ),
                  onTap: () => Navigator.of(context).pop('organize'),
                ),
                if (missing)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.folder_open_rounded),
                    title: const Text('重新定位文件'),
                    subtitle: const Text('选择一个替换文件，保留阅读进度和书签'),
                    onTap: () => Navigator.of(context).pop('relink'),
                  )
                else ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.photo_outlined),
                    title: const Text('更换封面'),
                    subtitle: const Text('从本地图片选择自定义封面'),
                    onTap: () => Navigator.of(context).pop('customCover'),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.image_outlined),
                    title: const Text('重新生成封面'),
                    subtitle: Text(
                      book.customCover ? '恢复为自动生成的第一页封面' : '封面损坏或想更新时使用',
                    ),
                    onTap: () => Navigator.of(context).pop('cover'),
                  ),
                ],
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
    switch (action) {
      case 'favorite':
        _repository.toggleFavorite(book);
        _toast(book.favorite ? '已收藏《${book.title}》' : '已取消收藏');
      case 'pin':
        _repository.togglePinned(book);
        _toast(book.pinned ? '已置顶《${book.title}》' : '已取消置顶');
      case 'read':
        await _openBook(book);
      case 'rename':
        await _showRenameDialog(book);
      case 'organize':
        await _showOrganizationDialog(book);
      case 'relink':
        await _relinkBook(book);
      case 'customCover':
        await _pickCustomCover(book);
      case 'cover':
        await _regenerateCover(book);
      case 'delete':
        await _deleteBook(book);
    }
  }

  Future<void> _showOrganizationDialog(ComicBook book) async {
    final result = await showBookOrganizationDialog(
      context,
      book: book,
      knownSeries: _repository.seriesNames,
      knownTags: _repository.tagNames,
    );
    if (!mounted || result == null) return;
    _repository.setBookOrganization(
      book,
      series: result.series,
      tags: result.tags,
    );
    _toast('系列与标签已更新');
  }

  Future<void> _pickCustomCover(ComicBook book) async {
    PlatformFile? picked;
    try {
      picked = await FilePicker.pickFile(
        dialogTitle: '选择封面图片',
        type: FileType.image,
      );
    } catch (error) {
      _toast('无法打开图片选择器：$error');
      return;
    }
    if (picked == null || !mounted) return;
    try {
      final bytes = await picked.readAsBytes();
      final ok = await _runWithProgress<bool>(
        '正在生成封面…',
        (_) => _repository.setCustomCover(book, bytes),
      );
      if (!mounted) return;
      _toast(ok == true ? '封面已更新' : '封面生成失败，请换一张图片');
    } catch (error) {
      if (mounted) _toast('封面更新失败：$error');
    }
  }

  Future<void> _showRenameDialog(ComicBook book) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => _RenameDialog(initialTitle: book.title),
    );
    if (!mounted || result == null) return;
    _repository.renameBook(book, result);
    _toast('已重命名为《${book.title}》');
  }

  Future<void> _regenerateCover(ComicBook book) async {
    if (!_repository.fileExists(book)) {
      _toast('文件已丢失；请先重新定位文件');
      return;
    }
    var attempts = 0;
    String? lastPassword;
    Future<String?> provider() async {
      attempts++;
      if (attempts == 1) {
        final cached = PdfPasswordCache.get(book.filePath);
        if (cached != null) {
          lastPassword = cached;
          return cached;
        }
      }
      if (!mounted) return null;
      final password = await showPdfPasswordDialog(
        context,
        fileName: book.title,
        errorText: attempts > 1 ? '密码不正确，请重试' : null,
      );
      if (password != null) lastPassword = password;
      return password;
    }

    try {
      final ok = await _runWithProgress<bool>(
        '正在生成封面…',
        (onProgress) => _repository.regenerateCover(
          book,
          pdfPasswordProvider: provider,
          onProgress: onProgress,
        ),
      );
      if (!mounted) return;
      if (ok == true) {
        PdfPasswordCache.put(book.filePath, lastPassword);
        _toast('封面已更新');
      } else {
        _toast('封面生成失败（可能需要密码或文件损坏）');
      }
    } catch (error) {
      if (mounted) _toast('封面生成失败：$error');
    }
  }

  Future<void> _relinkBook(ComicBook book) async {
    PlatformFile? picked;
    try {
      picked = await FilePicker.pickFile(
        dialogTitle: '选择用于替换的 ${book.format.label} 文件',
        type: FileType.custom,
        allowedExtensions: [book.format.extension],
      );
    } catch (error) {
      _toast('无法打开文件选择器：$error');
      return;
    }
    if (picked == null || !mounted) return;
    final selected = picked;

    final oldPath = book.filePath;
    var attempts = 0;
    String? lastPassword;
    Future<String?> provider() async {
      attempts++;
      if (attempts == 1) {
        final cached = PdfPasswordCache.get(oldPath);
        if (cached != null) {
          lastPassword = cached;
          return cached;
        }
      }
      if (!mounted) return null;
      final password = await showPdfPasswordDialog(
        context,
        fileName: selected.name,
        errorText: attempts > 1 ? '密码不正确，请重试' : null,
      );
      if (password != null) lastPassword = password;
      return password;
    }

    File? staged;
    try {
      final result = await _runWithProgress<ComicBook>('正在重新定位文件…', (
        onProgress,
      ) async {
        String sourcePath;
        final path = selected.path;
        if (path != null && path.isNotEmpty) {
          sourcePath = path;
        } else {
          final total = await selected.length();
          staged = File(
            p.join(
              _repository.paths.cacheDir.path,
              'relink_${DateTime.now().microsecondsSinceEpoch}.${book.format.extension}',
            ),
          );
          final sink = staged!.openWrite();
          var copied = 0;
          try {
            await for (final chunk in selected.readAsByteStream()) {
              sink.add(chunk);
              copied += chunk.length;
              final fraction = total != null && total > 0
                  ? (copied / total).clamp(0.0, 1.0)
                  : 0.0;
              onProgress('正在准备文件', fraction * 0.3);
            }
          } finally {
            await sink.close();
          }
          sourcePath = staged!.path;
        }
        return await _repository.relinkFile(
          book,
          sourcePath,
          pdfPasswordProvider: provider,
          onProgress: (label, value) => onProgress(label, 0.3 + value * 0.7),
        );
      });
      if (!mounted) return;
      if (result != null) {
        PdfPasswordCache.remove(oldPath);
        PdfPasswordCache.put(book.filePath, lastPassword);
        _toast('已重新定位《${book.title}》');
      }
    } on ImportException catch (error) {
      if (mounted) _toast(error.message);
    } catch (error) {
      if (mounted) _toast('重新定位失败：$error');
    } finally {
      if (staged != null) {
        try {
          await staged!.delete();
        } catch (_) {}
      }
    }
  }

  Future<void> _deleteBook(ComicBook book) async {
    final confirmed = await _confirmDelete(1);
    if (confirmed != true || !mounted) return;
    await _repository.deleteBook(book);
    if (mounted) _toast('已删除《${book.title}》');
  }

  Future<void> _deleteSelected() async {
    final selected = _repository.books
        .where((book) => _selectedIds.contains(book.id))
        .toList();
    if (selected.isEmpty) {
      _exitSelection();
      return;
    }
    final confirmed = await _confirmDelete(selected.length);
    if (confirmed != true || !mounted) return;
    await _repository.deleteBooks(selected);
    if (!mounted) return;
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
    _toast('已删除 ${selected.length} 本漫画');
  }

  void _markSelectedRead() {
    final selected = _repository.books
        .where((book) => _selectedIds.contains(book.id))
        .toList();
    if (selected.isEmpty) {
      _exitSelection();
      return;
    }
    final changed = _repository.markBooksRead(selected);
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
    _toast(changed == 0 ? '选中的漫画已经是已读状态' : '已将 $changed 本标记为已读');
  }

  Future<bool?> _confirmDelete(int count) {
    final title = count <= 1 ? '删除这本漫画？' : '删除选中的 $count 本漫画？';
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: const Text('应用内副本、封面及相关缓存会被删除。导入时复制到应用内的文件会一并清理，原文件不受影响。'),
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
  }

  Future<T?> _runWithProgress<T>(
    String title,
    Future<T> Function(ImportProgressCallback onProgress) action,
  ) async {
    final notifier = ValueNotifier<_ProgressState>(_ProgressState(title, 0));
    final dialogFuture = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _ProgressDialog(notifier: notifier),
    );
    try {
      return await action((label, value) {
        notifier.value = _ProgressState(label, value);
      });
    } finally {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      unawaited(dialogFuture.whenComplete(notifier.dispose));
    }
  }

  Future<void> _showStorage() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => LibraryStorageSheet(repository: _repository),
    );
  }

  Future<void> _renameFolder(LibraryFolder folder) async {
    final name = await showFolderNameDialog(context, initialName: folder.name);
    if (!mounted || name == null) return;
    final ok = _repository.renameFolder(folder, name);
    _toast(ok ? '文件夹已重命名' : '文件夹名称已存在或没有变化');
  }

  Future<void> _deleteFolder(LibraryFolder folder) async {
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
    if (confirmed != true || !mounted) return;
    await _repository.deleteFolder(folder);
    if (mounted) _toast('文件夹已删除，书籍已移回书架');
  }

  Future<void> _showSeries() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => SeriesScreen(repository: _repository),
      ),
    );
  }

  Future<void> _showStats() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ReadingStatsSheet(repository: _repository),
    );
  }

  Future<void> _showBackup() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => BackupSheet(repository: _repository),
    );
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

  Future<void> _showAbout() async {
    await showDialog<void>(
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
              Text('· 目录、书签（名称/备注）、缩略图导航'),
              Text('· 双页模式、加密 PDF 解锁'),
              Text('· 搜索筛选、批量管理、系列与标签'),
              Text('· 文件夹导入与重命名、阅读统计、备份'),
              Text('· 自动保存阅读进度、阅读方向与模式'),
              Text('· 导入的文件只保存在本机'),
              SizedBox(height: 16),
              Text('版本 1.3.0'),
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
    final content = PopScope<void>(
      canPop: !_importing && !_selectionMode,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_selectionMode) _exitSelection();
      },
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
                  final allVisible = _visibleBooks(books);
                  final folders = [..._repository.folders]
                    ..sort(
                      (a, b) =>
                          a.name.toLowerCase().compareTo(b.name.toLowerCase()),
                    );
                  final showFolderGroups =
                      !_hasActiveFilters &&
                      !_selectionMode &&
                      folders.isNotEmpty;
                  final visible = showFolderGroups
                      ? allVisible
                            .where(
                              (book) =>
                                  book.folderId == null ||
                                  _repository.folderById(book.folderId) == null,
                            )
                            .toList()
                      : allVisible;
                  final folderBooks = <String, List<ComicBook>>{};
                  for (final book in books) {
                    final folderId = book.folderId;
                    if (folderId == null) continue;
                    folderBooks.putIfAbsent(folderId, () => []).add(book);
                  }
                  final folderBookCount = folderBooks.values.fold<int>(
                    0,
                    (sum, items) => sum + items.length,
                  );
                  final lastRead = _repository.lastRead;
                  final view = _repository.librarySettings.view;
                  final showContinue =
                      lastRead != null && !_hasActiveFilters && !_selectionMode;
                  final countLabel = _hasActiveFilters
                      ? '${allVisible.length} / ${books.length}'
                      : '${visible.length}';
                  final bottomPadding = _selectionMode ? 128.0 : 110.0;

                  return CustomScrollView(
                    physics: const BouncingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics(),
                    ),
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 20, 12, 0),
                          child: _Header(
                            onImportFolder: _pickFolderAndImport,
                            onSeries: _showSeries,
                            onStats: _showStats,
                            onBackup: _showBackup,
                            onStorage: _showStorage,
                            onAbout: _showAbout,
                          ),
                        ),
                      ),
                      if (books.isNotEmpty)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                            child: _LibraryToolbar(
                              controller: _searchController,
                              query: _query,
                              onChanged: _onSearchChanged,
                              onClearQuery: _clearQuery,
                              onFilter: _showFilterSheet,
                              onToggleView: _toggleView,
                              viewMode: view,
                              filterActive:
                                  _formatFilter != null ||
                                  _readFilter != _ReadFilter.all ||
                                  _seriesFilter != null ||
                                  _tagFilter != null ||
                                  _favoritesOnly,
                              formatFilter: _formatFilter,
                              readFilter: _readFilter,
                              seriesFilter: _seriesFilter,
                              tagFilter: _tagFilter,
                              favoritesOnly: _favoritesOnly,
                              onClearFormat: _clearFormatFilter,
                              onClearRead: _clearReadFilter,
                              onClearSeries: _clearSeriesFilter,
                              onClearTag: _clearTagFilter,
                              onClearFavorites: _clearFavoritesFilter,
                            ),
                          ),
                        ),
                      if (showContinue)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                            child: _ContinueReadingCard(
                              book: lastRead,
                              onTap: () => _openBook(lastRead),
                            ),
                          ),
                        ),
                      if (showFolderGroups)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                            child: _FolderSection(
                              folders: folders,
                              booksByFolder: folderBooks,
                              totalBooks: folderBookCount,
                              onOpen: (folder) => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (context) => FolderScreen(
                                    repository: _repository,
                                    folderId: folder.id,
                                  ),
                                ),
                              ),
                              onRename: _renameFolder,
                              onDelete: _deleteFolder,
                            ),
                          ),
                        ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            20,
                            books.isEmpty ? 32 : 26,
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
                                    countLabel,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                              if (_hasActiveFilters) ...[
                                const Spacer(),
                                TextButton(
                                  onPressed: _clearSearchAndFilters,
                                  child: const Text(
                                    '清除筛选',
                                    style: TextStyle(fontSize: 11),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      if (books.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: _EmptyLibrary(onImport: _showImportOptions),
                        )
                      else if (visible.isEmpty && !showFolderGroups)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: _NoMatchingBooks(
                            onClear: _clearSearchAndFilters,
                          ),
                        )
                      else if (visible.isEmpty && showFolderGroups)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.035),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.06),
                                ),
                              ),
                              child: const Row(
                                children: [
                                  Icon(
                                    Icons.folder_open_outlined,
                                    size: 18,
                                    color: AppColors.textSecondary,
                                  ),
                                  SizedBox(width: 9),
                                  Expanded(
                                    child: Text(
                                      '根目录暂无书籍，内容都在文件夹中。',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                      else if (view == LibraryViewMode.grid)
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(
                            20,
                            0,
                            20,
                            bottomPadding,
                          ),
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
                              final book = visible[index];
                              return _BookCard(
                                book: book,
                                missing: !_repository.fileExists(book),
                                selectionMode: _selectionMode,
                                selected: _selectedIds.contains(book.id),
                                onTap: () {
                                  if (_selectionMode) {
                                    _toggleSelection(book);
                                  } else {
                                    _openBook(book);
                                  }
                                },
                                onLongPress: () {
                                  if (_selectionMode) {
                                    _toggleSelection(book);
                                  } else {
                                    _enterSelection(book);
                                  }
                                },
                                onMore: () => _showBookActions(book),
                              );
                            }, childCount: visible.length),
                          ),
                        )
                      else
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(
                            20,
                            0,
                            20,
                            bottomPadding,
                          ),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate((
                              context,
                              index,
                            ) {
                              final book = visible[index];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _BookListItem(
                                  book: book,
                                  missing: !_repository.fileExists(book),
                                  selectionMode: _selectionMode,
                                  selected: _selectedIds.contains(book.id),
                                  onTap: () {
                                    if (_selectionMode) {
                                      _toggleSelection(book);
                                    } else {
                                      _openBook(book);
                                    }
                                  },
                                  onLongPress: () {
                                    if (_selectionMode) {
                                      _toggleSelection(book);
                                    } else {
                                      _enterSelection(book);
                                    }
                                  },
                                  onMore: () => _showBookActions(book),
                                ),
                              );
                            }, childCount: visible.length),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
            if (!_selectionMode)
              Positioned(
                right: 20,
                bottom: 24,
                child: SafeArea(
                  child: FloatingActionButton.extended(
                    onPressed: _importing ? null : _showImportOptions,
                    icon: const IgnorePointer(child: Icon(Icons.add_rounded)),
                    label: const Text('导入'),
                  ),
                ),
              ),
            if (_selectionMode)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _SelectionBar(
                  selectedCount: _selectedIds.length,
                  allSelected:
                      _selectedIds.isNotEmpty &&
                      _selectedIds.length ==
                          _visibleBooks(_repository.books).length,
                  onClose: _exitSelection,
                  onSelectAll: () =>
                      _toggleSelectAll(_visibleBooks(_repository.books)),
                  onMarkRead: _markSelectedRead,
                  onDelete: _deleteSelected,
                ),
              ),
            if (_importing)
              _ImportOverlay(
                label: _importLabel,
                progress: _importProgress,
                success: _importSuccess,
                failure: _importFailure,
                cancelling: _cancelImport,
                onCancel: _cancelRemainingImports,
              ),
            if (_dragActive) const _DropOverlay(),
          ],
        ),
      ),
    );
    if (!_supportsDesktopDrop) return content;
    return DropTarget(
      enable: !_importing,
      onDragEntered: (_) {
        if (!mounted || _importing) return;
        setState(() => _dragActive = true);
      },
      onDragExited: (_) {
        if (mounted) setState(() => _dragActive = false);
      },
      onDragDone: (details) {
        if (mounted) setState(() => _dragActive = false);
        final paths = details.files
            .map((file) => file.path)
            .where((path) => path.isNotEmpty)
            .toList();
        unawaited(_importDropped(paths));
      },
      child: content,
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
  const _Header({
    required this.onImportFolder,
    required this.onSeries,
    required this.onStats,
    required this.onBackup,
    required this.onStorage,
    required this.onAbout,
  });

  final VoidCallback onImportFolder;
  final VoidCallback onSeries;
  final VoidCallback onStats;
  final VoidCallback onBackup;
  final VoidCallback onStorage;
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
        PopupMenuButton<String>(
          tooltip: '更多',
          icon: const Icon(
            Icons.more_vert_rounded,
            size: 22,
            color: AppColors.textSecondary,
          ),
          onSelected: (value) {
            switch (value) {
              case 'importFolder':
                onImportFolder();
              case 'series':
                onSeries();
              case 'stats':
                onStats();
              case 'backup':
                onBackup();
              case 'storage':
                onStorage();
              case 'about':
                onAbout();
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: 'importFolder',
              child: Row(
                children: [
                  Icon(Icons.create_new_folder_outlined, size: 19),
                  SizedBox(width: 10),
                  Text('导入文件夹'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'series',
              child: Row(
                children: [
                  Icon(Icons.collections_bookmark_outlined, size: 19),
                  SizedBox(width: 10),
                  Text('系列合集'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'stats',
              child: Row(
                children: [
                  Icon(Icons.insights_rounded, size: 19),
                  SizedBox(width: 10),
                  Text('阅读统计'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'backup',
              child: Row(
                children: [
                  Icon(Icons.backup_outlined, size: 19),
                  SizedBox(width: 10),
                  Text('备份与恢复'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'storage',
              child: Row(
                children: [
                  Icon(Icons.storage_rounded, size: 19),
                  SizedBox(width: 10),
                  Text('存储管理'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'about',
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 19),
                  SizedBox(width: 10),
                  Text('关于漫阅'),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _LibraryToolbar extends StatelessWidget {
  const _LibraryToolbar({
    required this.controller,
    required this.query,
    required this.onChanged,
    required this.onClearQuery,
    required this.onFilter,
    required this.onToggleView,
    required this.viewMode,
    required this.filterActive,
    required this.formatFilter,
    required this.readFilter,
    required this.seriesFilter,
    required this.tagFilter,
    required this.favoritesOnly,
    required this.onClearFormat,
    required this.onClearRead,
    required this.onClearSeries,
    required this.onClearTag,
    required this.onClearFavorites,
  });

  final TextEditingController controller;
  final String query;
  final ValueChanged<String> onChanged;
  final VoidCallback onClearQuery;
  final VoidCallback onFilter;
  final VoidCallback onToggleView;
  final LibraryViewMode viewMode;
  final bool filterActive;
  final ComicFormat? formatFilter;
  final _ReadFilter readFilter;
  final String? seriesFilter;
  final String? tagFilter;
  final bool favoritesOnly;
  final VoidCallback onClearFormat;
  final VoidCallback onClearRead;
  final VoidCallback onClearSeries;
  final VoidCallback onClearTag;
  final VoidCallback onClearFavorites;

  @override
  Widget build(BuildContext context) {
    final hasFilterChips =
        formatFilter != null ||
        readFilter != _ReadFilter.all ||
        seriesFilter != null ||
        tagFilter != null ||
        favoritesOnly;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: TextField(
                    controller: controller,
                    onChanged: onChanged,
                    textInputAction: TextInputAction.search,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: '搜索书名或文件名',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      suffixIcon: query.isEmpty
                          ? null
                          : IconButton(
                              onPressed: onClearQuery,
                              tooltip: '清除搜索',
                              icon: const IgnorePointer(
                                child: Icon(Icons.close_rounded, size: 18),
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _ToolbarButton(
              icon: Icons.tune_rounded,
              tooltip: '排序与筛选',
              active: filterActive,
              onPressed: onFilter,
            ),
            const SizedBox(width: 6),
            _ToolbarButton(
              icon: viewMode == LibraryViewMode.grid
                  ? Icons.view_list_rounded
                  : Icons.grid_view_rounded,
              tooltip: viewMode == LibraryViewMode.grid ? '切换为列表' : '切换为网格',
              onPressed: onToggleView,
            ),
          ],
        ),
        if (hasFilterChips) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (formatFilter != null)
                _ActiveFilterChip(
                  label: formatFilter!.label,
                  onDeleted: onClearFormat,
                ),
              if (readFilter != _ReadFilter.all)
                _ActiveFilterChip(
                  label: readFilter.label,
                  onDeleted: onClearRead,
                ),
              if (favoritesOnly)
                _ActiveFilterChip(label: '收藏', onDeleted: onClearFavorites),
              if (seriesFilter != null)
                _ActiveFilterChip(
                  label: '系列：$seriesFilter',
                  onDeleted: onClearSeries,
                ),
              if (tagFilter != null)
                _ActiveFilterChip(label: '#$tagFilter', onDeleted: onClearTag),
            ],
          ),
        ],
      ],
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      iconSize: 21,
      padding: EdgeInsets.zero,
      style: IconButton.styleFrom(
        fixedSize: const Size(42, 42),
        minimumSize: const Size(42, 42),
        maximumSize: const Size(42, 42),
        backgroundColor: active
            ? AppColors.accent.withValues(alpha: 0.14)
            : Colors.white.withValues(alpha: 0.06),
        foregroundColor: active ? AppColors.accent : AppColors.textPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      icon: IgnorePointer(child: Icon(icon)),
    );
  }
}

class _ActiveFilterChip extends StatelessWidget {
  const _ActiveFilterChip({required this.label, required this.onDeleted});

  final String label;
  final VoidCallback onDeleted;

  @override
  Widget build(BuildContext context) {
    return InputChip(
      label: Text(label),
      onDeleted: onDeleted,
      deleteIcon: const Icon(Icons.close_rounded, size: 15),
      deleteIconColor: AppColors.textSecondary,
      backgroundColor: Colors.white.withValues(alpha: 0.06),
      side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      labelStyle: const TextStyle(fontSize: 11.5, color: AppColors.textPrimary),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
    );
  }
}

class _LibraryFilterSheet extends StatefulWidget {
  const _LibraryFilterSheet({
    required this.initialSort,
    required this.initialFormat,
    required this.initialReadFilter,
    required this.initialSeries,
    required this.initialTag,
    required this.initialFavoritesOnly,
    required this.seriesCounts,
    required this.tagCounts,
  });

  final LibrarySort initialSort;
  final ComicFormat? initialFormat;
  final _ReadFilter initialReadFilter;
  final String? initialSeries;
  final String? initialTag;
  final bool initialFavoritesOnly;
  final Map<String, int> seriesCounts;
  final Map<String, int> tagCounts;

  @override
  State<_LibraryFilterSheet> createState() => _LibraryFilterSheetState();
}

class _LibraryFilterSheetState extends State<_LibraryFilterSheet> {
  late LibrarySort _sort;
  late ComicFormat? _format;
  late _ReadFilter _readFilter;
  late String? _series;
  late String? _tag;
  late bool _favoritesOnly;

  @override
  void initState() {
    super.initState();
    _sort = widget.initialSort;
    _format = widget.initialFormat;
    _readFilter = widget.initialReadFilter;
    _series = widget.initialSeries;
    _tag = widget.initialTag;
    _favoritesOnly = widget.initialFavoritesOnly;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        ),
        child: SingleChildScrollView(
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
              const SizedBox(height: 16),
              Row(
                children: [
                  Text(
                    '排序与筛选',
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontSize: 18),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, size: 20),
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                '排序',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final sort in LibrarySort.values)
                    _FilterChoice(
                      label: sort.label,
                      selected: _sort == sort,
                      onTap: () => setState(() => _sort = sort),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              const Text(
                '格式',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _FilterChoice(
                    label: '全部',
                    selected: _format == null,
                    onTap: () => setState(() => _format = null),
                  ),
                  for (final format in ComicFormat.values)
                    _FilterChoice(
                      label: format.label,
                      selected: _format == format,
                      onTap: () => setState(() => _format = format),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              const Text(
                '阅读状态',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final filter in _ReadFilter.values)
                    _FilterChoice(
                      label: filter.label,
                      selected: _readFilter == filter,
                      onTap: () => setState(() => _readFilter = filter),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              const Text(
                '收藏',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _FilterChoice(
                    label: '全部',
                    selected: !_favoritesOnly,
                    onTap: () => setState(() => _favoritesOnly = false),
                  ),
                  _FilterChoice(
                    label: '只看收藏',
                    selected: _favoritesOnly,
                    onTap: () => setState(() => _favoritesOnly = true),
                  ),
                ],
              ),
              if (widget.seriesCounts.isNotEmpty) ...[
                const SizedBox(height: 18),
                const Text(
                  '系列',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _FilterChoice(
                      label: '全部系列',
                      selected: _series == null,
                      onTap: () => setState(() => _series = null),
                    ),
                    for (final entry in widget.seriesCounts.entries)
                      _FilterChoice(
                        label: '${entry.key} (${entry.value})',
                        selected: _series == entry.key,
                        onTap: () => setState(() => _series = entry.key),
                      ),
                  ],
                ),
              ],
              if (widget.tagCounts.isNotEmpty) ...[
                const SizedBox(height: 18),
                const Text(
                  '标签',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _FilterChoice(
                      label: '全部标签',
                      selected: _tag == null,
                      onTap: () => setState(() => _tag = null),
                    ),
                    for (final entry in widget.tagCounts.entries)
                      _FilterChoice(
                        label: '#${entry.key} (${entry.value})',
                        selected: _tag == entry.key,
                        onTap: () => setState(() => _tag = entry.key),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 22),
              Row(
                children: [
                  TextButton(
                    onPressed: () => setState(() {
                      _sort = LibrarySort.recentRead;
                      _format = null;
                      _readFilter = _ReadFilter.all;
                      _series = null;
                      _tag = null;
                      _favoritesOnly = false;
                    }),
                    child: const Text('重置'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(
                      _LibraryFilterResult(
                        sort: _sort,
                        format: _format,
                        readFilter: _readFilter,
                        series: _series,
                        tag: _tag,
                        favoritesOnly: _favoritesOnly,
                      ),
                    ),
                    child: const Text('应用'),
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

class _FilterChoice extends StatelessWidget {
  const _FilterChoice({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? AppColors.accent.withValues(alpha: 0.15)
          : Colors.white.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? AppColors.accent
                  : Colors.white.withValues(alpha: 0.07),
            ),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? AppColors.accent : AppColors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FolderSection extends StatelessWidget {
  const _FolderSection({
    required this.folders,
    required this.booksByFolder,
    required this.totalBooks,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
  });

  final List<LibraryFolder> folders;
  final Map<String, List<ComicBook>> booksByFolder;
  final int totalBooks;
  final ValueChanged<LibraryFolder> onOpen;
  final ValueChanged<LibraryFolder> onRename;
  final ValueChanged<LibraryFolder> onDelete;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.folder_rounded, size: 18, color: AppColors.accent),
            const SizedBox(width: 7),
            Text(
              '文件夹',
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontSize: 18),
            ),
            const SizedBox(width: 10),
            Text(
              '${folders.length} 个 · $totalBooks 本',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 142,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: folders.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final folder = folders[index];
              return SizedBox(
                width: 228,
                child: _FolderCard(
                  folder: folder,
                  books: booksByFolder[folder.id] ?? const [],
                  onOpen: () => onOpen(folder),
                  onRename: () => onRename(folder),
                  onDelete: () => onDelete(folder),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _FolderCard extends StatelessWidget {
  const _FolderCard({
    required this.folder,
    required this.books,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
  });

  final LibraryFolder folder;
  final List<ComicBook> books;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final average = books.isEmpty
        ? 0.0
        : books.fold<double>(0, (sum, book) => sum + book.progress) /
              books.length;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF2A2230), Color(0xFF17151B)],
            ),
            border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.folder_rounded,
                      size: 20,
                      color: AppColors.accent,
                    ),
                  ),
                  const Spacer(),
                  PopupMenuButton<String>(
                    tooltip: '文件夹操作',
                    icon: const Icon(
                      Icons.more_horiz_rounded,
                      size: 19,
                      color: AppColors.textSecondary,
                    ),
                    onSelected: (value) {
                      if (value == 'rename') {
                        onRename();
                      } else if (value == 'delete') {
                        onDelete();
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: 'rename',
                        child: Row(
                          children: [
                            Icon(Icons.edit_outlined, size: 18),
                            SizedBox(width: 9),
                            Text('重命名文件夹'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(
                              Icons.folder_delete_outlined,
                              size: 18,
                              color: Color(0xFFE57373),
                            ),
                            SizedBox(width: 9),
                            Text(
                              '删除文件夹',
                              style: TextStyle(color: Color(0xFFE57373)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const Spacer(),
              Text(
                folder.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontSize: 14),
              ),
              const SizedBox(height: 3),
              Text(
                '${books.length} 本',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10.5,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 7),
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
      ),
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
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final compact = constraints.maxWidth < 160;
                          return Row(
                            children: [
                              Expanded(
                                child: ReadingProgressBar(
                                  value: book.progress,
                                  height: 7,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                compact
                                    ? '${book.safeLastPage + 1}/${book.pageCount}'
                                    : '第 ${book.safeLastPage + 1} / ${book.pageCount} 页',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(fontSize: 11),
                              ),
                            ],
                          );
                        },
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
    required this.missing,
    required this.selectionMode,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.onMore,
  });

  final ComicBook book;
  final bool missing;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final subtitle = missing
        ? '文件丢失 · 点按处理'
        : book.hasStarted
        ? '${formatProgressLabel(book.safeLastPage, book.pageCount)} · 第 ${book.safeLastPage + 1} 页'
        : '${formatPageCount(book.pageCount)} · 未读';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  BookCover(book: book, showProgress: true),
                  if (missing)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            color: Colors.black.withValues(alpha: 0.48),
                          ),
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: const Color(0xFFE57373)
                                      .withValues(alpha: 0.5),
                                ),
                              ),
                              child: const Text(
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
                    ),
                  if (!selectionMode)
                    Positioned(
                      top: 0,
                      right: 0,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: onMore,
                        child: SizedBox(
                          width: 40,
                          height: 40,
                          child: Center(
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.black.withValues(alpha: 0.42),
                              ),
                              child: const IgnorePointer(
                                child: Icon(
                                  Icons.more_horiz_rounded,
                                  size: 17,
                                  color: Colors.white70,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (selectionMode)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: _SelectionMark(selected: selected),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 9),
            Row(
              children: [
                if (book.pinned)
                  const Padding(
                    padding: EdgeInsets.only(right: 3),
                    child: Icon(
                      Icons.push_pin_rounded,
                      size: 11,
                      color: AppColors.accent,
                    ),
                  ),
                if (book.favorite)
                  const Padding(
                    padding: EdgeInsets.only(right: 3),
                    child: Icon(
                      Icons.star_rounded,
                      size: 12,
                      color: AppColors.accent,
                    ),
                  ),
                Expanded(
                  child: Text(
                    book.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontSize: 13.5, height: 1.2),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontSize: 11,
                color: missing
                    ? const Color(0xFFE57373)
                    : book.hasStarted
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

class _BookListItem extends StatelessWidget {
  const _BookListItem({
    required this.book,
    required this.missing,
    required this.selectionMode,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.onMore,
  });

  final ComicBook book;
  final bool missing;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              SizedBox(
                width: 54,
                height: 76,
                child: BookCover(
                  book: book,
                  showProgress: false,
                  borderRadius: const BorderRadius.all(Radius.circular(9)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        if (book.pinned)
                          const Padding(
                            padding: EdgeInsets.only(right: 3),
                            child: Icon(
                              Icons.push_pin_rounded,
                              size: 11,
                              color: AppColors.accent,
                            ),
                          ),
                        if (book.favorite)
                          const Padding(
                            padding: EdgeInsets.only(right: 3),
                            child: Icon(
                              Icons.star_rounded,
                              size: 12,
                              color: AppColors.accent,
                            ),
                          ),
                        Expanded(
                          child: Text(
                            book.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontSize: 13.5),
                          ),
                        ),
                        if (missing)
                          const Padding(
                            padding: EdgeInsets.only(left: 6),
                            child: Text(
                              '文件丢失',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFE57373),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${book.format.label} · ${formatPageCount(book.pageCount)} · '
                      '${book.hasStarted ? '${formatProgressLabel(book.safeLastPage, book.pageCount)} · 第 ${book.safeLastPage + 1} 页' : '未读'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(fontSize: 10.5),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      formatActivity(book.lastReadAt),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        color: book.hasStarted
                            ? AppColors.accent.withValues(alpha: 0.8)
                            : AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ReadingProgressBar(
                      value: book.progress,
                      height: 5,
                      gradient: missing
                          ? const LinearGradient(
                              colors: [Color(0xFFFF9A9A), Color(0xFFB3453F)],
                            )
                          : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              if (selectionMode)
                _SelectionMark(selected: selected)
              else
                IconButton(
                  onPressed: onMore,
                  tooltip: '更多操作',
                  icon: const Icon(
                    Icons.more_horiz_rounded,
                    size: 20,
                    color: AppColors.textSecondary,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectionMark extends StatelessWidget {
  const _SelectionMark({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected
            ? AppColors.accent
            : Colors.black.withValues(alpha: 0.45),
        border: Border.all(
          color: selected
              ? AppColors.accent
              : Colors.white.withValues(alpha: 0.65),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: selected
          ? const Icon(Icons.check_rounded, size: 16, color: Color(0xFF2A1500))
          : null,
    );
  }
}

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.selectedCount,
    required this.allSelected,
    required this.onClose,
    required this.onSelectAll,
    required this.onMarkRead,
    required this.onDelete,
  });

  final int selectedCount;
  final bool allSelected;
  final VoidCallback onClose;
  final VoidCallback onSelectAll;
  final VoidCallback onMarkRead;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
        decoration: BoxDecoration(
          color: AppColors.surfaceHigh,
          border: Border(
            top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 18,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: Row(
          children: [
            IconButton(
              onPressed: onClose,
              tooltip: '退出多选',
              icon: const IgnorePointer(
                child: Icon(Icons.close_rounded, size: 18),
              ),
              color: AppColors.textSecondary,
              style: IconButton.styleFrom(
                fixedSize: const Size(40, 40),
                minimumSize: const Size(40, 40),
                maximumSize: const Size(40, 40),
                padding: EdgeInsets.zero,
              ),
            ),
            Text(
              '已选 $selectedCount 本',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: onSelectAll,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                minimumSize: const Size(0, 36),
                visualDensity: VisualDensity.compact,
                textStyle: const TextStyle(fontSize: 12.5),
              ),
              child: Text(allSelected ? '取消全选' : '全选'),
            ),
            const SizedBox(width: 2),
            Tooltip(
              message: '标记已读',
              child: TextButton.icon(
                onPressed: selectedCount == 0 ? null : onMarkRead,
                icon: const IgnorePointer(
                  child: Icon(Icons.done_all_rounded, size: 16),
                ),
                label: const Text('已读'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.accent,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  minimumSize: const Size(0, 36),
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 2),
            FilledButton.icon(
              onPressed: selectedCount == 0 ? null : onDelete,
              icon: const IgnorePointer(
                child: Icon(Icons.delete_outline_rounded, size: 16),
              ),
              label: const Text('删除'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFB3453F),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                minimumSize: const Size(0, 36),
                textStyle: const TextStyle(fontSize: 12.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
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

class _NoMatchingBooks extends StatelessWidget {
  const _NoMatchingBooks({required this.onClear});

  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 20, 28, 110),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.04),
              ),
              child: const Icon(
                Icons.search_off_rounded,
                size: 30,
                color: Colors.white24,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              '没有匹配的漫画',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '试试其他关键词，或清除当前的排序筛选条件。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                height: 1.6,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.tonalIcon(
              onPressed: onClear,
              icon: const Icon(Icons.filter_alt_off_rounded, size: 18),
              label: const Text('清除搜索与筛选'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent.withValues(alpha: 0.12),
                foregroundColor: AppColors.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DropOverlay extends StatelessWidget {
  const _DropOverlay();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          color: Colors.black.withValues(alpha: 0.72),
          padding: const EdgeInsets.all(28),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 30),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: AppColors.accent.withValues(alpha: 0.5),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.accentDeep.withValues(alpha: 0.16),
                    blurRadius: 40,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.file_download_outlined,
                    size: 42,
                    color: AppColors.accent,
                  ),
                  SizedBox(height: 14),
                  Text(
                    '松开以导入漫画',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    '支持 PDF / MOBI 文件或文件夹',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
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

class _ImportOverlay extends StatelessWidget {
  const _ImportOverlay({
    required this.label,
    required this.progress,
    required this.success,
    required this.failure,
    required this.cancelling,
    required this.onCancel,
  });

  final String label;
  final double progress;
  final int success;
  final int failure;
  final bool cancelling;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final value = progress.isFinite ? progress.clamp(0.0, 1.0) : 0.0;
    return Positioned.fill(
      child: Stack(
        children: [
          const ModalBarrier(dismissible: false, color: Color(0xA6000000)),
          Center(
            child: Container(
              width: 340,
              margin: const EdgeInsets.symmetric(horizontal: 28),
              padding: const EdgeInsets.fromLTRB(24, 26, 24, 14),
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
                  ReadingProgressBar(value: value, height: 7),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        '${(value * 100).round()}%',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      const Spacer(),
                      if (success > 0 || failure > 0)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Text(
                            failure > 0
                                ? '成功 $success · 失败 $failure'
                                : '已成功 $success 本',
                            style: TextStyle(
                              fontSize: 10.5,
                              color: failure > 0
                                  ? const Color(0xFFE5A56B)
                                  : const Color(0xFF7BC98B),
                            ),
                          ),
                        ),
                      TextButton(
                        onPressed: cancelling ? null : onCancel,
                        child: Text(cancelling ? '正在取消…' : '取消剩余'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressDialog extends StatelessWidget {
  const _ProgressDialog({required this.notifier});

  final ValueNotifier<_ProgressState> notifier;
  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      canPop: false,
      child: AlertDialog(
        content: ValueListenableBuilder<_ProgressState>(
          valueListenable: notifier,
          builder: (context, state, _) {
            final value = state.value.isFinite
                ? state.value.clamp(0.0, 1.0)
                : 0.0;
            return SizedBox(
              width: 320,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.3,
                          color: AppColors.accent,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          state.label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            height: 1.4,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: value <= 0 ? null : value,
                      minHeight: 5.5,
                      backgroundColor: Colors.white.withValues(alpha: 0.08),
                      valueColor: const AlwaysStoppedAnimation(
                        AppColors.accent,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initialTitle});

  final String initialTitle;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialTitle);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final value = _controller.text.trim();
    if (value.isNotEmpty) Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _controller.text.trim().isNotEmpty;
    return AlertDialog(
      title: const Text('重命名'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: TextField(
          controller: _controller,
          autofocus: true,
          maxLength: 100,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _save(),
          decoration: const InputDecoration(
            labelText: '书架显示名称',
            counterText: '',
            prefixIcon: Icon(Icons.edit_outlined, size: 20),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: canSave ? _save : null,
          child: const Text('保存'),
        ),
      ],
    );
  }
}
