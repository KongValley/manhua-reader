import 'package:flutter/material.dart';

import '../services/library_repository.dart';
import '../theme/app_theme.dart';

class LibraryDeletionUndo extends StatelessWidget {
  const LibraryDeletionUndo({required this.repository, super.key});

  final LibraryRepository repository;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: repository,
      builder: (context, _) {
        final count = repository.pendingDeletionCount;
        if (count == 0) return const SizedBox.shrink();
        return Material(
          color: AppColors.surfaceHigh,
          child: SafeArea(
            top: false,
            minimum: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text('已删除 $count 本漫画', semanticsLabel: '已删除 $count 本漫画，可撤销'),
                ),
                TextButton(
                  onPressed: repository.undoPendingDeletion,
                  child: const Text('撤销'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
