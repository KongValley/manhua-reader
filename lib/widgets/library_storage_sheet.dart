import 'package:flutter/material.dart';

import '../models/comic_book.dart';
import '../models/library_storage_report.dart';
import '../services/library_repository.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';

/// Bottom sheet that summarises disk usage and reclaims cache/orphan files.
class LibraryStorageSheet extends StatefulWidget {
  const LibraryStorageSheet({required this.repository, super.key});

  final LibraryRepository repository;

  @override
  State<LibraryStorageSheet> createState() => _LibraryStorageSheetState();
}

class _LibraryStorageSheetState extends State<LibraryStorageSheet> {
  LibraryStorageReport? _report;
  bool _loading = true;
  bool _cleaning = false;
  String? _error;
  int? _lastFreed;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final report = await widget.repository.storageReport();
      if (!mounted) return;
      setState(() {
        _report = report;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _loading = false;
      });
    }
  }

  Future<void> _cleanup() async {
    final report = _report;
    if (report == null || _cleaning) return;
    if (report.reclaimableBytes <= 0) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清理存储空间？'),
        content: Text(
          '将删除临时缓存和 ${report.orphanFiles} 个无引用文件，预计释放 '
          '${formatFileSize(report.reclaimableBytes)}。\n\n'
          '不会删除书架中的漫画、封面、书签或阅读进度，也不影响原文件。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('清理'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _cleaning = true;
      _lastFreed = null;
      _error = null;
    });
    try {
      final freed = await widget.repository.cleanupStorage();
      if (!mounted) return;
      final report = await widget.repository.storageReport();
      if (!mounted) return;
      setState(() {
        _report = report;
        _cleaning = false;
        _lastFreed = freed;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _cleaning = false;
        _error = '$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final books = [...widget.repository.books]
      ..sort((a, b) => b.fileSize.compareTo(a.fileSize));
    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.86,
        ),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 22),
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
              const SizedBox(height: 14),
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.storage_rounded,
                      size: 19,
                      color: AppColors.accent,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '存储管理',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontSize: 17),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          '应用内副本、封面与缓存',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, size: 20),
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: AppColors.accent,
                    ),
                  ),
                )
              else if (_error != null && _report == null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 28),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        size: 28,
                        color: Color(0xFFE57373),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '读取存储信息失败\n$_error',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 12,
                          height: 1.6,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextButton(onPressed: _load, child: const Text('重试')),
                    ],
                  ),
                )
              else if (_report != null) ...[
                _UsageCard(report: _report!),
                const SizedBox(height: 16),
                _StorageRow(
                  icon: Icons.menu_book_rounded,
                  color: AppColors.accent,
                  label: '漫画文件',
                  detail: '${widget.repository.bookCount} 本',
                  bytes: _report!.bookBytes,
                ),
                _StorageRow(
                  icon: Icons.image_outlined,
                  color: const Color(0xFF6B7BFF),
                  label: '封面图片',
                  detail: '书架缩略图',
                  bytes: _report!.coverBytes,
                ),
                _StorageRow(
                  icon: Icons.hourglass_bottom_rounded,
                  color: const Color(0xFF8A93A6),
                  label: '临时缓存',
                  detail: '页面渲染与导入残留',
                  bytes: _report!.cacheBytes,
                ),
                _StorageRow(
                  icon: Icons.cleaning_services_outlined,
                  color: const Color(0xFFE5A56B),
                  label: '无引用文件',
                  detail: _report!.orphanFiles == 0
                      ? '没有可清理项'
                      : '${_report!.orphanFiles} 个文件',
                  bytes: _report!.orphanBytes,
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: Colors.white.withValues(alpha: 0.035),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.06),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '可回收空间',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _report!.reclaimableBytes <= 0
                                  ? '暂时没有需要清理的内容'
                                  : '缓存 + 无引用文件，共 '
                                        '${formatFileSize(_report!.reclaimableBytes)}',
                              style: const TextStyle(
                                fontSize: 11,
                                height: 1.5,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            if (_lastFreed != null) ...[
                              const SizedBox(height: 6),
                              Text(
                                _lastFreed! > 0
                                    ? '已释放 ${formatFileSize(_lastFreed!)}'
                                    : '清理完成，没有可释放的空间',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF7BC98B),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      FilledButton(
                        onPressed: _report!.reclaimableBytes <= 0 || _cleaning
                            ? null
                            : _cleanup,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: _cleaning
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Color(0xFF2B1700),
                                ),
                              )
                            : const Text('清理'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                if (books.isNotEmpty) ...[
                  Row(
                    children: [
                      const Text(
                        '书架明细',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${books.length} 本',
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  for (final book in books)
                    _BookUsageRow(
                      book: book,
                      missing: !widget.repository.fileExists(book),
                    ),
                  const SizedBox(height: 14),
                ],
                const Text(
                  '清理只删除应用生成的临时文件，不会影响书架内容。'
                  '如需释放漫画占用，请在书架中删除对应条目。',
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1.6,
                    color: AppColors.textSecondary,
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    '清理失败：$_error',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFFE57373),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _UsageCard extends StatelessWidget {
  const _UsageCard({required this.report});

  final LibraryStorageReport report;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatFileSize(report.totalBytes),
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                  color: AppColors.textPrimary,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 8),
              const Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Text(
                  '书架占用',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _UsageBar(report: report),
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              _LegendDot(color: AppColors.accent, label: '漫画'),
              _LegendDot(color: const Color(0xFF6B7BFF), label: '封面'),
              if (report.cacheBytes > 0)
                _LegendDot(color: const Color(0xFF8A93A6), label: '缓存'),
            ],
          ),
        ],
      ),
    );
  }
}

class _UsageBar extends StatelessWidget {
  const _UsageBar({required this.report});

  final LibraryStorageReport report;

  @override
  Widget build(BuildContext context) {
    final total = report.totalBytes + report.cacheBytes;
    if (total <= 0) {
      return Container(
        height: 8,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(6),
        ),
      );
    }
    int flex(int bytes) => (bytes * 1000 ~/ total).clamp(1, 1000);
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        height: 8,
        child: Row(
          children: [
            if (report.bookBytes > 0)
              Expanded(
                flex: flex(report.bookBytes),
                child: const ColoredBox(color: AppColors.accent),
              ),
            if (report.coverBytes > 0)
              Expanded(
                flex: flex(report.coverBytes),
                child: const ColoredBox(color: Color(0xFF6B7BFF)),
              ),
            if (report.cacheBytes > 0)
              Expanded(
                flex: flex(report.cacheBytes),
                child: const ColoredBox(color: Color(0xFF555D6E)),
              ),
            if (report.bookBytes <= 0 &&
                report.coverBytes <= 0 &&
                report.cacheBytes <= 0)
              const Expanded(child: ColoredBox(color: Color(0xFF2A2F3A))),
          ],
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            fontSize: 10.5,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _StorageRow extends StatelessWidget {
  const _StorageRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.detail,
    required this.bytes,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String detail;
  final int bytes;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  detail,
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Text(
            formatFileSize(bytes),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _BookUsageRow extends StatelessWidget {
  const _BookUsageRow({required this.book, required this.missing});

  final ComicBook book;
  final bool missing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 38,
            padding: const EdgeInsets.symmetric(vertical: 3),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.045),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Text(
              book.format.label,
              style: const TextStyle(
                fontSize: 8.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              book.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (missing)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Text(
                '文件丢失',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFE57373),
                ),
              ),
            )
          else
            Text(
              formatPageCount(book.pageCount),
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.textSecondary,
              ),
            ),
          const SizedBox(width: 10),
          Text(
            formatFileSize(book.fileSize),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
