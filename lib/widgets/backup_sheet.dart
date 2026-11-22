import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/library_repository.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';

class BackupSheet extends StatefulWidget {
  const BackupSheet({required this.repository, super.key});

  final LibraryRepository repository;

  @override
  State<BackupSheet> createState() => _BackupSheetState();
}

class _BackupSheetState extends State<BackupSheet> {
  bool _busy = false;
  String _status = '';
  double _progress = 0;
  String? _error;
  String? _success;

  String _stamp() {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}-'
        '${two(now.hour)}${two(now.minute)}';
  }

  void _start(String label) {
    setState(() {
      _busy = true;
      _status = label;
      _progress = 0;
      _error = null;
      _success = null;
    });
  }

  void _finish({String? success, String? error}) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _progress = 0;
      _success = success;
      _error = error;
    });
  }

  Future<void> _exportJson() async {
    if (_busy) return;
    try {
      final bytes = widget.repository.exportBackupJson();
      final uri = await FilePicker.saveFile(
        fileName: 'manhua-bookshelf-${_stamp()}.json',
        bytes: bytes,
        mimeType: 'application/json',
        dialogTitle: '导出书架数据',
      );
      if (!mounted) return;
      if (uri != null) {
        _finish(success: '书架数据已导出（不含漫画文件）');
      }
    } catch (error) {
      _finish(error: '导出失败：$error');
    }
  }

  Future<void> _exportArchive() async {
    if (_busy) return;
    _start('正在准备完整备份…');
    File? archive;
    try {
      archive = await widget.repository.createBackupArchive(
        onProgress: (label, value) {
          if (mounted) {
            setState(() {
              _status = label;
              _progress = value;
            });
          }
        },
      );
      if (!mounted) return;
      _status = '请选择保存位置…';
      setState(() {});
      final bytes = await archive.readAsBytes();
      final uri = await FilePicker.saveFile(
        fileName: 'manhua-full-backup-${_stamp()}.mrbackup',
        bytes: bytes,
        mimeType: 'application/zip',
        dialogTitle: '导出完整备份',
      );
      if (!mounted) return;
      if (uri != null) {
        _finish(success: '完整备份已导出（${formatFileSize(bytes.length)}）');
      } else {
        _finish();
      }
    } catch (error) {
      _finish(error: '备份失败：$error');
    } finally {
      if (archive != null) {
        try {
          await archive.delete();
        } catch (_) {}
      }
    }
  }

  Future<void> _restore() async {
    if (_busy) return;
    PlatformFile? picked;
    try {
      picked = await FilePicker.pickFile(
        dialogTitle: '选择漫阅备份',
        type: FileType.any,
      );
    } catch (error) {
      _finish(error: '无法打开文件选择器：$error');
      return;
    }
    if (picked == null || !mounted) return;

    _start('正在读取备份…');
    try {
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      final result = await widget.repository.restoreBackupBytes(
        bytes,
        onProgress: (label, value) {
          if (mounted) {
            setState(() {
              _status = label;
              _progress = value;
            });
          }
        },
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _progress = 0;
      });
      await _showRestoreResult(result);
    } catch (error) {
      _finish(error: '恢复失败：$error');
    }
  }

  Future<void> _showRestoreResult(BackupImportResult result) async {
    if (!mounted) return;
    final lines = <String>[
      '成功导入 ${result.imported} 本',
      if (result.skipped > 0) '跳过重复 ${result.skipped} 本',
      if (result.failed > 0) '失败 ${result.failed} 本',
      if (result.booksWithoutFiles > 0)
        '${result.booksWithoutFiles} 本缺少文件，可在书架中重新定位',
      if (result.errors.isNotEmpty) '',
      ...result.errors.take(6),
    ];
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('备份恢复完成'),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Text(
              lines.join('\n'),
              style: const TextStyle(fontSize: 12.5, height: 1.6),
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
    if (mounted) {
      setState(() {
        _success = '备份已合并到当前书架';
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalBytes = widget.repository.books.fold<int>(
      0,
      (sum, book) => sum + book.fileSize,
    );
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
                      Icons.backup_rounded,
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
                          '备份与恢复',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontSize: 17),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${widget.repository.bookCount} 本 · 漫画文件约 '
                          '${formatFileSize(totalBytes)}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
                    icon: const IgnorePointer(
                      child: Icon(Icons.close_rounded, size: 20),
                    ),
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
              if (_busy) ...[
                const SizedBox(height: 16),
                Text(
                  _status,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: _progress <= 0 ? null : _progress.clamp(0.0, 1.0),
                    minHeight: 5.5,
                    backgroundColor: Colors.white.withValues(alpha: 0.08),
                    valueColor: const AlwaysStoppedAnimation(AppColors.accent),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              _BackupAction(
                icon: Icons.data_object_rounded,
                color: const Color(0xFF6B7BFF),
                title: '导出书架数据',
                subtitle: 'JSON · 含书架、进度、书签、标签与统计；不含漫画文件',
                enabled: !_busy,
                onTap: _exportJson,
              ),
              _BackupAction(
                icon: Icons.folder_zip_rounded,
                color: AppColors.accent,
                title: '导出完整备份',
                subtitle: 'ZIP · 包含导入的漫画文件与封面；引用型相册只保存书架信息',
                enabled: !_busy,
                onTap: _exportArchive,
              ),
              _BackupAction(
                icon: Icons.settings_backup_restore_rounded,
                color: const Color(0xFF7BC98B),
                title: '从备份恢复',
                subtitle: '支持 JSON / .mrbackup；合并到当前书架，自动跳过重复',
                enabled: !_busy,
                onTap: _restore,
              ),
              if (_success != null) ...[
                const SizedBox(height: 8),
                Text(
                  _success!,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF7BC98B),
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFFE57373),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              const Text(
                '仅 JSON 备份恢复后，若本机没有对应漫画文件，书籍会显示“文件丢失”，'
                '可逐本重新定位；完整备份会恢复导入的文件和封面，引用型相册只恢复书架条目，'
                '图片仍保存在原文件夹。',
                style: TextStyle(
                  fontSize: 10.5,
                  height: 1.6,
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

class _BackupAction extends StatelessWidget {
  const _BackupAction({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        enabled: enabled,
        leading: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
        title: Text(
          title,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(fontSize: 10.5, height: 1.45),
        ),
        trailing: const Icon(
          Icons.chevron_right_rounded,
          size: 20,
          color: AppColors.textSecondary,
        ),
        onTap: enabled ? onTap : null,
      ),
    );
  }
}
