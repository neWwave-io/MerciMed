import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mime/mime.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:drift/drift.dart' show Value;

import '../../../features/auth/providers/auth_provider.dart';
import '../../../features/family/providers/family_provider.dart';
import '../../../shared/cache/local_db.dart';
import '../../../shared/cache/outbox.dart';
import '../../../shared/models/file_model.dart';
import '../../../shared/models/folder.dart';
import '../../../shared/models/profile.dart';
import '../../../shared/providers/connectivity_provider.dart';

class FolderStats {
  final int fileCount;
  final DateTime? lastUpdated;
  const FolderStats({required this.fileCount, this.lastUpdated});
}

final currentUserProfileProvider = FutureProvider<Profile?>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  // Depend on the auth-aware user provider so this refetches on login.
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;
  final data = await client
      .from('profiles')
      .select()
      .eq('id', user.id)
      .maybeSingle();
  if (data == null) return null;
  return Profile.fromJson(data);
});

/// Local-first stream of ALL folders for the active owner. Reads directly
/// from the drift cache (`lib/shared/cache/local_db.dart`) so the list is
/// available offline and during cold start before Supabase responds. Live
/// reconciliation with the server happens in [_folderHydrationProvider]
/// — UI providers below `.watch` both so hydration starts the moment any
/// folder list is rendered.
///
/// Client-side filtering by parentId / isChat continues at the consumer
/// providers ([foldersProvider], [chatFoldersProvider]).
final _ownerFoldersStreamProvider =
    StreamProvider.autoDispose<List<Folder>>((ref) {
  final db = ref.watch(localDbProvider);
  final ownerId = ref.watch(effectiveOwnerIdProvider);
  if (ownerId == null) return Stream.value(const []);
  // Custom-ordered folders first (ascending sort_order), then anything
  // still NULL (older rows, or freshly created) in creation order.
  return db.watchFoldersForOwner(ownerId).map((folders) {
    final sorted = [...folders]..sort((a, b) {
        final ao = a.sortOrder;
        final bo = b.sortOrder;
        if (ao != null && bo != null) return ao.compareTo(bo);
        if (ao != null) return -1;
        if (bo != null) return 1;
        return a.createdAt.compareTo(b.createdAt);
      });
    return sorted;
  });
});

/// Subscribes to the Supabase `folders` realtime stream and reconciles the
/// drift cache: upserts the server snapshot and tombstones any local row
/// missing from the snapshot UNLESS that row is `dirty` (has a pending
/// outbox write). The provider has no value; consumers `.watch` it purely
/// for the side-effect subscription. Cancelling the subscription when the
/// last consumer goes away is handled by `ref.onDispose`.
final _folderHydrationProvider = Provider.autoDispose<void>((ref) {
  final client = ref.watch(supabaseClientProvider);
  final db = ref.watch(localDbProvider);
  final ownerId = ref.watch(effectiveOwnerIdProvider);
  if (ownerId == null) return;

  final sub = client
      .from('folders')
      .stream(primaryKey: ['id'])
      .eq('user_id', ownerId)
      .listen((rows) async {
        try {
          final folders =
              rows.map<Folder>(Folder.fromJson).toList(growable: false);
          await db.upsertFolders(folders);
          await db.deleteFoldersNotIn(
            ownerId: ownerId,
            keepIds: folders.map((f) => f.id).toSet(),
          );
        } catch (e, st) {
          // Swallow — the next emission will retry. Logging only so we can
          // diagnose recurring reconciler failures.
          debugPrint('folders hydration failed: $e\n$st');
        }
      });
  ref.onDispose(sub.cancel);
});

/// Persists a new ordering for [ordered] by writing `sort_order = index + 1`
/// for each row. The first item in the list ends up at position 1 (top-left
/// in the folder grid). The drift hydration provider picks up the writes
/// on the next realtime emission, so the UI re-sorts automatically.
Future<void> persistFolderOrder(
  SupabaseClient client,
  List<Folder> ordered,
) async {
  if (ordered.isEmpty) return;
  await Future.wait([
    for (var i = 0; i < ordered.length; i++)
      client
          .from('folders')
          .update({'sort_order': i + 1})
          .eq('id', ordered[i].id),
  ]);
}

