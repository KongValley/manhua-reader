import 'package:flutter/material.dart';

import '../models/comic_book.dart';
import '../theme/app_theme.dart';

class BookOrganizationResult {
  const BookOrganizationResult({required this.series, required this.tags});

  final String? series;
  final List<String> tags;
}

Future<BookOrganizationResult?> showBookOrganizationDialog(
  BuildContext context, {
  required ComicBook book,
  required List<String> knownSeries,
  required List<String> knownTags,
}) {
  return showDialog<BookOrganizationResult>(
    context: context,
    builder: (context) => BookOrganizationDialog(
      book: book,
      knownSeries: knownSeries,
      knownTags: knownTags,
    ),
  );
}

class BookOrganizationDialog extends StatefulWidget {
  const BookOrganizationDialog({
    required this.book,
    required this.knownSeries,
    required this.knownTags,
    super.key,
  });

  final ComicBook book;
  final List<String> knownSeries;
  final List<String> knownTags;

  @override
  State<BookOrganizationDialog> createState() => _BookOrganizationDialogState();
}

class _BookOrganizationDialogState extends State<BookOrganizationDialog> {
  late final TextEditingController _seriesController;
  final TextEditingController _tagController = TextEditingController();
  late final List<String> _tags;

  @override
  void initState() {
    super.initState();
    _seriesController = TextEditingController(text: widget.book.series ?? '');
    _tags = [...widget.book.tags];
  }

  @override
  void dispose() {
    _seriesController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  void _addTag([String? value]) {
    final source = value ?? _tagController.text;
    final tag = source.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (tag.isEmpty || _tags.contains(tag) || _tags.length >= 20) return;
    setState(() {
      _tags.add(tag.length <= 24 ? tag : tag.substring(0, 24));
      _tagController.clear();
    });
  }

  void _save() {
    final series = _seriesController.text
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    Navigator.of(context).pop(
      BookOrganizationResult(
        series: series.isEmpty ? null : series,
        tags: List<String>.unmodifiable(_tags),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final seriesSuggestions = widget.knownSeries
        .where((name) => name != _seriesController.text.trim())
        .take(12)
        .toList();
    final tagSuggestions = widget.knownTags
        .where((tag) => !_tags.contains(tag))
        .take(16)
        .toList();
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.collections_bookmark_outlined, size: 21),
          SizedBox(width: 10),
          Text('系列与标签'),
        ],
      ),
      content: SizedBox(
        width: 430,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _seriesController,
                maxLength: 60,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: '系列 / 合集',
                  hintText: '例如：海贼王、VOL',
                  counterText: '',
                  prefixIcon: Icon(
                    Icons.auto_awesome_motion_outlined,
                    size: 19,
                  ),
                ),
              ),
              if (seriesSuggestions.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final name in seriesSuggestions)
                      ActionChip(
                        label: Text(name),
                        onPressed: () =>
                            setState(() => _seriesController.text = name),
                        visualDensity: VisualDensity.compact,
                        labelStyle: const TextStyle(fontSize: 11),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 18),
              Row(
                children: [
                  const Icon(
                    Icons.sell_outlined,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    '标签',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${_tags.length}/20',
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_tags.isNotEmpty)
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final tag in _tags)
                      InputChip(
                        label: Text(tag),
                        onDeleted: () => setState(() => _tags.remove(tag)),
                        deleteIcon: const Icon(Icons.close_rounded, size: 14),
                        visualDensity: VisualDensity.compact,
                        labelStyle: const TextStyle(fontSize: 11),
                      ),
                  ],
                ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _tagController,
                      maxLength: 24,
                      textInputAction: TextInputAction.done,
                      onSubmitted: _addTag,
                      decoration: const InputDecoration(
                        hintText: '输入标签后回车 / 添加',
                        counterText: '',
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 11,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    onPressed: _tags.length >= 20 ? null : _addTag,
                    tooltip: '添加标签',
                    icon: const Icon(Icons.add_rounded, size: 20),
                  ),
                ],
              ),
              if (tagSuggestions.isNotEmpty) ...[
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final tag in tagSuggestions)
                      ActionChip(
                        label: Text('#$tag'),
                        onPressed: () => _addTag(tag),
                        visualDensity: VisualDensity.compact,
                        labelStyle: const TextStyle(fontSize: 10.5),
                      ),
                  ],
                ),
              ],
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
