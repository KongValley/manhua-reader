import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android volume-key page turning.
///
/// The native activity intercepts volume keys only while the reader asks for
/// them, so the system volume keys keep working everywhere else.
/// Android 音量键翻页。
///
/// 原生 Activity 只在阅读器启用时拦截音量键，其他界面仍使用系统音量功能。
class VolumeKeys {
  static const MethodChannel _channel = MethodChannel('manhua/reader');

  static bool get isSupported => !kIsWeb && Platform.isAndroid;

  static Future<void> setEnabled(bool enabled) async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod<void>('setVolumeKeysEnabled', enabled);
    } catch (_) {
      // Non-Android platforms have no handler.
      // 非 Android 平台没有对应处理器。
    }
  }

  static void listen({
    required VoidCallback onNext,
    required VoidCallback onPrevious,
  }) {
    if (kIsWeb) return;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'nextPage':
          onNext();
          break;
        case 'previousPage':
          onPrevious();
          break;
      }
    });
  }

  static void stop() {
    if (kIsWeb) return;
    _channel.setMethodCallHandler(null);
  }
}
