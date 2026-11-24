import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:path/path.dart' as p;

import '../models/comic_book.dart';
import '../models/library_folder.dart';
import '../models/library_settings.dart';
import '../models/reading_stats.dart';
import '../services/external_open_channel.dart';
import '../services/folder_import.dart';
import '../services/library_repository.dart';
import '../services/pdf_password_flow.dart';
import '../services/pdf_password_store.dart';
import '../services/saf_album_service.dart';
import '../services/saf_folder_service.dart';
import '../theme/app_theme.dart';
import '../utils/adaptive_layout.dart';
import '../utils/book_navigation.dart';
import '../utils/format.dart';
import '../widgets/backup_sheet.dart';
import '../widgets/book_cover.dart';
import '../widgets/book_organization_dialog.dart';
import '../widgets/folder_name_dialog.dart';
import '../widgets/library_deletion_undo.dart';
import '../widgets/library_storage_sheet.dart';
import '../widgets/pdf_password_dialog.dart';
import '../widgets/reading_progress_bar.dart';
import '../widgets/reading_stats_sheet.dart';
import 'folder_screen.dart';
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

enum _BatchAction {
  move('移动到文件夹', Icons.drive_file_move_outline),
  unread('标记未读', Icons.restart_alt_rounded),
  series('设置系列', Icons.collections_bookmark_outlined),
  addTags('添加标签', Icons.label_outline_rounded),
  removeTags('移除标签', Icons.label_off_outlined);

  const _BatchAction(this.label, this.icon);

  final String label;
  final IconData icon;
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
  const LibraryScreen({
    required this.repository,
    this.externalOpen,
    this.externalRoutes,
    super.key,
  });

  final LibraryRepository repository;
  final ExternalOpenChannel? externalOpen;
  final ExternalOpenNavigatorObserver? externalRoutes;

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
  bool _importStarting = false;
  bool _importCancellable = true;
  bool _cancelImport = false;
  String _importLabel = '';
  double _importProgress = 0;
  int _importSuccess = 0;
  int _importFailure = 0;

  bool _externalRequested = false;
  bool _externalScheduled = false;
  bool _externalRunning = false;
  ComicBook? _externalBook;

  LibraryRepository get _repository => widget.repository;

  @override
  void initState() {
    super.initState();
    _repository.addListener(_pruneSelection);
    final externalOpen = widget.externalOpen;
    if (externalOpen != null) {
      widget.externalRoutes?.addListener(_scheduleExternalOpen);
      externalOpen.listen(_externalFilesAvailable);
      _externalFilesAvailable();
    }
  }

  @override
  void dispose() {
    _repository.removeListener(_pruneSelection);
    widget.externalRoutes?.removeListener(_scheduleExternalOpen);
    widget.externalOpen?.listen(null);
    _searchController.dispose();
    super.dispose();
  }

  void _pruneSelection() {
    if (!_selectionMode && _selectedIds.isEmpty) return;
    final existing = _repository.books.map((book) => book.id).toSet();
    final removed = _selectedIds.where((id) => !existing.contains(id)).toList();
    if (removed.isEmpty) return;
    setState(() {
      _selectedIds.removeAll(removed);
      if (_selectedIds.isEmpty) {
        _selectionMode = false;
      }
    });
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
        return book.hasStarted && !book.isFinished;
      case _ReadFilter.finished:
        return book.isFinished;
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
    final allSelected = ids.isNotEmpty && ids.every(_selectedIds.contains);
    setState(() {
      if (allSelected) {
        _selectedIds.removeAll(ids);
      } else {
        _selectedIds.addAll(ids);
      }
    });
  }

  Future<void> _pickAndImport() async {
    if (_importing || _importStarting) return;
    setState(() => _importStarting = true);

    List<PlatformFile> files;
    try {
      files = await FilePicker.pickFiles(
        dialogTitle: '选择漫画文件',
        type: FileType.custom,
        allowedExtensions: ComicFormat.allExtensions,
      );
    } catch (error) {
      if (mounted) {
        setState(() => _importStarting = false);
        _toast('无法打开文件选择器：$error');
        _scheduleExternalOpen();
      }
      return;
    }
    if (!mounted) return;
    if (files.isEmpty || _importing) {
      setState(() => _importStarting = false);
      if (!_importing) _scheduleExternalOpen();
      return;
    }
    await _runImportCandidates([
      for (final file in files) _ImportCandidate(name: file.name, file: file),
    ]);
  }

