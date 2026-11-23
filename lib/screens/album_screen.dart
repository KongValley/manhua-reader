import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;

import '../formats/album_comic_source.dart';
import '../formats/comic_source.dart';
import '../formats/comic_source_factory.dart';
import '../models/comic_book.dart';
import '../services/external_open_channel.dart';
import '../services/library_repository.dart';
import '../services/saf_album_service.dart';
import '../services/saf_folder_service.dart';
import '../theme/app_theme.dart';
import 'reader_screen.dart';

typedef _AlbumSortChoice = ({AlbumSortField field, bool descending});

const _albumSortOptions =
    <({AlbumSortField field, bool descending, String label})>[
      (field: AlbumSortField.name, descending: false, label: '名称 A→Z'),
      (field: AlbumSortField.name, descending: true, label: '名称 Z→A'),
      (field: AlbumSortField.created, descending: true, label: '创建时间 新→旧'),
      (field: AlbumSortField.created, descending: false, label: '创建时间 旧→新'),
      (field: AlbumSortField.modified, descending: true, label: '修改时间 新→旧'),
      (field: AlbumSortField.modified, descending: false, label: '修改时间 旧→新'),
    ];

/// Album-style thumbnail wall for a referenced image folder.
/// 引用型图片相册的缩略图墙。
class AlbumScreen extends StatefulWidget {
  const AlbumScreen({required this.book, required this.repository, super.key});

  final ComicBook book;
  final LibraryRepository repository;

  @override
  State<AlbumScreen> createState() => _AlbumScreenState();
}

class _AlbumScreenState extends State<AlbumScreen> {
  ComicSource? _source;
  Object? _error;
  bool _loading = true;
  bool _sorting = false;
  late AlbumSortField _sortField;
  late bool _sortDescending;

  @override
  void initState() {
    super.initState();
    _sortField = widget.book.albumSort;
    _sortDescending = widget.book.albumSortDescending;
    _openSource();
  }

  Future<void> _openSource() async {
    try {
      final source = await ComicSourceFactory.open(
        widget.book,
        albumSort: _sortField,
        albumSortDescending: _sortDescending,
      );
      if (!mounted) {
        await source.dispose();
        return;
      }
      if (source is AlbumComicSource) {
        widget.repository.syncAlbumMetadata(
          widget.book,
          source.pageCount,
          source.totalBytes,
        );
      }
      setState(() {
        _source = source;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  void _retry() {
    setState(() {
      _loading = true;
      _error = null;
    });
    _openSource();
  }

  Future<void> _changeSort(AlbumSortField field, bool descending) async {
    if (_sorting || (field == _sortField && descending == _sortDescending)) {
      return;
    }
    final oldSource = _source;
    final oldKeys = oldSource is AlbumComicSource
        ? oldSource.pageKeys
        : const <String>[];
    setState(() => _sorting = true);
    ComicSource? nextSource;
    try {
      nextSource = await ComicSourceFactory.open(
        widget.book,
        albumSort: field,
        albumSortDescending: descending,
      );
      if (!mounted) {
        await nextSource.dispose();
        return;
      }
      final newKeys = nextSource is AlbumComicSource
          ? nextSource.pageKeys
          : const <String>[];
      final dropped = widget.repository.setAlbumSort(
        widget.book,
        field,
        descending,
        oldKeys: oldKeys,
        newKeys: newKeys,
      );
      if (nextSource is AlbumComicSource) {
        widget.repository.syncAlbumMetadata(
          widget.book,
          nextSource.pageCount,
          nextSource.totalBytes,
        );
      }
      setState(() {
        _sortField = field;
        _sortDescending = descending;
        _source = nextSource;
        _sorting = false;
        _loading = false;
        _error = null;
      });
      if (oldSource != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          unawaited(oldSource.dispose().catchError((Object _) {}));
        });
      }
      if (dropped > 0) {
        _showMessage('$dropped 个书签因图片变化被移除');
      }
    } catch (error) {
      if (nextSource != null) await nextSource.dispose();
      if (!mounted) return;
      setState(() => _sorting = false);
      _showMessage('无法重新排序：$error');
    }
  }

  Future<void> _relink() async {
    String? source;
    try {
      if (SafAlbumService.isSupported) {
        source = await SafFolderService.pickDirectory();
      } else {
        final uri = await FilePicker.pickDirectory(dialogTitle: '选择相册文件夹');
        if (uri == null) return;
        if (uri.scheme != 'file') {
          _showMessage('当前平台无法直接读取该文件夹');
          return;
        }
        source = uri.toFilePath();
      }
    } catch (error) {
      _showMessage('无法打开文件夹选择器：$error');
      return;
    }
    if (source == null || !mounted) return;
    final nextSource = source;
    try {
      await widget.repository.relinkAlbum(widget.book, source: nextSource);
      if (!mounted) return;
      _retry();
    } on ImportException catch (error) {
      _showMessage(error.message);
    } catch (error) {
      _showMessage('重新定位失败：$error');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _openPage(int page) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: readerRouteName),
        builder: (context) => ReaderScreen(
          book: widget.book,
          repository: widget.repository,
          initialPage: page,
        ),
      ),
    );
  }

  @override
  void dispose() {
    final source = _source;
    _source = null;
    if (source != null) {
      unawaited(source.dispose().catchError((Object _) {}));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.readerBackground,
      appBar: AppBar(
        backgroundColor: AppColors.readerBackground,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 0,
        bottom: _sorting
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
        actions: [
          PopupMenuButton<_AlbumSortChoice>(
            tooltip: '排序',
            enabled: _source != null && !_sorting,
            icon: const Icon(Icons.sort_rounded),
            onSelected: (choice) =>
                _changeSort(choice.field, choice.descending),
            itemBuilder: (context) => [
              for (final option in _albumSortOptions)
                PopupMenuItem<_AlbumSortChoice>(
                  value: (field: option.field, descending: option.descending),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 24,
                        child:
                            option.field == _sortField &&
                                option.descending == _sortDescending
                            ? const Icon(
                                Icons.check_rounded,
                                size: 18,
                                color: AppColors.accent,
                              )
                            : null,
                      ),
                      Text(option.label),
                    ],
                  ),
                ),
            ],
          ),
        ],
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.book.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            if (_source != null)
              Text(
                '${_source!.pageCount} 张 · 点击图片开始阅读',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
          ],
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            color: AppColors.textSecondary,
          ),
        ),
      );
    }
    final error = _error;
    if (error != null || _source == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.photo_library_outlined,
                size: 40,
                color: AppColors.textSecondary,
              ),
              const SizedBox(height: 14),
              const Text(
                '相册无法打开',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                '$error',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                children: [
                  FilledButton.tonal(
                    onPressed: _retry,
                    child: const Text('重试'),
                  ),
                  TextButton(onPressed: _relink, child: const Text('重新选择文件夹')),
                ],
              ),
            ],
          ),
        ),
      );
    }

    final source = _source!;
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      scrollCacheExtent: const ScrollCacheExtent.pixels(600),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 190,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.72,
      ),
      itemCount: source.pageCount,
      itemBuilder: (context, index) => _AlbumTile(
        source: source,
        index: index,
        onTap: () => _openPage(index),
      ),
    );
  }
}

class _AlbumTile extends StatelessWidget {
  const _AlbumTile({
    required this.source,
    required this.index,
    required this.onTap,
  });

  final ComicSource source;
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            source.buildThumbnail(context, index),
            Positioned(
              right: 6,
              bottom: 6,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xB3000000),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
