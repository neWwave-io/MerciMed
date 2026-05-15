class Conversation {
  final String id;
  final String userId;
  final String? title;
  final String? folderId;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Conversation({
    required this.id,
    required this.userId,
    this.title,
    this.folderId,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Conversation.fromJson(Map<String, dynamic> json) => Conversation(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        title: json['title'] as String?,
        folderId: json['folder_id'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );
}