  Future<void> _showImportOptions() async {
    if (_importing || _importStarting) return;
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
                subtitle: const Text('可多选 PDF / MOBI / CBZ'),
                onTap: () => Navigator.of(context).pop('files'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.create_new_folder_outlined),
                title: const Text('选择文件夹'),
                subtitle: const Text('递归导入文件夹中的 PDF / MOBI / CBZ'),
                onTap: () => Navigator.of(context).pop('folder'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('导入图片相册'),
                subtitle: const Text('引用 JPG / PNG 文件夹，不复制图片'),
                onTap: () => Navigator.of(context).pop('album'),
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
    if (!mounted || choice == null || _importing || _importStarting) return;
    if (choice == 'files') {
      await _pickAndImport();
    } else if (choice == 'album') {
      await _pickAlbumAndImport();
    } else {
      await _pickFolderAndImport();
    }
  }

  Future<void> _pickAlbumAndImport() async {
    if (_importing || _importStarting) return;
    setState(() => _importStarting = true);
    Directory? directory;
    String? treeUri;
    String name;
    try {
      if (SafAlbumService.isSupported) {
        treeUri = await SafFolderService.pickDirectory();
        if (treeUri == null) return;
        name = await SafFolderService.directoryName(treeUri);
      } else {
        final uri = await FilePicker.pickDirectory(dialogTitle: '选择图片相册文件夹');
        if (uri == null) return;
        if (uri.scheme != 'file') {
          _toast('当前平台无法直接读取该文件夹');
          return;
        }
        directory = Directory(uri.toFilePath());
        name = p.basename(directory.path);
      }
    } catch (error) {
      if (mounted) _toast('无法打开文件夹选择器：$error');
      return;
    } finally {
      if (mounted && _importStarting) {
        setState(() => _importStarting = false);
        _scheduleExternalOpen();
      }
    }
    if (!mounted || _importing) return;

    setState(() {
      _importing = true;
      _importCancellable = false;
      _cancelImport = false;
      _importSuccess = 0;
      _importFailure = 0;
      _importLabel = '正在扫描相册';
      _importProgress = 0;
    });
    try {
      final book = directory != null
          ? await _repository.importAlbumDirectory(
              directory,
              onProgress: _updateAlbumProgress,
            )
          : await _repository.importSafAlbum(
              treeUri: treeUri!,
              name: name,
              onProgress: _updateAlbumProgress,
            );
      if (!mounted) return;
      _toast('已添加相册《${book.title}》，共 ${book.pageCount} 张');
    } on ImportException catch (error) {
      if (mounted) _toast(error.message);
    } catch (error) {
      if (mounted) _toast('无法导入相册：$error');
    } finally {
      if (mounted) {
        setState(() {
          _importing = false;
          _importCancellable = true;
          _cancelImport = false;
          _importLabel = '';
          _importProgress = 0;
        });
        _scheduleExternalOpen();
      }
    }
  }

  void _updateAlbumProgress(String label, double value) {
    if (!mounted) return;
    setState(() {
      _importLabel = label;
      _importProgress = value;
    });
  }

  Future<void> _pickFolderAndImport() async {
    if (_importing || _importStarting) return;
    setState(() => _importStarting = true);
    var handedOff = false;
    try {
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
          if (mounted) _toast('无法读取文件夹：$error');
          return;
        }
        if (!mounted || _importing) return;
        if (files.isEmpty) {
          _toast('文件夹里没有漫画文件；如需浏览图片，请用「导入图片相册」');
          return;
        }
        final folder = _repository.ensureFolder(folderName);
        handedOff = true;
        try {
          await _runImportCandidates([
            for (final file in files)
              _ImportCandidate(name: file.name, saf: file, folderId: folder.id),
          ]);
        } finally {
          await _removeFolderIfEmpty(folder);
        }
        return;
      }

      Uri? uri;
      try {
        uri = await FilePicker.pickDirectory(dialogTitle: '选择漫画文件夹');
      } catch (error) {
        if (mounted) _toast('无法打开文件夹选择器：$error');
        return;
      }
      if (!mounted || uri == null || _importing) return;
      if (uri.scheme != 'file') {
        _toast('当前平台无法直接读取该文件夹，请改用多选文件');
        return;
      }

      final directory = Directory(uri.toFilePath());
      List<File> files;
      try {
        files = await FolderImportScanner.scanFolder(directory);
      } catch (error) {
        if (mounted) _toast('无法扫描文件夹：$error');
        return;
      }
      if (!mounted || _importing) return;
      if (files.isEmpty) {
        _toast('文件夹里没有漫画文件；如需浏览图片，请用「导入图片相册」');
        return;
      }
      final folderName = p.basename(directory.path).trim();
      final folder = _repository.ensureFolder(
        folderName.isEmpty ? '导入的文件夹' : folderName,
      );
      handedOff = true;
      try {
        await _runImportCandidates([
          for (final file in files)
            _ImportCandidate(
              name: p.basename(file.path),
              path: file.path,
              folderId: folder.id,
            ),
        ]);
      } finally {
        await _removeFolderIfEmpty(folder);
      }
    } finally {
      if (!handedOff && mounted && _importStarting) {
        setState(() => _importStarting = false);
        if (!_importing) _scheduleExternalOpen();
      }
    }
  }

  Future<void> _removeFolderIfEmpty(LibraryFolder folder) async {
    if (!mounted) return;
    if ((_repository.folderCounts[folder.id] ?? 0) == 0) {
      await _repository.deleteFolder(folder);
    }
  }

  Future<void> _importDropped(List<String> paths) async {
    if (_importing || _importStarting || paths.isEmpty) return;
    setState(() => _importStarting = true);
    final candidates = <_ImportCandidate>[];
    final createdFolders = <LibraryFolder>[];
    var handedOff = false;
    try {
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
        if (mounted) _toast('无法读取拖入的文件：$error');
        return;
      }
      if (!mounted || _importing) return;
      if (candidates.isEmpty) {
        _toast('拖入的内容里没有漫画文件；图片文件夹请用「导入图片相册」');
        return;
      }
      handedOff = true;
      await _runImportCandidates(candidates);
    } finally {
      for (final folder in createdFolders) {
        await _removeFolderIfEmpty(folder);
      }
      if (!handedOff && mounted && _importStarting) {
        setState(() => _importStarting = false);
        if (!_importing) _scheduleExternalOpen();
      }
    }
  }

  Future<void> _runImportCandidates(List<_ImportCandidate> candidates) async {
    if (candidates.isEmpty || _importing) {
      if (_importStarting && mounted) {
        setState(() => _importStarting = false);
        if (!_importing) _scheduleExternalOpen();
      }
      return;
    }
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
      _importStarting = false;
      _importing = true;
      _importCancellable = true;
      _cancelImport = false;
      _importLabel = '准备导入';
      _importProgress = 0;
      _importSuccess = 0;
      _importFailure = 0;
    });

    var imported = 0;
    var unsavedPasswords = 0;
    var cancelled = false;
    final errors = <String>[];
    try {
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

        final passwords = PdfPasswordFlow(
          prompt: (errorText) async {
            if (!mounted) return null;
            return showPdfPasswordDialog(
              context,
              fileName: name,
              errorText: errorText,
            );
          },
        );

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
              pdfPasswordProvider: passwords.provide,
            );
          } else if (picked != null) {
            final path = picked.path;
            if (path != null && path.isNotEmpty) {
              book = await _repository.importFile(
                path,
                originalName: name,
                folderId: candidate.folderId,
                onProgress: progress,
                pdfPasswordProvider: passwords.provide,
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
                pdfPasswordProvider: passwords.provide,
              );
            }
          } else if (candidate.path != null) {
            book = await _repository.importFile(
              candidate.path!,
              originalName: name,
              folderId: candidate.folderId,
              onProgress: progress,
              pdfPasswordProvider: passwords.provide,
            );
          } else {
            throw ImportException('无法读取文件');
          }
          if (!await passwords.onSuccess(book)) unsavedPasswords++;
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
    } finally {
      if (mounted) {
        setState(() {
          _importing = false;
          _importStarting = false;
          _importCancellable = true;
          _cancelImport = false;
          _importProgress = 0;
        });
        _scheduleExternalOpen();
      }
    }

    if (!mounted) return;
    if (imported > 0 || cancelled) {
      final parts = <String>[];
      if (imported > 0) parts.add('已导入 $imported 本');
      if (cancelled) parts.add('已取消剩余文件');
      if (unsavedPasswords > 0) parts.add('$unsavedPasswords 本的密码未能保存');
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

  void _externalFilesAvailable() {
    _externalRequested = true;
    _scheduleExternalOpen();
  }

  void _scheduleExternalOpen() {
    if (!mounted ||
        !_externalRequested ||
        _externalScheduled ||
        _externalRunning ||
        _importing ||
        _importStarting) {
      return;
    }
    _externalScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _externalScheduled = false;
      if (mounted) unawaited(_processExternalOpen());
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _processExternalOpen() async {
    final channel = widget.externalOpen;
    final routes = widget.externalRoutes;
    final top = routes?.topRoute ?? ModalRoute.of(context);
    if (channel == null ||
        _externalRunning ||
        _importing ||
        _importStarting ||
        top is! PageRoute<dynamic> ||
        !top.isCurrent) {
      return;
    }

    _externalRunning = true;
    ExternalOpenRequest? request;
    try {
      if (_externalBook == null) {
        _externalRequested = false;
        request = await channel.takeNext();
        if (request == null || !mounted) return;
        _externalRequested = true;
        if (request.path == null) {
          throw ImportException(request.error ?? '无法读取文件');
        }
        _externalBook = await _importExternalBook(request);
      }

      // Let any active reader route finish disposing before launching the next.
      // 连续触发外部打开时先等待当前阅读器退出完成，再打开新漫画。
      while (true) {
        if (!mounted) return;
        final active = routes?.topRoute ?? ModalRoute.of(context) ?? top;
        if (active is! PageRoute<dynamic> || !active.isCurrent) return;
        if (active.settings.name != readerRouteName) break;
        final navigator = active.navigator;
        if (navigator == null) return;
        navigator.pop();
        await active.completed;
      }
      if (!mounted) return;
      final nextTop = routes?.topRoute;
      if (nextTop != null &&
          (nextTop is! PageRoute<dynamic> || !nextTop.isCurrent)) {
        return;
      }
      final book = _externalBook!;
      _externalBook = null;
      unawaited(openComicBook(context, book: book, repository: _repository));
    } on MissingPluginException {
      _externalRequested = false;
    } catch (error) {
      _externalBook = null;
      if (mounted) {
        final name = request?.name;
        await _showImportErrors([
          if (name == null) '$error' else '$name：$error',
        ]);
      }
    } finally {
      await request?.release();
      _externalRunning = false;
      if (mounted) {
        final currentTop = routes?.topRoute ?? ModalRoute.of(context);
        if (currentTop is PageRoute<dynamic>) {
          _scheduleExternalOpen();
        }
      }
    }
  }

  Future<ComicBook> _importExternalBook(ExternalOpenRequest request) async {
    setState(() {
      _importing = true;
      _importCancellable = false;
      _cancelImport = false;
      _importLabel = '正在打开 ${request.name}';
      _importProgress = 0;
      _importSuccess = 0;
      _importFailure = 0;
    });
    final passwords = PdfPasswordFlow(
      prompt: (errorText) async {
        if (!mounted) return null;
        return showPdfPasswordDialog(
          context,
          fileName: request.name,
          errorText: errorText,
        );
      },
    );
    try {
      final book = await _repository.importFile(
        request.path!,
        originalName: request.name,
        reuseIdenticalBook: true,
        pdfPasswordProvider: passwords.provide,
        onProgress: (label, progress) {
          if (!mounted) return;
          setState(() {
            _importLabel = label;
            _importProgress = progress;
          });
        },
      );
      if (!await passwords.onSuccess(book) && mounted) {
        _toast('密码未能保存');
      }
      return book;
    } finally {
      if (mounted) {
        setState(() {
          _importing = false;
          _importCancellable = true;
          _cancelImport = false;
          _importLabel = '';
          _importProgress = 0;
        });
      }
    }
  }

  Future<void> _openBook(ComicBook book, {bool continueReading = false}) async {
    if (_selectionMode) {
      _toggleSelection(book);
      return;
    }
    if (!_repository.fileExists(book)) {
      await _showBookActions(book);
      return;
    }
    await openComicBook(
      context,
      book: book,
      repository: _repository,
      page: continueReading ? book.safeLastPage : null,
    );
  }

  Future<void> _showBookActions(ComicBook book) async {
    final missing = !_repository.fileExists(book);
    final finished = LibraryRepository.isFinished(book);
    final totalBookSeconds = _repository.stats.bookSecondsTotal(book.id);
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
                            '${book.bookmarks.isEmpty ? '' : ' · ${book.bookmarks.length} 个书签'}'
                            '${totalBookSeconds > 0 ? ' · 已看 ${formatCompactReadingDuration(totalBookSeconds)}' : ''}',
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
                    child: Row(
                      children: [
                        const Icon(
                          Icons.folder_off_outlined,
                          size: 18,
                          color: Color(0xFFE57373),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            book.format.isAlbum
                                ? '相册文件夹不可用。可以重新选择文件夹，或从书架移除；不会删除原图片。'
                                : '文件已丢失。可以重新定位一个 PDF/MOBI/CBZ 文件，或删除此条目。',
                            style: const TextStyle(
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
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.drive_file_move_outline),
                  title: const Text('移动到文件夹'),
                  subtitle: Text(
                    _repository.folderById(book.folderId)?.name ?? '书架根目录',
                  ),
                  onTap: () => Navigator.of(context).pop('move'),
                ),
                if (book.pageCount > 0 && !finished)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.done_all_rounded),
                    title: const Text('标记已读'),
                    onTap: () => Navigator.of(context).pop('markRead'),
                  ),
                if (book.hasStarted || book.lastPage != 0)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.restart_alt_rounded),
                    title: const Text('标记未读'),
                    onTap: () => Navigator.of(context).pop('markUnread'),
                  ),
                _RememberedPasswordAction(
                  book: book,
                  onTap: () => Navigator.of(context).pop('forgetPassword'),
                ),
                if (missing)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.folder_open_rounded),
                    title: Text(book.format.isAlbum ? '重新选择相册文件夹' : '重新定位文件'),
                    subtitle: Text(
                      book.format.isAlbum
                          ? '选择新的图片文件夹，保留阅读进度和书签'
                          : '选择一个替换文件，保留阅读进度和书签',
                    ),
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
                  subtitle: Text(
                    book.format.isAlbum
                        ? '只从书架移除，不会删除原文件夹中的图片'
                        : '只删除应用内的副本，不影响原文件',
                  ),
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
        _toggleFavorite(book);
      case 'pin':
        _togglePinned(book);
      case 'read':
        await _openBook(book);
      case 'rename':
        await _showRenameDialog(book);
      case 'organize':
        await _showOrganizationDialog(book);
      case 'move':
        await _moveBooks([book]);
      case 'markRead':
        _markBooks([book], read: true);
      case 'markUnread':
        _markBooks([book], read: false);
      case 'forgetPassword':
        final forgotten = await PdfPasswordStore.forget(book);
        if (mounted) _toast(forgotten ? '已忘记 PDF 密码' : '无法移除已保存的 PDF 密码');
      case 'relink':
        if (book.format.isAlbum) {
          await _relinkAlbum(book);
        } else {
          await _relinkBook(book);
        }
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
    final passwords = PdfPasswordFlow(
      book: book,
      prompt: (errorText) async {
        if (!mounted) return null;
        return showPdfPasswordDialog(
          context,
          fileName: book.title,
          errorText: errorText,
        );
      },
    );

    try {
      final ok = await _runWithProgress<bool>(
        '正在生成封面…',
        (onProgress) => _repository.regenerateCover(
          book,
          pdfPasswordProvider: passwords.provide,
          onProgress: onProgress,
        ),
      );
      final passwordSaved = ok != true || await passwords.onSuccess(book);
      if (!mounted) return;
      if (ok == true) {
        _toast(passwordSaved ? '封面已更新' : '封面已更新，密码未能保存');
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
        allowedExtensions: book.format.extensions,
      );
    } catch (error) {
      _toast('无法打开文件选择器：$error');
      return;
    }
    if (picked == null || !mounted) return;
    final selected = picked;

    final passwords = PdfPasswordFlow(
      prompt: (errorText) async {
        if (!mounted) return null;
        return showPdfPasswordDialog(
          context,
          fileName: selected.name,
          errorText: errorText,
        );
      },
    );

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
          pdfPasswordProvider: passwords.provide,
          onProgress: (label, value) => onProgress(label, 0.3 + value * 0.7),
        );
      });
      if (result != null) {
        final passwordSaved = await passwords.onSuccess(result);
        if (!mounted) return;
        _toast(
          passwordSaved
              ? '已重新定位《${book.title}》'
              : '已重新定位《${book.title}》，密码未能保存',
        );
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

  Future<void> _relinkAlbum(ComicBook book) async {
    String? source;
    try {
      if (SafAlbumService.isSupported) {
        source = await SafFolderService.pickDirectory();
      } else {
        final uri = await FilePicker.pickDirectory(dialogTitle: '选择新的图片文件夹');
        if (uri == null) return;
        if (uri.scheme != 'file') {
          _toast('当前平台无法直接读取该文件夹');
          return;
        }
        source = uri.toFilePath();
      }
    } catch (error) {
      _toast('无法打开文件夹选择器：$error');
      return;
    }
    if (source == null || !mounted) return;
    final nextSource = source;
    try {
      await _runWithProgress<ComicBook>(
        '正在重新定位相册…',
        (onProgress) => _repository.relinkAlbum(
          book,
          source: nextSource,
          onProgress: onProgress,
        ),
      );
      if (mounted) _toast('已重新定位《${book.title}》');
    } on ImportException catch (error) {
      if (mounted) _toast(error.message);
    } catch (error) {
      if (mounted) _toast('重新定位失败：$error');
    }
  }

  Future<void> _deleteBook(ComicBook book) async {
    final confirmed = await _confirmDelete(1);
    if (confirmed != true || !mounted) return;
    _repository.deleteBooksLater([book]);
  }

  List<ComicBook> get _selectedBooks => _repository.books
      .where((book) => _selectedIds.contains(book.id))
      .toList();

  void _toggleFavorite(ComicBook book) {
    _repository.toggleFavorite(book);
    _toast(book.favorite ? '已收藏《${book.title}》' : '已取消收藏《${book.title}》');
  }

  void _togglePinned(ComicBook book) {
    _repository.togglePinned(book);
    _toast(book.pinned ? '已置顶《${book.title}》' : '已取消置顶《${book.title}》');
  }

  void _favoriteSelected() {
    final selected = _selectedBooks;
    if (selected.isEmpty) return;
    final favorite = selected.any((book) => !book.favorite);
    final changed = _repository.setBooksFavorite(selected, favorite);
    if (changed == 0) return;
    _pruneSelectionToVisible();
    _toast(favorite ? '已收藏 $changed 本' : '已取消收藏 $changed 本');
  }

  /// Drops selected books that the active filters no longer show.
  /// 移除被当前筛选隐藏的选中项，全部隐藏时退出多选。
  void _pruneSelectionToVisible() {
    final visibleIds = _visibleBooks(_repository.books)
        .map((book) => book.id)
        .toSet();
    if (_selectedIds.every(visibleIds.contains)) return;
    setState(() {
      _selectedIds.removeWhere((id) => !visibleIds.contains(id));
      if (_selectedIds.isEmpty) _selectionMode = false;
    });
  }

  void _pinSelected() {
    final selected = _selectedBooks;
    if (selected.isEmpty) return;
    final pinned = selected.any((book) => !book.pinned);
    final changed = _repository.setBooksPinned(selected, pinned);
    if (changed == 0) return;
    _toast(pinned ? '已置顶 $changed 本' : '已取消置顶 $changed 本');
  }

  Future<void> _deleteSelected() async {
    final selected = _selectedBooks;
    if (selected.isEmpty) {
      _exitSelection();
      return;
    }
    final confirmed = await _confirmDelete(selected.length);
    if (confirmed != true || !mounted) return;
    _repository.deleteBooksLater(selected);
    _exitSelection();
  }

  void _markSelectedRead() {
    final selected = _selectedBooks;
    _exitSelection();
    _markBooks(selected, read: true);
  }

  void _markBooks(List<ComicBook> books, {required bool read}) {
    final label = read ? '已读' : '未读';
    final changed = read
        ? _repository.markBooksRead(books)
        : _repository.markBooksUnread(books);
    _toast(changed == 0 ? '阅读状态没有变化' : '已将 $changed 本标记为$label');
  }

  Future<void> _moveBooks(List<ComicBook> books) async {
    const newFolder = '__new_folder__';
    final picked = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('移动到文件夹'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(dialogContext).pop(''),
            child: const Text('书架根目录'),
          ),
          for (final folder in _repository.folders)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(folder.id),
              child: Text(folder.name),
            ),
          const Divider(height: 8),
          SimpleDialogOption(
            onPressed: () => Navigator.of(dialogContext).pop(newFolder),
            child: const Row(
              children: [
                Icon(Icons.create_new_folder_outlined, size: 20),
                SizedBox(width: 10),
                Text('新建文件夹'),
              ],
            ),
          ),
        ],
      ),
    );
    if (!mounted || picked == null) return;
    if (picked == newFolder) {
      final name = await showFolderNameDialog(
        context,
        initialName: '',
        title: '新建文件夹',
      );
      if (!mounted || name == null) return;
      final folder = _repository.ensureFolder(name);
      final changed = _repository.moveBooksToFolder(books, folder.id);
      _exitSelection();
      _toast(changed == 0 ? '未移动任何漫画' : '已将 $changed 本移动到${folder.name}');
      return;
    }
    final folderId = picked.isEmpty ? null : picked;
    final changed = _repository.moveBooksToFolder(books, folderId);
    _exitSelection();
    final name = _repository.folderById(folderId)?.name ?? '书架根目录';
    _toast(changed == 0 ? '未移动任何漫画' : '已将 $changed 本移动到$name');
  }

  Future<void> _showBatchActions() async {
    final selected = _selectedBooks;
    if (selected.isEmpty) return;
    final action = await showModalBottomSheet<_BatchAction>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final action in _BatchAction.values)
                ListTile(
                  leading: Icon(action.icon),
                  title: Text(action.label),
                  onTap: () => Navigator.of(sheetContext).pop(action),
                ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _BatchAction.move:
        await _moveBooks(selected);
      case _BatchAction.unread:
        _exitSelection();
        _markBooks(selected, read: false);
      case _BatchAction.series:
      case _BatchAction.addTags:
      case _BatchAction.removeTags:
        await _editBatchOrganization(action, selected);
    }
  }

  Future<void> _editBatchOrganization(
    _BatchAction action,
    List<ComicBook> books,
  ) async {
    final series = action == _BatchAction.series;
    var value = '';
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(action.label),
        content: TextField(
          autofocus: true,
          maxLength: series ? 60 : null,
          decoration: InputDecoration(
            labelText: series ? '系列名称' : '标签',
            helperText: series ? '留空可清除系列' : '可用逗号、顿号或换行分隔多个标签',
          ),
          keyboardType: series ? TextInputType.text : TextInputType.multiline,
          maxLines: series ? 1 : 3,
          onChanged: (text) => value = text,
          onSubmitted: series
              ? (_) => Navigator.of(dialogContext).pop(value)
              : null,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(value),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (!mounted || result == null) return;
    final tags = result.split(RegExp(r'[,，、\n]'));
    final changed = switch (action) {
      _BatchAction.series => _repository.setBooksSeries(books, result),
      _BatchAction.addTags => _repository.addBooksTags(books, tags),
      _BatchAction.removeTags => _repository.removeBooksTags(books, tags),
      _ => 0,
    };
    _pruneSelectionToVisible();
    _toast(changed == 0 ? '系列与标签没有变化' : '已更新 $changed 本漫画');
  }

  Future<bool?> _confirmDelete(int count) {
    final title = count <= 1 ? '删除这本漫画？' : '删除选中的 $count 本漫画？';
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: const Text('删除后可以短暂撤销。撤销期限结束后会清理书架中的应用内副本和封面，原文件会保留。'),
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
      builder: (context) => LibraryStorageSheet(
        repository: _repository,
        externalOpen: widget.externalOpen,
      ),
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
        builder: (context) => SeriesScreen(
          repository: _repository,
          onBookActions: _showBookActions,
        ),
      ),
    );
  }

  Future<void> _showStats() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: double.infinity),
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
            const AppLogo(size: 34),
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
              Text('· 支持 PDF / MOBI / CBZ 与图片相册'),
              Text('· 横向翻页 / 纵向滚动，双击可放大'),
              Text('· 目录、书签（名称/备注）、缩略图导航'),
              Text('· 双页模式、加密 PDF 解锁'),
              Text('· 屏幕常亮、亮度滤镜、自动翻页与音量键翻页'),
              Text('· 搜索筛选、批量管理、系列与标签'),
              Text('· 文件夹导入与重命名、阅读统计（年度热力图）、备份'),
              Text('· 自动保存阅读进度、阅读方向与模式'),
              Text('· 导入的文件只保存在本机'),
              SizedBox(height: 16),
              Text('版本 1.9.0'),
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
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          margin: _selectionMode
              ? EdgeInsets.fromLTRB(
                  20,
                  0,
                  20,
                  MediaQuery.paddingOf(context).bottom + 112,
                )
              : null,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    _scheduleExternalOpen();
    final content = PopScope<void>(
      canPop: !_importing && !_selectionMode,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_selectionMode) _exitSelection();
      },
      child: ListenableBuilder(
        listenable: _repository,
        builder: (context, bodyChild) => Scaffold(
          bottomNavigationBar: _repository.pendingDeletionCount > 0
              ? LibraryDeletionUndo(repository: _repository)
              : null,
          body: bodyChild!,
        ),
        child: Stack(
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
                  final screenWidth = MediaQuery.sizeOf(context).width;
                  final hPad = screenWidth > 1440
                      ? (screenWidth - 1440) / 2 + 32
                      : AdaptiveLayout.horizontalPadding(screenWidth);
                  final wideHero = screenWidth >= 860;
                  final twoColList = screenWidth >= 760;
                  final showDailyStrip =
                      !_hasActiveFilters &&
                      !_selectionMode &&
                      (books.isNotEmpty ||
                          _repository.stats.totalSeconds > 0 ||
                          _repository.stats.dailyGoalMinutes > 0);
                  final countLabel = _hasActiveFilters
                      ? '${allVisible.length} / ${books.length}'
                      : '${visible.length}';
                  final bottomPadding =
                      (_selectionMode ? 168.0 : 110.0) +
                      MediaQuery.paddingOf(context).bottom;

                  Widget buildGridCard(ComicBook book) {
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
                      onToggleFavorite: () => _toggleFavorite(book),
                      onTogglePinned: () => _togglePinned(book),
                    );
                  }

                  Widget buildListItem(ComicBook book) {
                    return _BookListItem(
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
                      onToggleFavorite: () => _toggleFavorite(book),
                      onTogglePinned: () => _togglePinned(book),
                    );
                  }

                  return CustomScrollView(
                    physics: const BouncingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics(),
                    ),
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            hPad,
                            20,
                            (hPad - 8).clamp(8.0, hPad),
                            0,
                          ),
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
                            padding: EdgeInsets.fromLTRB(hPad, 16, hPad, 0),
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
                      if (wideHero && showDailyStrip && showContinue)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(hPad, 14, hPad, 0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      minHeight: 118,
                                    ),
                                    child: _ContinueReadingCard(
                                      book: lastRead,
                                      onTap: () => _openBook(
                                        lastRead,
                                        continueReading: true,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  flex: 2,
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      minHeight: 118,
                                    ),
                                    child: _DailyReadingStrip(
                                      stats: _repository.stats,
                                      onTap: _showStats,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else ...[
                        if (showDailyStrip)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(hPad, 14, hPad, 0),
                              child: _DailyReadingStrip(
                                stats: _repository.stats,
                                onTap: _showStats,
                              ),
                            ),
                          ),
                        if (showContinue)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(hPad, 14, hPad, 0),
                              child: _ContinueReadingCard(
                                book: lastRead,
                                onTap: () =>
                                    _openBook(lastRead, continueReading: true),
                              ),
                            ),
                          ),
                      ],
                      if (showFolderGroups)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(hPad, 20, hPad, 0),
                            child: _FolderSection(
                              folders: folders,
                              booksByFolder: folderBooks,
                              totalBooks: folderBookCount,
                              onOpen: (folder) => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (context) => FolderScreen(
                                    repository: _repository,
                                    folderId: folder.id,
                                    onBookActions: _showBookActions,
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
                            hPad,
                            books.isEmpty ? 32 : 26,
                            hPad,
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
                            padding: EdgeInsets.fromLTRB(hPad, 10, hPad, 30),
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
                            hPad,
                            0,
                            hPad,
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
                            delegate: SliverChildBuilderDelegate(
                              (context, index) => buildGridCard(visible[index]),
                              childCount: visible.length,
                            ),
                          ),
                        )
                      else
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(
                            hPad,
                            0,
                            hPad,
                            bottomPadding,
                          ),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                if (!twoColList) {
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: buildListItem(visible[index]),
                                  );
                                }
                                final leftIndex = index * 2;
                                final rightIndex = leftIndex + 1;
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: buildListItem(visible[leftIndex]),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: rightIndex < visible.length
                                            ? buildListItem(visible[rightIndex])
                                            : const SizedBox.shrink(),
                                      ),
                                    ],
                                  ),
                                );
                              },
                              childCount: twoColList
                                  ? (visible.length + 1) ~/ 2
                                  : visible.length,
                            ),
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
                child: ListenableBuilder(
                  listenable: _repository,
                  builder: (context, _) {
                    final visible = _visibleBooks(_repository.books);
                    final visibleIds = visible.map((book) => book.id).toSet();
                    final selected = _repository.books
                        .where((book) => _selectedIds.contains(book.id))
                        .toList();
                    return _SelectionBar(
                      selectedCount: selected.length,
                      allSelected:
                          visibleIds.isNotEmpty &&
                          visibleIds.every(_selectedIds.contains),
                      allFavorite:
                          selected.isNotEmpty &&
                          selected.every((book) => book.favorite),
                      allPinned:
                          selected.isNotEmpty &&
                          selected.every((book) => book.pinned),
                      onClose: _exitSelection,
                      onSelectAll: () => _toggleSelectAll(visible),
                      onFavorite: _favoriteSelected,
                      onPin: _pinSelected,
                      onMarkRead: _markSelectedRead,
                      onMore: _showBatchActions,
                      onDelete: _deleteSelected,
                    );
                  },
                ),
              ),
            if (_importing)
              _ImportOverlay(
                label: _importLabel,
                progress: _importProgress,
                success: _importSuccess,
                failure: _importFailure,
                cancelling: _cancelImport,
                cancellable: _importCancellable,
                onCancel: _cancelRemainingImports,
              ),
            if (_dragActive) const _DropOverlay(),
          ],
        ),
      ),
    );
    if (!_supportsDesktopDrop) return content;
    return DropTarget(
      enable: !_importing && !_importStarting,
      onDragEntered: (_) {
        if (!mounted || _importing || _importStarting) return;
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

  int _columnCount(BuildContext context) =>
      AdaptiveLayout.bookColumns(MediaQuery.sizeOf(context).width);
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
        const AppLogo(),
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
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Container(
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
                          'PDF · MOBI · CBZ',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF2A1500),
                            letterSpacing: 0.4,
                          ),
                        ),
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
                      hintText: '搜索书名或拼音首字母',
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

