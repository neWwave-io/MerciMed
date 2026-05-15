// Drift-backed offline cache for MerciMed.
//
// This is the ONE place codegen is allowed in the repo (see CLAUDE.md).
// Everywhere else we hand-write fromJson/toJson on the model classes.
//
// To regenerate:
//   dart run build_runner build --delete-conflicting-outputs
//
// Tables here mirror the Postgres schema for the entities we cache today
// (folders, files, conversations, chat_messages) plus two app-internal
// tables: BlobCache (for downloaded medical-files blobs) and Outbox (for
// queued mutations that need to replay once the device is back online).

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// drift brings `path` in transitively; importing directly is cleaner than
// open-coding string joins. Lint suppression mirrors blob_cache.dart.
// ignore: depend_on_referenced_packages
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/chat_message.dart';
import '../models/conversation.dart';
import '../models/file_model.dart';
import '../models/folder.dart';

part 'local_db.g.dart';

// ── Tables ────────────────────────────────────────────────────────────────────
//
// Drift generates a data class per table whose default name is the singular
// of the table class. That collides with our hand-written model classes
// (Folder, FileModel, etc.), so we override every data class name with the
// `Drift…Row` suffix and bridge in code.

@DataClassName('DriftFolderRow')
class Folders extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text().named('user_id')();
  TextColumn get name => text()();
  TextColumn get parentFolderId =>
      text().named('parent_folder_id').nullable()();
  TextColumn get notes => text().nullable()();
  BoolColumn get isChat => boolean().named('is_chat').withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().named('created_at')();
  BoolColumn get dirty => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('DriftFileRow')
class Files extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text().named('user_id')();
  TextColumn get folderId => text().named('folder_id').nullable()();
  TextColumn get fileName => text().named('file_name')();
  TextColumn get fileType => text().named('file_type').nullable()();
  TextColumn get storagePath => text().named('storage_path')();
  TextColumn get extractedText => text().named('extracted_text').nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get aiScanStatus =>
      text().named('ai_scan_status').withDefault(const Constant('pending'))();
  DateTimeColumn get createdAt => dateTime().named('created_at')();
  BoolColumn get dirty => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('DriftConversationRow')
class Conversations extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text().named('user_id')();
  TextColumn get title => text().nullable()();
  TextColumn get folderId => text().named('folder_id').nullable()();
  DateTimeColumn get createdAt => dateTime().named('created_at')();
  DateTimeColumn get updatedAt => dateTime().named('updated_at')();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('DriftChatMessageRow')
class ChatMessages extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text().named('user_id')();
  TextColumn get conversationId =>
      text().named('conversation_id').nullable()();
  TextColumn get role => text()();
  TextColumn get content => text()();
  DateTimeColumn get createdAt => dateTime().named('created_at')();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('DriftBlobCacheRow')
class BlobCache extends Table {
  TextColumn get storagePath => text().named('storage_path')();
  TextColumn get localPath => text().named('local_path')();
  TextColumn get sha256 => text()();
  IntColumn get sizeBytes => integer().named('size_bytes')();
  DateTimeColumn get lastUsedAt => dateTime().named('last_used_at')();

  @override
  Set<Column> get primaryKey => {storagePath};
}

@DataClassName('DriftOutboxRow')
class Outbox extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get op => text()(); // e.g. 'update_file_notes'
  // Drift reserves the getter name `tableName` on Table subclasses, so we
  // store the target table under `targetTable` and expose `table_name`
  // via the column name.
  TextColumn get targetTable => text().named('table_name')();
  TextColumn get rowJson => text().named('row_json')();
  DateTimeColumn get createdAt => dateTime().named('created_at')();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().named('last_error').nullable()();
}

// ── Database ─────────────────────────────────────────────────────────────────

