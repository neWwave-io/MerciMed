class ChatMessage {
  final String id;
  final String userId;
  final String? conversationId;
  final String role;
  final String content;
  final DateTime createdAt;

  const ChatMessage({
    required this.id,
    required this.userId,
    this.conversationId,
    required this.role,
    required this.content,
    required this.createdAt,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        conversationId: json['conversation_id'] as String?,
        role: json['role'] as String,
        content: json['content'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'conversation_id': conversationId,
        'role': role,
        'content': content,
        'created_at': createdAt.toIso8601String(),
      };
}