class _DailyReadingStrip extends StatelessWidget {
  const _DailyReadingStrip({required this.stats, required this.onTap});

  final ReadingStats stats;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final todaySeconds = stats.secondsToday(now);
    final weekSeconds = stats.secondsThisWeek(now);
    final streak = stats.currentStreak(now);
    final goalMinutes = stats.dailyGoalMinutes;
    final goalMet = stats.isGoalMetOn(now);
    final progress = stats.goalProgressToday(now);
    final accent = goalMet ? AppColors.success : AppColors.accent;

    final subtitle = goalMinutes > 0
        ? (goalMet
              ? '已达成每日 $goalMinutes 分钟目标'
              : '目标 $goalMinutes 分钟 · 已完成 ${(progress * 100).round()}%')
        : (streak > 0
              ? '连续 $streak 天 · 本周 ${formatCompactReadingDuration(weekSeconds)}'
              : '本周已看 ${formatCompactReadingDuration(weekSeconds)}');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: goalMet
                  ? AppColors.success.withValues(alpha: 0.28)
                  : Colors.white.withValues(alpha: 0.07),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(
                      goalMet ? Icons.verified_rounded : Icons.schedule_rounded,
                      size: 16,
                      color: accent,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '今日已看 ${formatCompactReadingDuration(todaySeconds)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: goalMet
                                ? AppColors.success
                                : AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '时间记录',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: accent,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(Icons.chevron_right_rounded, size: 16, color: accent),
                ],
              ),
              if (goalMinutes > 0) ...[
                const SizedBox(height: 8),
                ReadingProgressBar(
                  value: progress,
                  height: 4,
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

class _ContinueReadingCard extends StatelessWidget {
  const _ContinueReadingCard({required this.book, required this.onTap});

  final ComicBook book;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final finished = book.isFinished;
    final statusColor = finished ? AppColors.success : AppColors.accent;

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
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: statusColor,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            finished ? '已读完' : '继续阅读',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2,
                              color: statusColor,
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
                  child: Icon(
                    finished ? Icons.done_rounded : Icons.play_arrow_rounded,
                    size: 20,
                    color: statusColor,
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

class _CoverActionBar extends StatelessWidget {
  const _CoverActionBar({
    required this.book,
    required this.onFavorite,
    required this.onPinned,
    required this.onMore,
  });

  final ComicBook book;
  final VoidCallback onFavorite;
  final VoidCallback onPinned;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 2),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.46),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _CoverActionSegment(
            icon: book.favorite
                ? Icons.star_rounded
                : Icons.star_border_rounded,
            tooltip: book.favorite
                ? '取消收藏《${book.title}》'
                : '收藏《${book.title}》',
            active: book.favorite,
            onPressed: onFavorite,
          ),
          _CoverActionSegment(
            icon: book.pinned
                ? Icons.push_pin_rounded
                : Icons.push_pin_outlined,
            tooltip: book.pinned ? '取消置顶《${book.title}》' : '置顶《${book.title}》',
            active: book.pinned,
            onPressed: onPinned,
          ),
          _CoverActionSegment(
            icon: Icons.more_horiz_rounded,
            tooltip: '更多操作',
            onPressed: onMore,
          ),
        ],
      ),
    );
  }
}