/// Standard (non-chat) folders under a given parent (null = root). Reads
/// the local drift cache and ensures the server→local reconciler is running
/// while at least one folder list is on screen.
final foldersProvider =
    Provider.autoDispose.family<AsyncValue<List<Folder>>, String?>((ref, parentId) {
  ref.watch(_folderHydrationProvider); // start/keep the reconciler alive
  final all = ref.watch(_ownerFoldersStreamProvider);
  return all.whenData((folders) => folders
      .where((f) => f.parentFolderId == parentId && !f.isChat)
      .toList());
});

/// Folders created automatically when the user uploaded a file inside a
/// chat conversation. Surfaces in the home screen's "Chat Folders" section.
final chatFoldersProvider =
    Provider.autoDispose<AsyncValue<List<Folder>>>((ref) {
  ref.watch(_folderHydrationProvider);
  final all = ref.watch(_ownerFoldersStreamProvider);
  return all.whenData((folders) => folders.where((f) => f.isChat).toList());
});

/// Local-first stream of ALL files for the active owner. Reads from the
/// drift cache so the list is available offline and during cold start.
/// Live reconciliation with Supabase happens in [_fileHydrationProvider]
/// — consumers below `.watch` it so hydration starts the moment any file
/// view is rendered.
final ownerFilesStreamProvider =
    StreamProvider.autoDispose<List<FileModel>>((ref) {
  final db = ref.watch(localDbProvider);
  final ownerId = ref.watch(effectiveOwnerIdProvider);
  if (ownerId == null) return Stream.value(const []);
  return db.watchFilesForOwner(ownerId);
});

/// Subscribes to the Supabase `files` realtime stream and reconciles the
/// drift cache. Mirrors the folder reconciler: upserts the server snapshot
/// and tombstones any local row missing from the snapshot — but ONLY for
/// rows where `dirty = false`. Dirty rows have pending outbox writes that
/// haven't been acked yet; clobbering them would lose user edits.
final _fileHydrationProvider = Provider.autoDispose<void>((ref) {
  final client = ref.watch(supabaseClientProvider);
  final db = ref.watch(localDbProvider);
  final ownerId = ref.watch(effectiveOwnerIdProvider);
  if (ownerId == null) return;

  final sub = client
      .from('files')
      .stream(primaryKey: ['id'])
      .eq('user_id', ownerId)
      .listen((rows) async {
        try {
          final list =
              rows.map<FileModel>(FileModel.fromJson).toList(growable: false);
          await db.upsertFiles(list);
          await db.deleteFilesNotIn(
            ownerId: ownerId,
            keepIds: list.map((f) => f.id).toSet(),
          );
        } catch (e, st) {
          // Swallow — the next emission will retry.
          debugPrint('files hydration failed: $e\n$st');
        }
      });
  ref.onDispose(sub.cancel);
});

final folderStatsProvider =
    Provider.autoDispose<AsyncValue<Map<String, FolderStats>>>((ref) {
  ref.watch(_fileHydrationProvider); // keep reconciler alive
  final files = ref.watch(ownerFilesStreamProvider);
  return files.whenData((list) {
    final stats = <String, FolderStats>{};
    for (final f in list) {
      final fid = f.folderId;
      if (fid == null) continue;
      final cur = stats[fid];
      if (cur == null) {
        stats[fid] = FolderStats(fileCount: 1, lastUpdated: f.createdAt);
      } else {
        final newest =
            (cur.lastUpdated != null && cur.lastUpdated!.isAfter(f.createdAt))
                ? cur.lastUpdated
                : f.createdAt;
        stats[fid] = FolderStats(
          fileCount: cur.fileCount + 1,
          lastUpdated: newest,
        );
      }
    }
    return stats;
  });
});

/// Files inside a given folder (or root when folderId is null).
final filesProvider =
    Provider.autoDispose.family<AsyncValue<List<FileModel>>, String?>((ref, folderId) {
  ref.watch(_fileHydrationProvider); // keep reconciler alive
  final all = ref.watch(ownerFilesStreamProvider);
  return all.whenData(
    (files) => files.where((f) => f.folderId == folderId).toList(),
  );
});

/// Phase-2 contract: folder create/rename/delete still write directly to
/// Supabase and have NO offline path. When offline, the notifier reports a
/// human-readable error on `state` (the UI surfaces this as a SnackBar) and
/// skips the local write entirely. This keeps the v1+v2 write contract
/// simple: file-notes is the only mutation that survives offline.
class OfflineMutationException implements Exception {
  final String message;
  const OfflineMutationException(this.message);
  @override
  String toString() => message;
}

