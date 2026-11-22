import 'dart:ffi';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

typedef _SetThreadExecutionStateNative = Int32 Function(Uint32);
typedef _SetThreadExecutionStateDart = int Function(int);

/// Keeps the display awake while a comic is open.
///
/// Android and iOS use the platform channel; Windows calls the kernel directly
/// so no extra plugin is required.
/// 阅读漫画时保持屏幕常亮。
///
/// Android / iOS 走平台通道，Windows 直接调用内核接口，无需额外插件。
class ScreenAwake {
  static const MethodChannel _channel = MethodChannel('manhua/screen');

  static _SetThreadExecutionStateDart? _setThreadExecutionState;

  static Future<void> setEnabled(bool enabled) async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod<void>('setKeepScreenOn', enabled);
    } catch (_) {
      // A platform without the channel falls back to its native path below.
      // 没有该通道的平台继续尝试下面的原生实现。
    }
    if (Platform.isWindows) {
      _setWindows(enabled);
    }
  }

  static void _setWindows(bool enabled) {
    try {
      _setThreadExecutionState ??= DynamicLibrary.open('kernel32.dll')
          .lookupFunction<
            _SetThreadExecutionStateNative,
            _SetThreadExecutionStateDart
          >('SetThreadExecutionState');
      const continuous = 0x80000000;
      const displayRequired = 0x00000002;
      _setThreadExecutionState!(
        enabled ? continuous | displayRequired : continuous,
      );
    } catch (_) {
      // Best effort only; a desktop that ignores this still reads normally.
      // 仅尽力而为；即使系统忽略也不影响阅读。
    }
  }
}