class _CoverActionSegment extends StatelessWidget {
  const _CoverActionSegment({
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
    return SizedBox(
      width: 32,
      height: 32,
      child: IconButton(
        onPressed: onPressed,
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(
          fixedSize: const Size(32, 32),
          minimumSize: const Size(32, 32),
          maximumSize: const Size(32, 32),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        icon: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active
                ? AppColors.accent.withValues(alpha: 0.18)
                : Colors.transparent,
          ),
          child: Icon(
            icon,
            size: 17,
            color: active ? AppColors.accent : Colors.white70,
          ),
        ),
      ),
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  const _QuickActionButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.active = false,
    this.onDark = true,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool active;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final foreground = active
        ? (onDark ? const Color(0xFF2A1500) : AppColors.accent)
        : (onDark ? Colors.white70 : AppColors.textSecondary);
    final background = active
        ? (onDark ? AppColors.accent : AppColors.accent.withValues(alpha: 0.12))
        : (onDark ? Colors.black.withValues(alpha: 0.42) : Colors.transparent);

    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 36,
        height: 36,
        child: IconButton(
          onPressed: onPressed,
          padding: EdgeInsets.zero,
          style: IconButton.styleFrom(
            fixedSize: const Size(36, 36),
            minimumSize: const Size(36, 36),
            maximumSize: const Size(36, 36),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          icon: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: background,
              border: active
                  ? Border.all(
                      color: onDark
                          ? Colors.white.withValues(alpha: 0.28)
                          : AppColors.accent.withValues(alpha: 0.35),
                    )
                  : null,
            ),
            child: Icon(icon, size: 17, color: foreground),
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
    required this.onToggleFavorite,
    required this.onTogglePinned,
  });

  final ComicBook book;
  final bool missing;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onMore;
  final VoidCallback onToggleFavorite;
  final VoidCallback onTogglePinned;

  @override
  Widget build(BuildContext context) {
    final subtitle = missing
        ? '文件丢失 · 点按处理'
        : book.isFinished
        ? '已读完 · 第 ${book.safeLastPage + 1} 页'
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
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Move the actions down when the cover is too narrow to
                  // share the top edge with the format badge.
                  // 封面过窄时把操作按钮移到底部，避免遮挡格式徽标。
                  final compactActions = constraints.maxWidth < 156;
                  return Stack(
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
                          top: compactActions ? null : 4,
                          bottom: compactActions ? 8 : null,
                          right: 4,
                          child: _CoverActionBar(
                            book: book,
                            onFavorite: onToggleFavorite,
                            onPinned: onTogglePinned,
                            onMore: onMore,
                          ),
                        ),
                      if (selectionMode)
                        Positioned(
                          top: 6,
                          right: 6,
                          child: _SelectionMark(selected: selected),
                        ),
                    ],
                  );
                },
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
                color: missing
                    ? const Color(0xFFE57373)
                    : book.isFinished
                    ? AppColors.success
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
    required this.onToggleFavorite,
    required this.onTogglePinned,
  });

  final ComicBook book;
  final bool missing;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onMore;
  final VoidCallback onToggleFavorite;
  final VoidCallback onTogglePinned;

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
                      '${book.isFinished
                          ? '已读完'
                          : book.hasStarted
                          ? '${formatProgressLabel(book.safeLastPage, book.pageCount)} · 第 ${book.safeLastPage + 1} 页'
                          : '未读'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 10.5,
                        color: book.isFinished ? AppColors.success : null,
                      ),
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
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _QuickActionButton(
                      icon: book.favorite
                          ? Icons.star_rounded
                          : Icons.star_border_rounded,
                      tooltip: book.favorite
                          ? '取消收藏《${book.title}》'
                          : '收藏《${book.title}》',
                      active: book.favorite,
                      onDark: false,
                      onPressed: onToggleFavorite,
                    ),
                    _QuickActionButton(
                      icon: book.pinned
                          ? Icons.push_pin_rounded
                          : Icons.push_pin_outlined,
                      tooltip: book.pinned
                          ? '取消置顶《${book.title}》'
                          : '置顶《${book.title}》',
                      active: book.pinned,
                      onDark: false,
                      onPressed: onTogglePinned,
                    ),
                    _QuickActionButton(
                      icon: Icons.more_horiz_rounded,
                      tooltip: '更多操作',
                      onDark: false,
                      onPressed: onMore,
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

/// Shows the forget-password action only when this device remembers one.
/// 仅当此设备保存过密码时显示「忘记 PDF 密码」。
class _RememberedPasswordAction extends StatefulWidget {
  const _RememberedPasswordAction({required this.book, required this.onTap});

  final ComicBook book;
  final VoidCallback onTap;

  @override
  State<_RememberedPasswordAction> createState() =>
      _RememberedPasswordActionState();
}

class _RememberedPasswordActionState extends State<_RememberedPasswordAction> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    final book = widget.book;
    if (book.format != ComicFormat.pdf || !PdfPasswordStore.isSupported) return;
    unawaited(
      PdfPasswordStore.hasRemembered(book).then((remembered) {
        if (mounted && remembered) setState(() => _visible = true);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.lock_reset_rounded),
      title: const Text('忘记 PDF 密码'),
      onTap: widget.onTap,
    );
  }
}

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.selectedCount,
    required this.allSelected,
    required this.allFavorite,
    required this.allPinned,
    required this.onClose,
    required this.onSelectAll,
    required this.onFavorite,
    required this.onPin,
    required this.onMarkRead,
    required this.onMore,
    required this.onDelete,
  });

  final int selectedCount;
  final bool allSelected;
  final bool allFavorite;
  final bool allPinned;
  final VoidCallback onClose;
  final VoidCallback onSelectAll;
  final VoidCallback onFavorite;
  final VoidCallback onPin;
  final VoidCallback onMarkRead;
  final VoidCallback onMore;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final hasSelection = selectedCount > 0;
    // Scaffold zeroes the body's MediaQuery padding when it reserves space
    // for the system navigation bar, so read the window inset directly.
    // Scaffold 为系统导航栏预留空间时会清零 body 的 MediaQuery padding，
    // 因此这里直接读取窗口的 viewPadding。
    final view = View.of(context);
    final navInset = view.viewPadding.bottom / view.devicePixelRatio;
    return SafeArea(
      top: false,
      bottom: false,
      child: Container(
        padding: EdgeInsets.fromLTRB(10, 6, 12, 10 + navInset),
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
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
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
                    TextButton.icon(
                      onPressed: hasSelection ? onMore : null,
                      icon: const Icon(Icons.more_horiz_rounded, size: 18),
                      label: const Text('批量操作'),
                    ),
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
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: _BatchActionButton(
                        icon: allFavorite
                            ? Icons.star_rounded
                            : Icons.star_border_rounded,
                        label: '收藏',
                        tooltip: allFavorite ? '取消收藏选中的漫画' : '收藏选中的漫画',
                        active: allFavorite,
                        onPressed: hasSelection ? onFavorite : null,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _BatchActionButton(
                        icon: allPinned
                            ? Icons.push_pin_rounded
                            : Icons.push_pin_outlined,
                        label: '置顶',
                        tooltip: allPinned ? '取消置顶选中的漫画' : '置顶选中的漫画',
                        active: allPinned,
                        onPressed: hasSelection ? onPin : null,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _BatchActionButton(
                        icon: Icons.done_all_rounded,
                        label: '已读',
                        tooltip: '标记已读',
                        highlight: true,
                        onPressed: hasSelection ? onMarkRead : null,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _BatchActionButton(
                        icon: Icons.delete_outline_rounded,
                        label: '删除',
                        tooltip: '删除选中的漫画',
                        danger: true,
                        onPressed: hasSelection ? onDelete : null,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BatchActionButton extends StatelessWidget {
  const _BatchActionButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onPressed,
    this.active = false,
    this.highlight = false,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool active;
  final bool highlight;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final foreground = danger
        ? Colors.white
        : active || highlight
        ? AppColors.accent
        : AppColors.textPrimary;
    final style = danger
        ? FilledButton.styleFrom(
            backgroundColor: const Color(0xFFB3453F),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            minimumSize: const Size(0, 36),
            visualDensity: VisualDensity.compact,
            textStyle: const TextStyle(fontSize: 12.5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          )
        : OutlinedButton.styleFrom(
            foregroundColor: foreground,
            backgroundColor: active
                ? AppColors.accent.withValues(alpha: 0.10)
                : null,
            side: BorderSide(
              color: active
                  ? AppColors.accent.withValues(alpha: 0.55)
                  : Colors.white.withValues(alpha: 0.12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            minimumSize: const Size(0, 36),
            visualDensity: VisualDensity.compact,
            textStyle: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          );

    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 16),
        const SizedBox(width: 4),
        Flexible(
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    );

    return Tooltip(
      message: tooltip,
      child: danger
          ? FilledButton(onPressed: onPressed, style: style, child: child)
          : OutlinedButton(onPressed: onPressed, style: style, child: child),
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
                    '支持 PDF / MOBI / CBZ 文件或文件夹',
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
    this.cancellable = true,
  });

  final String label;
  final double progress;
  final int success;
  final int failure;
  final bool cancelling;
  final VoidCallback onCancel;
  final bool cancellable;

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
                      AppLogo(size: 30),
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
                      if (cancellable)
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
