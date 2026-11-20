import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import 'app.dart';
import 'services/app_paths.dart';
import 'services/library_repository.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await pdfrxFlutterInitialize();
  } catch (error, stack) {
    debugPrint('PDF engine initialization failed: $error\n$stack');
  }

  try {
    final paths = await AppPaths.resolve();
    final repository = LibraryRepository(paths);
    await repository.load();
    runApp(ManhuaApp(repository: repository));
  } catch (error, stack) {
    debugPrint('App startup failed: $error\n$stack');
    runApp(StartupErrorApp(message: '$error'));
  }
}

class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '漫阅',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  size: 42,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(height: 16),
                const Text(
                  '应用启动失败',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    height: 1.5,
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