class FolderNotifier extends StateNotifier<AsyncValue<void>> {
  final Ref _ref;
  final SupabaseClient _client;

  FolderNotifier(this._ref, this._client) : super(const AsyncValue.data(null));

  bool get _online => _ref.read(isOnlineProvider);

  Future<void> create(
    String name, {
    String? parentFolderId,
    String? notes,
    bool isChat = false,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    if (!_online) {
      state = AsyncValue.error(
        const OfflineMutationException(
          "You're offline — folder changes will sync when you're back online.",
        ),
        StackTrace.current,
      );
      return;
    }
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final trimmedNotes = notes?.trim();
      await _client.from('folders').insert({
        'user_id': user.id,
        'name': name,
        'parent_folder_id': parentFolderId,
        'is_chat': isChat,
        if (trimmedNotes != null && trimmedNotes.isNotEmpty)
          'notes': trimmedNotes,
      });
      _ref.invalidate(_ownerFoldersStreamProvider);
    });
  }

  /// Ensures a chat-folder exists for the given conversation: returns the
  /// linked folder id if one is already set, otherwise creates a new
  /// `is_chat = true` folder with [name] and stamps `conversation.folder_id`.
  Future<String?> ensureChatFolderForConversation({
    required String conversationId,
    required String name,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    if (!_online) {
      state = AsyncValue.error(
        const OfflineMutationException(
          "You're offline — folder changes will sync when you're back online.",
        ),
        StackTrace.current,
      );
      return null;
    }
    final conv = await _client
        .from('conversations')
        .select('folder_id')
        .eq('id', conversationId)
        .maybeSingle();
    final existing = conv?['folder_id'] as String?;
    if (existing != null && existing.isNotEmpty) return existing;
    final inserted = await _client
        .from('folders')
        .insert({
          'user_id': user.id,
          'name': name.isEmpty ? 'Chat' : name,
          'is_chat': true,
        })
        .select('id')
        .single();
    final folderId = inserted['id'] as String;
    await _client
        .from('conversations')
        .update({'folder_id': folderId})
        .eq('id', conversationId);
    _ref.invalidate(_ownerFoldersStreamProvider);
    return folderId;
  }

  Future<void> rename(String folderId, String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return;
    if (!_online) {
      state = AsyncValue.error(
        const OfflineMutationException(
          "You're offline — folder changes will sync when you're back online.",
        ),
        StackTrace.current,
      );
      return;
    }
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await _client
          .from('folders')
          .update({'name': trimmed})
          .eq('id', folderId);
      _ref.invalidate(_ownerFoldersStreamProvider);
    });
  }

  /// Deletes a folder. Files inside are kept (folder_id set to null via FK
  /// ON DELETE SET NULL) so the user's data isn't lost.
  Future<void> delete(String folderId) async {
    if (!_online) {
      state = AsyncValue.error(
        const OfflineMutationException(
          "You're offline — folder changes will sync when you're back online.",
        ),
        StackTrace.current,
      );
      return;
    }
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await _client.from('folders').delete().eq('id', folderId);
      _ref.invalidate(_ownerFoldersStreamProvider);
    });
  }
}

final folderNotifierProvider =
    StateNotifierProvider<FolderNotifier, AsyncValue<void>>(
  (ref) => FolderNotifier(ref, ref.watch(supabaseClientProvider)),
);

// ── Upload ────────────────────────────────────────────────────────────────────

class UploadState {
  final bool isUploading;
  final String? fileName;
  final double progress; // 0..1, indeterminate when < 0
  final String? errorMessage;

  const UploadState({
    this.isUploading = false,
    this.fileName,
    this.progress = 0,
    this.errorMessage,
  });

  UploadState copyWith({
    bool? isUploading,
    String? fileName,
    double? progress,
    String? errorMessage,
    bool clearError = false,
    bool clearFileName = false,
  }) =>
      UploadState(
        isUploading: isUploading ?? this.isUploading,
        fileName: clearFileName ? null : (fileName ?? this.fileName),
        progress: progress ?? this.progress,
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      );
}

/// Max file size we accept — server-side may still reject larger.
const int kMaxUploadBytes = 20 * 1024 * 1024;

/// A file the user has picked but not yet uploaded — held while we show the
/// preview-and-notes dialog before committing the upload.
class FileUploadDraft {
  final File file;
  final String displayName;
  final String mimeType;
  final int sizeBytes;

  const FileUploadDraft({
    required this.file,
    required this.displayName,
    required this.mimeType,
    required this.sizeBytes,
  });

