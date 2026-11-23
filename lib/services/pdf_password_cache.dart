/// In-memory cache for PDF passwords that unlocked a document this session.
/// The cache is cleared on restart. Opt-in storage is managed separately.
/// 在内存中缓存本次运行期间成功解锁 PDF 的密码。
/// 重启会清空缓存，用户主动选择保存的密码由安全存储单独管理。
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
