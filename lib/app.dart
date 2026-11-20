import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';

import 'screens/library_screen.dart';
import 'services/library_repository.dart';
import 'theme/app_theme.dart';

class ManhuaApp extends StatelessWidget {
  const ManhuaApp({required this.repository, this.home, super.key});

  final LibraryRepository repository;
  final Widget? home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '漫阅',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      scrollBehavior: const AppScrollBehavior(),
      home: home ?? LibraryScreen(repository: repository),
    );
  }
}

/// Allows mouse dragging on desktop so the reader feels natural on tablets
/// connected to a mouse / trackpad as well.
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
    PointerDeviceKind.trackpad,
  };
}
