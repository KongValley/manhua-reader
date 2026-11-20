/// Session-only storage for successfully used PDF passwords.
///
/// Passwords are intentionally kept in memory only: they are never written to
/// the library JSON or any other file. Restarting the app requires the user to
/// enter them again.
/// 仅在本次会话内保存成功使用的 PDF 密码。
///
/// 密码只保存在内存中：绝不会写入 library.json 或任何其他文件。
/// 重启应用后需要用户重新输入。
class PdfPasswordCache {
  PdfPasswordCache._();

  static final Map<String, String> _passwords = {};

  static String? get(String filePath) => _passwords[filePath];

  static void put(String filePath, String? password) {
    if (password == null || password.isEmpty) return;
    _passwords[filePath] = password;
  }

  static void remove(String filePath) {
    _passwords.remove(filePath);
  }

  static void clear() {
    _passwords.clear();
  }
}
