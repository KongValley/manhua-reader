import 'package:flutter/material.dart';

import '../models/bookmark.dart';
import '../theme/app_theme.dart';

/// Values returned by the bookmark editor. Empty strings are converted to
/// null, so an empty form means "use the default page title and no note".
/// 书签编辑器返回的值。空字符串会转换为 null，因此空表单表示
/// “使用默认页码标题且不添加备注”。
class BookmarkEditResult {
  const BookmarkEditResult({this.label, this.note});

  final String? label;
  final String? note;
}

/// Dialog for adding or editing a bookmark's custom name and note.
/// 添加或编辑书签自定义名称与备注的对话框。
Future<BookmarkEditResult?> showBookmarkEditorDialog(
  BuildContext context, {
  required int page,
  Bookmark? existing,
}) {
  return showDialog<BookmarkEditResult>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _BookmarkEditorDialog(page: page, existing: existing),
  );
}

class _BookmarkEditorDialog extends StatefulWidget {
  const _BookmarkEditorDialog({required this.page, this.existing});

  final int page;
  final Bookmark? existing;

  @override
  State<_BookmarkEditorDialog> createState() => _BookmarkEditorDialogState();
}

class _BookmarkEditorDialogState extends State<_BookmarkEditorDialog> {
  late final TextEditingController _labelController;
  late final TextEditingController _noteController;
  final FocusNode _noteFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _labelController = TextEditingController(
      text: widget.existing?.label ?? '',
    );
    _noteController = TextEditingController(text: widget.existing?.note ?? '');
  }

  @override
  void dispose() {
    _labelController.dispose();
    _noteController.dispose();
    _noteFocus.dispose();
    super.dispose();
  }

  void _save() {
    final label = _labelController.text.trim();
    final note = _noteController.text.trim();
    Navigator.of(context).pop(
      BookmarkEditResult(
        label: label.isEmpty ? null : label,
        note: note.isEmpty ? null : note,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    return AlertDialog(
      icon: const Icon(
        Icons.bookmark_rounded,
        color: AppColors.accent,
        size: 27,
      ),
      title: Text(editing ? '编辑书签' : '添加书签'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(
                      '第 ${widget.page + 1} 页',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.accent,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      '名称和备注都是可选的',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _labelController,
                autofocus: true,
                maxLength: 80,
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => _noteFocus.requestFocus(),
                decoration: const InputDecoration(
                  labelText: '名称',
                  hintText: '不填写则显示“第 N 页”',
                  counterText: '',
                  prefixIcon: Icon(Icons.label_outline_rounded, size: 20),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _noteController,
                focusNode: _noteFocus,
                maxLength: 500,
                minLines: 2,
                maxLines: 4,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(
                  labelText: '备注',
                  hintText: '记录这一页的内容、想法或章节线索…',
                  counterText: '',
                  alignLabelWithHint: true,
                  prefixIcon: Padding(
                    padding: EdgeInsets.only(bottom: 34),
                    child: Icon(Icons.notes_rounded, size: 20),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _save, child: const Text('保存')),
      ],
    );
  }
}
