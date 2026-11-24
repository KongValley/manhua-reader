import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';

import 'screens/library_screen.dart';
import 'services/external_open_channel.dart';
import 'services/library_repository.dart';
import 'theme/app_theme.dart';

class ManhuaApp extends StatefulWidget {
  const ManhuaApp({
    required this.repository,
    this.externalOpen,
    this.home,
    super.key,
  });

  final LibraryRepository repository;
  final ExternalOpenChannel? externalOpen;
  final Widget? home;

  @override
  State<ManhuaApp> createState() => _ManhuaAppState();
}

class _ManhuaAppState extends State<ManhuaApp> {
  final _externalRoutes = ExternalOpenNavigatorObserver();
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onInactive: _flushLibrary,
      onHide: _flushLibrary,
      onPause: _flushLibrary,
      onDetach: _flushLibrary,
    );
  }

  void _flushLibrary() {
    unawaited(widget.repository.flush());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _externalRoutes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '漫阅',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      scrollBehavior: const AppScrollBehavior(),
      navigatorObservers: [if (widget.externalOpen != null) _externalRoutes],
      home: widget.home ??
          LibraryScreen(
            repository: widget.repository,
            externalOpen: widget.externalOpen,
            externalRoutes: _externalRoutes,
          ),
    );
  }
}

/// Allows mouse dragging on desktop so the reader feels natural on tablets
/// connected to a mouse / trackpad as well.
/// 允许桌面端鼠标拖动，让连接鼠标 / 触控板的平板也有自然的阅读操作。
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
