import 'package:flutter/material.dart';

Future<String?> showFolderNameDialog(
  BuildContext context, {
  required String initialName,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _FolderNameDialog(initialName: initialName),
  );
}

class _FolderNameDialog extends StatefulWidget {
  const _FolderNameDialog({required this.initialName});

  final String initialName;

  @override
  State<_FolderNameDialog> createState() => _FolderNameDialogState();
}

class _FolderNameDialogState extends State<_FolderNameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final value = _controller.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (value.isNotEmpty) Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _controller.text.trim().isNotEmpty;
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.folder_outlined, size: 21),
          SizedBox(width: 10),
          Text('重命名文件夹'),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: TextField(
          controller: _controller,
          autofocus: true,
          maxLength: 60,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _save(),
          decoration: const InputDecoration(
            labelText: '文件夹名称',
            counterText: '',
            prefixIcon: Icon(Icons.drive_file_rename_outline, size: 20),
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
