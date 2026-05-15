// Hand-written Folder model. snake_case in JSON/DB, camelCase in Dart.
//
// Bridges:
//   • fromJson / toJson  — Supabase REST + Realtime payloads.
//   • fromDriftRow / toDriftCompanion — local drift cache (see
//     lib/shared/cache/local_db.dart). Drift is the ONE place codegen is
//     allowed in this repo; everywhere else we keep manual serialisation.

import 'package:drift/drift.dart' show Value;

import '../cache/local_db.dart';

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

  /// Construct from a drift row (`DriftFolderRow` is the generated data
  /// class for the [Folders] table — see local_db.dart).
  factory Folder.fromDriftRow(DriftFolderRow r) => Folder(
        id: r.id,
        userId: r.userId,
        name: r.name,
        parentFolderId: r.parentFolderId,
        notes: r.notes,
        isChat: r.isChat,
        createdAt: r.createdAt,
      );

  /// Build a drift insert companion. The `dirty` flag is left absent so the
  /// table default (`false`) wins for server-originated writes. Outbox
  /// flows should set `dirty: Value(true)` explicitly.
  FoldersCompanion toDriftCompanion({bool dirty = false}) =>
      FoldersCompanion.insert(
        id: id,
        userId: userId,
        name: name,
        parentFolderId: Value(parentFolderId),
        notes: Value(notes),
        isChat: Value(isChat),
        createdAt: createdAt,
        dirty: Value(dirty),
      );
}
