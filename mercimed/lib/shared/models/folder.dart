class Folder {
  final String id;
  final String userId;
  final String name;
  final String? parentFolderId;
  final String? notes;
  final bool isChat;
  final DateTime createdAt;

  const Folder({
    required this.id,
    required this.userId,
    required this.name,
    this.parentFolderId,
    this.notes,
    this.isChat = false,
    required this.createdAt,
  });

  factory Folder.fromJson(Map<String, dynamic> json) => Folder(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        name: json['name'] as String,
        parentFolderId: json['parent_folder_id'] as String?,
        notes: json['notes'] as String?,
        isChat: (json['is_chat'] as bool?) ?? false,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'name': name,
        'parent_folder_id': parentFolderId,
        'notes': notes,
        'is_chat': isChat,
        'created_at': createdAt.toIso8601String(),
      };
}
