/// A user-visible shelf folder that groups books imported from one directory.
/// 书架文件夹：用于归组从同一目录导入的漫画。
class LibraryFolder {
  LibraryFolder({required this.id, required this.name, DateTime? createdAt})
    : createdAt = createdAt ?? DateTime.now();

  final String id;
  String name;
  final DateTime createdAt;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'createdAt': createdAt.toIso8601String(),
  };

  factory LibraryFolder.fromJson(Map<String, Object?> json) {
    final rawId = json['id'];
    final rawName = json['name'];
    final rawCreated = json['createdAt'];
    return LibraryFolder(
      id: rawId is String ? rawId : '',
      name: (rawName is String ? rawName : '文件夹').trim(),
      createdAt:
          DateTime.tryParse(rawCreated is String ? rawCreated : '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