  bool get isPdf => mimeType.toLowerCase().contains('pdf');
  bool get isImage => mimeType.toLowerCase().startsWith('image/');
}

class UploadNotifier extends StateNotifier<UploadState> {
  final Ref _ref;
  final SupabaseClient _client;

  UploadNotifier(this._ref, this._client) : super(const UploadState());

  bool get _online => _ref.read(isOnlineProvider);

  /// Picks a file and uploads it to the given folder. Returns the new
  /// file's id on success, or null if the user cancelled or it failed.
  /// Opens the system file picker and returns a draft the caller can preview
  /// before kicking off the actual upload. Returns null when the user cancels
  /// or the picked file is unusable; the error message (if any) is on `state`.
  Future<FileUploadDraft?> pickFile() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      state = state.copyWith(errorMessage: 'Please sign in to upload.');
      return null;
    }

    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const [
          'pdf', 'jpg', 'jpeg', 'png', 'heic', 'webp',
        ],
        withData: false,
      );
    } catch (e, st) {
      debugPrint('File picker failed: $e\n$st');
      state = state.copyWith(errorMessage: 'Could not open the file picker: $e');
      return null;
    }
    if (result == null || result.files.isEmpty) return null;

    final picked = result.files.single;
    debugPrint(
      'Picked file: name=${picked.name} path=${picked.path} size=${picked.size}',
    );
    if (picked.path == null) {
      state = state.copyWith(
        errorMessage: 'Could not read file (no path returned).',
      );
      return null;
    }

    final file = File(picked.path!);
    final size = await file.length();
    if (size > kMaxUploadBytes) {
      state = state.copyWith(
        errorMessage:
            'File is too large (${(size / 1024 / 1024).toStringAsFixed(1)} MB). Max is 20 MB.',
      );
      return null;
    }

    final mimeType = lookupMimeType(picked.name) ?? 'application/octet-stream';
    return FileUploadDraft(
      file: file,
      displayName: picked.name,
      mimeType: mimeType,
      sizeBytes: size,
    );
  }

  /// Picks one or more files from the system picker and returns one
  /// [FileUploadDraft] per accepted entry. Mirrors [pickFile]'s validation
  /// (size limit, mime detection) but allows multi-select for the
  /// "Upload files" entry in the add-menu. Drafts that fail validation are
  /// dropped silently from the returned list; if everything fails an error
  /// message is exposed on `state` and `null` is returned.
  Future<List<FileUploadDraft>?> pickFiles({bool allowMultiple = true}) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      state = state.copyWith(errorMessage: 'Please sign in to upload.');
      return null;
    }

    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const [
          'pdf', 'jpg', 'jpeg', 'png', 'heic', 'webp',
        ],
        allowMultiple: allowMultiple,
        withData: false,
      );
    } catch (e, st) {
      debugPrint('File picker (multi) failed: $e\n$st');
      state = state.copyWith(errorMessage: 'Could not open the file picker: $e');
      return null;
    }
    if (result == null || result.files.isEmpty) return null;

    final drafts = <FileUploadDraft>[];
    String? lastError;
    for (final picked in result.files) {
      if (picked.path == null) {
        lastError = 'Could not read ${picked.name} (no path).';
        continue;
      }
      final file = File(picked.path!);
      final size = await file.length();
      if (size > kMaxUploadBytes) {
        lastError =
            '${picked.name} is ${(size / 1024 / 1024).toStringAsFixed(1)} MB — over the 20 MB limit.';
        continue;
      }
      final mimeType =
          lookupMimeType(picked.name) ?? 'application/octet-stream';
      drafts.add(FileUploadDraft(
        file: file,
        displayName: picked.name,
        mimeType: mimeType,
        sizeBytes: size,
      ));
    }
    if (drafts.isEmpty) {
      if (lastError != null) {
        state = state.copyWith(errorMessage: lastError);
      }
      return null;
    }
    return drafts;
  }

  /// Resets a failed (or completed) file back to `pending` and re-invokes the
  /// scan function. Used by the row-level "Retry" button.
  Future<void> retryScan(String fileId) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    final row = await _client
        .from('files')
        .select('id, user_id, storage_path, file_type, file_name')
        .eq('id', fileId)
        .maybeSingle();
    if (row == null) return;
    await _client
        .from('files')
        .update({'ai_scan_status': 'pending'})
        .eq('id', fileId);
    unawaited(_invokeScan(
      fileId: fileId,
      userId: row['user_id'] as String,
      storagePath: row['storage_path'] as String,
      fileType: (row['file_type'] as String?) ?? '',
      displayName: row['file_name'] as String,
    ));
  }

  /// Direct upload (for retries with an existing File handle).
  ///
  /// If the same `(folderId, displayName)` already exists for this user, we
  /// short-circuit and return the existing row's id — avoids stacking up
  /// duplicate `Report_X.pdf` rows when a user re-attaches the same file
  /// to the same chat folder.
  Future<String?> upload({
    required String folderId,
    required File file,
    required String displayName,
    String? notes,
  }) async {
    if (!_online) {
      state = state.copyWith(
        isUploading: false,
        errorMessage:
            "You're offline — uploads will be available when you're back online.",
        clearFileName: true,
      );
      return null;
    }
    final dedupe = await _findExistingFile(
      folderId: folderId,
      displayName: displayName,
    );
    if (dedupe != null) {
      state = const UploadState();
      return dedupe;
    }
    return _doUpload(
      folderId: folderId,
      file: file,
      displayName: displayName,
      notes: notes,
    );
  }

  Future<String?> _findExistingFile({
    required String folderId,
    required String displayName,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    final row = await _client
        .from('files')
        .select('id')
        .eq('user_id', user.id)
        .eq('folder_id', folderId)
        .eq('file_name', displayName)
        .maybeSingle();
    return (row?['id'] as String?);
  }

  Future<String?> _doUpload({
    required String folderId,
    required File file,
    required String displayName,
    String? notes,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) return null;

    state = UploadState(
      isUploading: true,
      fileName: displayName,
      progress: -1, // indeterminate
    );

    try {
      final ext = _ext(displayName);
      final mimeType = lookupMimeType(displayName) ?? 'application/octet-stream';
      final fileType = mimeType;

      // Path: {userId}/{uuid-ish}/{filename}
      final uuid =
          '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-${file.lengthSync().toRadixString(36)}';
      final safeName = displayName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final storagePath = '${user.id}/$uuid/$safeName';

      await _client.storage
          .from('medical-files')
          .upload(
            storagePath,
            file,
            fileOptions: FileOptions(
              contentType: mimeType,
              upsert: false,
            ),
          );

      state = state.copyWith(progress: 0.85);

      final trimmedNotes = notes?.trim();
      final inserted = await _client
          .from('files')
          .insert({
            'user_id': user.id,
            'folder_id': folderId,
            'file_name': displayName,
            'file_type': fileType,
            'storage_path': storagePath,
            'ai_scan_status': 'pending',
            if (trimmedNotes != null && trimmedNotes.isNotEmpty)
              'notes': trimmedNotes,
          })
          .select()
          .single();

      final fileId = inserted['id'] as String;

      // Kick off AI scan. Treat this as fire-and-forget — the function will
      // update ai_scan_status on the row, and Realtime delivers the badge.
      unawaited(_invokeScan(
        fileId: fileId,
        userId: user.id,
        storagePath: storagePath,
        fileType: fileType,
        displayName: displayName,
      ));

      state = state.copyWith(progress: 1.0);

      // No invalidation needed — files list is a live Supabase stream.

      state = const UploadState();
      // Suppress unused-variable warning for `ext` — kept for future routing.
      assert(ext.isEmpty || ext.isNotEmpty);
      return fileId;
    } catch (e, st) {
      debugPrint('Upload failed for $displayName: $e\n$st');
      final reason = e is StorageException
          ? e.message
          : e.toString();
      state = UploadState(
        isUploading: false,
        fileName: displayName,
        errorMessage: 'Upload failed: $reason',
      );
      return null;
    }
  }

  void clearError() => state = state.copyWith(clearError: true);

  Future<void> _invokeScan({
    required String fileId,
    required String userId,
    required String storagePath,
    required String fileType,
    required String displayName,
  }) async {
    try {
      await _client.functions.invoke(
        'scan-medical-file',
        body: {
          'record': {
            'id': fileId,
            'user_id': userId,
            'storage_path': storagePath,
            'file_type': fileType,
            'file_name': displayName,
          },
        },
      );
    } catch (_) {
      // Swallow — Realtime will still surface 'failed' if the function logs
      // the status, otherwise the badge stays 'pending' for retry/UI poll.
    }
  }

  static String _ext(String name) {
    final i = name.lastIndexOf('.');
    if (i < 0 || i == name.length - 1) return '';
    return name.substring(i + 1).toLowerCase();
  }
}

