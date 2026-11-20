import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Shows a password dialog for an encrypted PDF.
///
/// Returns the entered password, or null if the user cancels. Pass [errorText]
/// when reopening the dialog after a failed attempt.
/// 为加密 PDF 显示密码输入对话框。
///
/// 返回用户输入的密码；取消时返回 null。密码错误后重新打开对话框时
/// 传入 [errorText] 显示错误提示。
Future<String?> showPdfPasswordDialog(
  BuildContext context, {
  required String fileName,
  String? errorText,
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (context) =>
        _PdfPasswordDialog(fileName: fileName, errorText: errorText),
  );
}

class _PdfPasswordDialog extends StatefulWidget {
  const _PdfPasswordDialog({required this.fileName, this.errorText});

  final String fileName;
  final String? errorText;

  @override
  State<_PdfPasswordDialog> createState() => _PdfPasswordDialogState();
}

class _PdfPasswordDialogState extends State<_PdfPasswordDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _obscure = true;

  bool get _canSubmit => _controller.text.isNotEmpty;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_canSubmit) return;
    Navigator.of(context).pop(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(
        Icons.lock_outline_rounded,
        color: AppColors.accent,
        size: 28,
      ),
      title: const Text('PDF 已加密'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '《${widget.fileName}》需要密码才能打开。',
              style: const TextStyle(
                fontSize: 13,
                height: 1.5,
                color: AppColors.textSecondary,
              ),
            ),
            if (widget.errorText != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    size: 16,
                    color: Color(0xFFE57373),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      widget.errorText!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFFE57373),
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autofocus: true,
              obscureText: _obscure,
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submit(),
              style: const TextStyle(
                fontSize: 15,
                letterSpacing: 1,
                color: AppColors.textPrimary,
              ),
              decoration: InputDecoration(
                labelText: '密码',
                hintText: '输入 PDF 打开密码',
                prefixIcon: const Icon(Icons.password_rounded, size: 20),
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _obscure = !_obscure),
                  tooltip: _obscure ? '显示密码' : '隐藏密码',
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                    size: 20,
                  ),
                ),
                filled: true,
                fillColor: AppColors.backgroundSoft,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.accent),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 15,
                  color: AppColors.textSecondary,
                ),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '密码仅保存在本次运行的内存中，不会写入磁盘；重启应用后需要重新输入。',
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _canSubmit ? _submit : null,
          child: const Text('解锁'),
        ),
      ],
    );
  }
}
