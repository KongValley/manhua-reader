import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../models/comic_book.dart';
import 'pdf_password_cache.dart';

/// Per-book PDF credentials backed by the platform's local secret store.
/// 通过平台本机安全存储保存每本 PDF 的密码。
class PdfPasswordStore {
  PdfPasswordStore._();

  static const _channel = MethodChannel('manhua/pdf_password_store');
  static final _generations = Expando<Object>();

  static bool get isSupported {
    if (kIsWeb) return false;
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.windows) {
      return false;
    }
    // Background tests and early startup may run before the binding exists.
    // 后台测试和启动早期可能还没有初始化绑定。
    try {
      ServicesBinding.instance.defaultBinaryMessenger;
      return true;
    } catch (_) {
      return false;
    }
  }

  // The stored filename changes on relink and survives app directory moves.
  // 重新定位会更改存储文件名，应用目录迁移则不会更改该文件名。
  static String _key(ComicBook book, String filePath) =>
      jsonEncode([book.id, p.basename(filePath)]);

  static Object generation(ComicBook book) => _generations[book] ??= Object();

  static Future<bool> hasRemembered(ComicBook book) async {
    if (!isSupported || book.format != ComicFormat.pdf) return false;
    try {
      return await _channel.invokeMethod<bool>('contains', {
            'key': _key(book, book.filePath),
          }) ??
          false;
    } catch (_) {
      // Missing plugins or a missing binding both mean "not available".
      // 插件缺失或绑定未初始化都表示「不可用」。
      return false;
    }
  }

  static Future<String?> read(ComicBook book, String filePath) async {
    if (!isSupported || book.format != ComicFormat.pdf) return null;
    try {
      return await _channel.invokeMethod<String>('read', {
        'key': _key(book, filePath),
      });
    } catch (_) {
      return null;
    }
  }

  static Future<bool> remember(ComicBook book, String password) async {
    if (!isSupported || book.format != ComicFormat.pdf) return false;
    return _mutate('write', _key(book, book.filePath), password: password);
  }

  /// Clears this copy's password and invalidates credentials in open attempts.
  /// 清除该文件副本的密码，并使正在进行的打开操作中的旧密码失效。
  static Future<bool> forget(ComicBook book, {String? filePath}) async {
    final path = filePath ?? book.filePath;
    _generations[book] = Object();
    PdfPasswordCache.remove(path);
    if (!isSupported || book.format != ComicFormat.pdf) return true;
    return _mutate('delete', _key(book, path));
  }

  /// Removes a rejected stored password only while it is still the same value.
  /// 仅在保存的密码仍是这次被拒绝的值时将其移除。
  static Future<void> reject(
    ComicBook book,
    String filePath,
    String password,
  ) async {
    if (!isSupported || book.format != ComicFormat.pdf) return;
    await _mutate('delete', _key(book, filePath), password: password);
  }

  static Future<bool> _mutate(
    String method,
    String key, {
    String? password,
  }) async {
    try {
      await _channel.invokeMethod<void>(method, {
        'key': key,
        'password': ?password,
      });
      return true;
    } catch (_) {
      return false;
    }
  }
}
