// Hand-written FileModel. snake_case in JSON/DB, camelCase in Dart.
//
// Bridges:
//   • fromJson / toJson  — Supabase REST + Realtime payloads.
//   • fromDriftRow / toDriftCompanion — local drift cache (see
//     lib/shared/cache/local_db.dart). Drift is the ONE place codegen is
//     allowed in this repo; everywhere else we keep manual serialisation.

import 'package:drift/drift.dart' show Value;

import '../cache/local_db.dart';

class FileModel {
  final String id;
  final String userId;
  final String? folderId;
  final String fileName;
  final String? fileType;
  final String storagePath;
  final String? extractedText;
  final String? notes;
  final String aiScanStatus;
  final DateTime createdAt;

  const FileModel({
    required this.id,
    required this.userId,
    this.folderId,
    required this.fileName,
    this.fileType,
    required this.storagePath,
    this.extractedText,
    this.notes,
    required this.aiScanStatus,
    required this.createdAt,
  });

  factory FileModel.fromJson(Map<String, dynamic> json) => FileModel(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        folderId: json['folder_id'] as String?,
        fileName: json['file_name'] as String,
        fileType: json['file_type'] as String?,
        storagePath: json['storage_path'] as String,
        extractedText: json['extracted_text'] as String?,
        notes: json['notes'] as String?,
        aiScanStatus: json['ai_scan_status'] as String? ?? 'pending',
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'folder_id': folderId,
        'file_name': fileName,
        'file_type': fileType,
        'storage_path': storagePath,
        'extracted_text': extractedText,
        'notes': notes,
        'ai_scan_status': aiScanStatus,
        'created_at': createdAt.toIso8601String(),
      };

  /// Construct from a drift row (`DriftFileRow` is the generated data class
  /// for the [Files] table — see local_db.dart).
  factory FileModel.fromDriftRow(DriftFileRow r) => FileModel(
        id: r.id,
        userId: r.userId,
        folderId: r.folderId,
        fileName: r.fileName,
        fileType: r.fileType,
        storagePath: r.storagePath,
        extractedText: r.extractedText,
        notes: r.notes,
        aiScanStatus: r.aiScanStatus,
        createdAt: r.createdAt,
      );

  /// Build a drift insert companion. The `dirty` flag is left at the column
  /// default (`false`) for server-originated writes; the outbox flow sets it
  /// to `true` explicitly when persisting an offline mutation.
  FilesCompanion toDriftCompanion({bool dirty = false}) =>
      FilesCompanion.insert(
        id: id,
        userId: userId,
        folderId: Value(folderId),
        fileName: fileName,
        fileType: Value(fileType),
        storagePath: storagePath,
        extractedText: Value(extractedText),
        notes: Value(notes),
        aiScanStatus: Value(aiScanStatus),
        createdAt: createdAt,
        dirty: Value(dirty),
      );

  FileModel copyWith({
    String? id,
    String? userId,
    String? folderId,
    String? fileName,
    String? fileType,
    String? storagePath,
    String? extractedText,
    String? notes,
    String? aiScanStatus,
    DateTime? createdAt,
  }) =>
      FileModel(
        id: id ?? this.id,
        userId: userId ?? this.userId,
        folderId: folderId ?? this.folderId,
        fileName: fileName ?? this.fileName,
        fileType: fileType ?? this.fileType,
        storagePath: storagePath ?? this.storagePath,
        extractedText: extractedText ?? this.extractedText,
        notes: notes ?? this.notes,
        aiScanStatus: aiScanStatus ?? this.aiScanStatus,
        createdAt: createdAt ?? this.createdAt,
      );
}
