// Hand-written Conversation model.
//
// Bridges:
//   • fromJson — Supabase REST + Realtime payloads (no toJson — we never
//     write the whole row from the client; inserts happen via partial
//     `_client.from('conversations').insert({...})` calls).
//   • fromDriftRow / toDriftCompanion — local drift cache.

import 'package:drift/drift.dart' show Value;

import '../cache/local_db.dart';

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

  factory Conversation.fromDriftRow(DriftConversationRow r) => Conversation(
        id: r.id,
        userId: r.userId,
        title: r.title,
        folderId: r.folderId,
        createdAt: r.createdAt,
        updatedAt: r.updatedAt,
      );

  ConversationsCompanion toDriftCompanion() => ConversationsCompanion.insert(
        id: id,
        userId: userId,
        title: Value(title),
        folderId: Value(folderId),
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}
