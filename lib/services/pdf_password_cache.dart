/// Session-only storage for successfully used PDF passwords.
///
/// Passwords are intentionally kept in memory only: they are never written to
/// the library JSON or any other file. Restarting the app requires the user to
/// enter them again.
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