@DriftDatabase(tables: [
  Folders,
  Files,
  Conversations,
  ChatMessages,
  BlobCache,
  Outbox,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());
  AppDatabase.withExecutor(super.e);

  @override
  int get schemaVersion => 1;

  // ── Folders ────────────────────────────────────────────────────────────────

  /// Streams the full folder list for [userId], ordered by creation time so
  /// the UI matches what Supabase returns. Filtering by parentId / isChat
  /// happens client-side (matching the Supabase `.stream()` pattern).
  Stream<List<Folder>> watchFoldersForOwner(String userId) {
    final query = select(folders)
      ..where((f) => f.userId.equals(userId))
      ..orderBy([(f) => OrderingTerm.asc(f.createdAt)]);
    return query.watch().map(
          (rows) => rows.map(_folderFromRow).toList(growable: false),
        );
  }

  /// Upserts a batch of folders. Used by the Supabase→drift reconciler.
  /// Skips rows that are marked `dirty` locally — those have pending writes
  /// not yet acked by the server, so we don't want to overwrite them.
  ///
  /// SQLite UPSERT with `WHERE` lets us guard the update: if `dirty=true`
  /// the conflict is kept silent (old row stays), if `dirty=false` we apply
  /// the incoming server values.
  Future<void> upsertFolders(List<Folder> incoming) async {
    if (incoming.isEmpty) return;
    await batch((b) {
      for (final f in incoming) {
        b.insert(
          folders,
          FoldersCompanion.insert(
            id: f.id,
            userId: f.userId,
            name: f.name,
            parentFolderId: Value(f.parentFolderId),
            notes: Value(f.notes),
            isChat: Value(f.isChat),
            createdAt: f.createdAt,
          ),
          // Don't clobber a row currently dirty (pending outbox write).
          // `old` is the user-defined Folders table DSL; columns can be
          // null in the static DSL view, but at runtime drift's UPSERT
          // SQL wires the WHERE against the actual generated column.
          onConflict: DoUpdate<Folders, DriftFolderRow>(
            (old) => FoldersCompanion(
              userId: Value(f.userId),
              name: Value(f.name),
              parentFolderId: Value(f.parentFolderId),
              notes: Value(f.notes),
              isChat: Value(f.isChat),
              createdAt: Value(f.createdAt),
            ),
            where: (old) => old.dirty.equals(false),
          ),
        );
      }
    });
  }

  /// Tombstones any local folder owned by [ownerId] whose id is not in
  /// [keepIds] AND is not currently `dirty`. Dirty rows are preserved so
  /// pending local creates aren't lost mid-sync.
  Future<void> deleteFoldersNotIn({
    required String ownerId,
    required Set<String> keepIds,
  }) async {
    await (delete(folders)
          ..where((f) =>
              f.userId.equals(ownerId) &
              f.dirty.equals(false) &
              f.id.isNotIn(keepIds)))
        .go();
  }

  Folder _folderFromRow(DriftFolderRow r) => Folder(
        id: r.id,
        userId: r.userId,
        name: r.name,
        parentFolderId: r.parentFolderId,
        notes: r.notes,
        isChat: r.isChat,
        createdAt: r.createdAt,
      );

  // ── Files ──────────────────────────────────────────────────────────────────

  /// Streams the full file list for [userId], newest first — mirrors the
  /// Supabase `.order('created_at', ascending: false)` ordering so the UI
  /// sees the same shape whether the source is the network or the cache.
  Stream<List<FileModel>> watchFilesForOwner(String userId) {
    final query = select(files)
      ..where((f) => f.userId.equals(userId))
      ..orderBy([(f) => OrderingTerm.desc(f.createdAt)]);
    return query.watch().map(
          (rows) => rows.map(FileModel.fromDriftRow).toList(growable: false),
        );
  }

  /// Upserts a batch of files. Rows currently `dirty` are preserved (they
  /// have pending outbox writes that haven't been acked by the server yet).
  Future<void> upsertFiles(List<FileModel> incoming) async {
    if (incoming.isEmpty) return;
    await batch((b) {
      for (final f in incoming) {
        b.insert(
          files,
          FilesCompanion.insert(
            id: f.id,
            userId: f.userId,
            folderId: Value(f.folderId),
            fileName: f.fileName,
            fileType: Value(f.fileType),
            storagePath: f.storagePath,
            extractedText: Value(f.extractedText),
            notes: Value(f.notes),
            aiScanStatus: Value(f.aiScanStatus),
            createdAt: f.createdAt,
          ),
          onConflict: DoUpdate<Files, DriftFileRow>(
            (old) => FilesCompanion(
              userId: Value(f.userId),
              folderId: Value(f.folderId),
              fileName: Value(f.fileName),
              fileType: Value(f.fileType),
              storagePath: Value(f.storagePath),
              extractedText: Value(f.extractedText),
              notes: Value(f.notes),
              aiScanStatus: Value(f.aiScanStatus),
              createdAt: Value(f.createdAt),
            ),
            where: (old) => old.dirty.equals(false),
          ),
        );
      }
    });
  }

  /// Tombstones any local file owned by [ownerId] not in [keepIds] AND not
  /// currently `dirty`. Dirty rows are preserved so pending local writes
  /// aren't lost mid-sync.
  Future<void> deleteFilesNotIn({
    required String ownerId,
    required Set<String> keepIds,
  }) async {
    await (delete(files)
          ..where((f) =>
              f.userId.equals(ownerId) &
              f.dirty.equals(false) &
              f.id.isNotIn(keepIds)))
        .go();
  }

  /// Single-file lookup from the local cache.
  Future<FileModel?> fileById(String id) async {
    final row = await (select(files)..where((f) => f.id.equals(id)))
        .getSingleOrNull();
    return row == null ? null : FileModel.fromDriftRow(row);
  }

  // ── Conversations ──────────────────────────────────────────────────────────

  /// Streams conversations for [userId], newest-first by `updated_at` to
  /// match the Supabase stream ordering.
  Stream<List<Conversation>> watchConversationsForOwner(String userId) {
    final query = select(conversations)
      ..where((c) => c.userId.equals(userId))
      ..orderBy([(c) => OrderingTerm.desc(c.updatedAt)]);
    return query.watch().map(
          (rows) =>
              rows.map(Conversation.fromDriftRow).toList(growable: false),
        );
  }

  Future<void> upsertConversations(List<Conversation> incoming) async {
    if (incoming.isEmpty) return;
    await batch((b) {
      for (final c in incoming) {
        b.insert(
          conversations,
          ConversationsCompanion.insert(
            id: c.id,
            userId: c.userId,
            title: Value(c.title),
            folderId: Value(c.folderId),
            createdAt: c.createdAt,
            updatedAt: c.updatedAt,
          ),
          // Conversations don't carry a `dirty` flag in v1+v2 (no offline
          // write path for them yet), so a server snapshot always wins.
          onConflict: DoUpdate<Conversations, DriftConversationRow>(
            (old) => ConversationsCompanion(
              userId: Value(c.userId),
              title: Value(c.title),
              folderId: Value(c.folderId),
              createdAt: Value(c.createdAt),
              updatedAt: Value(c.updatedAt),
            ),
          ),
        );
      }
    });
  }

  Future<void> deleteConversationsNotIn({
    required String ownerId,
    required Set<String> keepIds,
  }) async {
    await (delete(conversations)
          ..where((c) =>
              c.userId.equals(ownerId) & c.id.isNotIn(keepIds)))
        .go();
  }

  // ── Chat messages ──────────────────────────────────────────────────────────

  /// Streams messages for a given conversation, oldest first (the UI sorts
  /// the in-memory slice further by `(createdAt, role tie-break)` — see
  /// chat_provider.dart). We mirror the server `.order('created_at')`.
  Stream<List<ChatMessage>> watchMessagesForConversation(String conversationId) {
    final query = select(chatMessages)
      ..where((m) => m.conversationId.equals(conversationId))
      ..orderBy([(m) => OrderingTerm.asc(m.createdAt)]);
    return query.watch().map(
          (rows) =>
              rows.map(ChatMessage.fromDriftRow).toList(growable: false),
        );
  }

  Future<void> upsertMessages(List<ChatMessage> incoming) async {
    if (incoming.isEmpty) return;
    await batch((b) {
      for (final m in incoming) {
        b.insert(
          chatMessages,
          ChatMessagesCompanion.insert(
            id: m.id,
            userId: m.userId,
            conversationId: Value(m.conversationId),
            role: m.role,
            content: m.content,
            createdAt: m.createdAt,
          ),
          onConflict: DoUpdate<ChatMessages, DriftChatMessageRow>(
            (old) => ChatMessagesCompanion(
              userId: Value(m.userId),
              conversationId: Value(m.conversationId),
              role: Value(m.role),
              content: Value(m.content),
              createdAt: Value(m.createdAt),
            ),
          ),
        );
      }
    });
  }

  /// Tombstones any local message for [conversationId] missing from
  /// [keepIds]. Scoped to a single conversation so we don't accidentally
  /// wipe other conversations' caches while their hydration provider is
  /// asleep.
  Future<void> deleteMessagesNotIn({
    required String conversationId,
    required Set<String> keepIds,
  }) async {
    await (delete(chatMessages)
          ..where((m) =>
              m.conversationId.equals(conversationId) &
              m.id.isNotIn(keepIds)))
        .go();
  }

  // ── Owner-scoped wipe ──────────────────────────────────────────────────────

  /// Drops every cached row that belongs to [userId]: folders, files,
  /// conversations, and chat messages. Called from the sign-out path to
  /// ensure the next user that signs in on this device doesn't see the
  /// previous user's data. The Outbox is left alone — pending writes belong
  /// to the old account anyway; the worker will surface the conflict when
  /// it next attempts to drain.
  ///
  /// `BlobCache` rows are NOT keyed by user, so they stay; the next blob
  /// open from a different account will be a fresh entry on a different
  /// `storage_path`. A future eviction pass can prune by mtime.
  Future<void> wipeOwner(String userId) async {
    await transaction(() async {
      await (delete(folders)..where((f) => f.userId.equals(userId))).go();
      await (delete(files)..where((f) => f.userId.equals(userId))).go();
      await (delete(chatMessages)..where((m) => m.userId.equals(userId))).go();
      await (delete(conversations)..where((c) => c.userId.equals(userId))).go();
    });
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationSupportDirectory();
    final dbFile = File(p.join(dir.path, 'merci_med.sqlite'));
    return NativeDatabase.createInBackground(dbFile);
  });
}

// ── Riverpod ─────────────────────────────────────────────────────────────────

/// Singleton AppDatabase for the app's lifetime. Intentionally NOT autoDispose
/// — opening sqlite + warming the connection on every screen would thrash.
final localDbProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});
