import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

const readerRouteName = 'reader';

class ExternalOpenNavigatorObserver extends NavigatorObserver
    with ChangeNotifier {
  Route<dynamic>? topRoute;

  @override
  void didChangeTop(Route<dynamic> topRoute, Route<dynamic>? previousTopRoute) {
    this.topRoute = topRoute;
    notifyListeners();
  }
}

class ExternalOpenRequest {
  const ExternalOpenRequest({
    required this.name,
    this.path,
    this.error,
    this.temporary = false,
  });

  final String name;
  final String? path;
  final String? error;
  final bool temporary;

  Future<void> release() async {
    final filePath = path;
    if (!temporary || filePath == null) return;
    try {
      await File(filePath).delete();
    } on FileSystemException {
      // The platform cache can also be cleared by the operating system.
      // 操作系统也可以清理平台缓存。
    }
  }
}

class ExternalOpenChannel {
  const ExternalOpenChannel();

  static const _channel = MethodChannel('manhua/external_open');

  static bool get isSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isWindows);

  static bool get supportsAssociations => !kIsWeb && Platform.isWindows;

  /// The native queue holds startup requests until the shelf asks for them.
  /// 原生队列保留启动时收到的请求，直到书架主动读取。
  void listen(VoidCallback? onAvailable) {
    if (onAvailable == null) {
      _channel.setMethodCallHandler(null);
      return;
    }
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'filesAvailable') onAvailable();
    });
  }

  Future<ExternalOpenRequest?> takeNext() async {
    final data = await _channel.invokeMapMethod<String, Object?>('takeNext');
    if (data == null) return null;
    return ExternalOpenRequest(
      name: data['name'] as String,
      path: data['path'] as String?,
      error: data['error'] as String?,
      temporary: data['temporary'] == true,
    );
  }

  Future<bool> associationsRegistered() async =>
      await _channel.invokeMethod<bool>('associationsRegistered') ?? false;

  Future<void> setAssociationsRegistered(bool registered) =>
      _channel.invokeMethod<void>('setAssociationsRegistered', registered);
}