final uploadNotifierProvider =
    StateNotifierProvider<UploadNotifier, UploadState>(
  (ref) => UploadNotifier(ref, ref.watch(supabaseClientProvider)),
);

// ── AI folder name suggestion ────────────────────────────────────────────────

/// Asks the `suggest-folder-name` edge function for a short 2–4-word folder
/// title based on the filename + optional conversation context. Returns null
/// on any failure so the caller can fall back to a safe default.
Future<String?> suggestChatFolderName(
  SupabaseClient client, {
  required String fileName,
  String? message,
  List<Map<String, String>>? history,
}) async {
  try {
    final res = await client.functions.invoke(
      'suggest-folder-name',
      body: {
        'file_name': fileName,
        if (message != null && message.isNotEmpty) 'message': message,
        if (history != null && history.isNotEmpty) 'history': history,
      },
    );
    if (res.status >= 400) return null;
    final data = res.data;
    if (data is Map && data['name'] is String) {
      final name = (data['name'] as String).trim();
      if (name.isNotEmpty) return name;
    }
  } catch (_) {}
  return null;
}

// ── AI note revise ────────────────────────────────────────────────────────────

/// Calls the `revise-note` edge function and returns an improved version of
/// the user's text. Throws with a user-readable message on failure.
Future<String> reviseNote(
  SupabaseClient client,
  String text, {
  String? context,
}) async {
  final res = await client.functions.invoke(
    'revise-note',
    body: {
      'text': text,
      if (context != null && context.isNotEmpty) 'context': context,
    },
  );
  final data = res.data;
  if (res.status >= 400) {
    final msg = (data is Map && data['error'] is String)
        ? data['error'] as String
        : 'AI revise failed (status ${res.status}).';
    throw Exception(msg);
  }
  if (data is Map && data['revised'] is String) {
    final revised = (data['revised'] as String).trim();
    if (revised.isNotEmpty) return revised;
  }
  throw Exception('AI revise returned no text.');
}

// ── File mutations ────────────────────────────────────────────────────────────

/// Write-through update of `files.notes`.
///
/// Step 1 — local: write to drift immediately (marking `dirty = true`) so the
/// UI reflects the new note via [ownerFilesStreamProvider] even offline.
/// Step 2 — network: if online, attempt the Supabase update synchronously.
/// On success we clear `dirty`. On failure (or offline) we enqueue an
/// `update_file_notes` row in the outbox; the [OutboxWorker] drains it on
/// the next connectivity flip with exponential backoff and LWW conflict
/// resolution. Conflicts are surfaced on `outboxWorkerProvider.conflicts`.
///
/// Accepts either a `Ref` or a `WidgetRef` — both expose the `.read`
/// surface this function needs.
Future<void> updateFileNotes(
  WidgetRef ref,
  String fileId,
  String notes,
) async {
  final db = ref.read(localDbProvider);
  final client = ref.read(supabaseClientProvider);
  final online = ref.read(isOnlineProvider);
  final worker = ref.read(outboxWorkerProvider);

  // Step 1: local write. Drift watch re-emits → UI updates instantly.
  await (db.update(db.files)..where((f) => f.id.equals(fileId))).write(
    FilesCompanion(notes: Value(notes), dirty: const Value(true)),
  );

  if (!online) {
    await worker.enqueueUpdateFileNotes(fileId: fileId, notes: notes);
    return;
  }

  try {
    await client.from('files').update({'notes': notes}).eq('id', fileId);
    // Server acknowledged — drop the dirty flag so the reconciler can
    // resume overwriting this row from server snapshots.
    await (db.update(db.files)..where((f) => f.id.equals(fileId)))
        .write(const FilesCompanion(dirty: Value(false)));
  } catch (_) {
    // Transient: defer to the outbox.
    await worker.enqueueUpdateFileNotes(fileId: fileId, notes: notes);
  }
}

/// Single-file lookup for the detail screen — derived from the same live
/// stream so notes/scan-status updates appear immediately.
final fileByIdProvider =
    Provider.autoDispose.family<AsyncValue<FileModel?>, String>((ref, id) {
  ref.watch(_fileHydrationProvider); // keep reconciler alive
  final all = ref.watch(ownerFilesStreamProvider);
  return all.whenData((files) {
    for (final f in files) {
      if (f.id == id) return f;
    }
    return null;
  });
});
