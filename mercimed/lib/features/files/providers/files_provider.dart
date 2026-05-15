import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mime/mime.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../features/auth/providers/auth_provider.dart';
import '../../../features/family/providers/family_provider.dart';
import '../../../shared/models/file_model.dart';
import '../../../shared/models/folder.dart';
import '../../../shared/models/profile.dart';

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

/// Live stream of ALL folders for the active owner. Client filters by
/// parentId since Supabase `.stream()` only allows a single `.eq()` filter.
final _ownerFoldersStreamProvider =
    StreamProvider.autoDispose<List<Folder>>((ref) {
  final client = ref.watch(supabaseClientProvider);
  final ownerId = ref.watch(effectiveOwnerIdProvider);
  if (ownerId == null) return Stream.value(const []);

  return client
      .from('folders')
      .stream(primaryKey: ['id'])
      .eq('user_id', ownerId)
      .order('created_at')
      .map((rows) {
        final folders = rows.map(Folder.fromJson).toList();
        // Custom-ordered folders first (ascending sort_order), then
        // anything still NULL (older rows, or freshly created) in
        // creation order — which the server already returned.
        folders.sort((a, b) {
          final ao = a.sortOrder;
          final bo = b.sortOrder;
          if (ao != null && bo != null) return ao.compareTo(bo);
          if (ao != null) return -1;
          if (bo != null) return 1;
          return a.createdAt.compareTo(b.createdAt);
        });
        return folders;
      });
});

/// Persists a new ordering for [ordered] by writing `sort_order = index + 1`
/// for each row. The first item in the list ends up at position 1 (top-left
/// in the folder grid).
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

/// Standard (non-chat) folders under a given parent (null = root).
/// Reactively follows [_ownerFoldersStreamProvider]. Chat-auto-created
/// folders are filtered out and shown separately via [chatFoldersProvider].
final foldersProvider =
    Provider.autoDispose.family<AsyncValue<List<Folder>>, String?>((ref, parentId) {
  final all = ref.watch(_ownerFoldersStreamProvider);
  return all.whenData((folders) => folders
      .where((f) => f.parentFolderId == parentId && !f.isChat)
      .toList());
});

/// Folders created automatically when the user uploaded a file inside a
/// chat conversation. Surfaces in the home screen's "Chat Folders" section.
final chatFoldersProvider =
    Provider.autoDispose<AsyncValue<List<Folder>>>((ref) {
  final all = ref.watch(_ownerFoldersStreamProvider);
  return all.whenData((folders) => folders.where((f) => f.isChat).toList());
});

/// Live stream of ALL files for the active owner. Used as the basis for
/// both per-folder file lists and folder stats.
final ownerFilesStreamProvider =
    StreamProvider.autoDispose<List<FileModel>>((ref) {
  final client = ref.watch(supabaseClientProvider);
  final ownerId = ref.watch(effectiveOwnerIdProvider);
  if (ownerId == null) return Stream.value(const []);

  return client
      .from('files')
      .stream(primaryKey: ['id'])
      .eq('user_id', ownerId)
      .order('created_at', ascending: false)
      .map((rows) => rows.map(FileModel.fromJson).toList());
});

final folderStatsProvider =
    Provider.autoDispose<AsyncValue<Map<String, FolderStats>>>((ref) {
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
  final all = ref.watch(ownerFilesStreamProvider);
  return all.whenData(
    (files) => files.where((f) => f.folderId == folderId).toList(),
  );
});

class FolderNotifier extends StateNotifier<AsyncValue<void>> {
  final Ref _ref;
  final SupabaseClient _client;

  FolderNotifier(this._ref, this._client) : super(const AsyncValue.data(null));

  Future<void> create(
    String name, {
    String? parentFolderId,
    String? notes,
    bool isChat = false,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
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
  final SupabaseClient _client;

  UploadNotifier(this._client) : super(const UploadState());

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
  (ref) => UploadNotifier(ref.watch(supabaseClientProvider)),
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

/// Updates the notes field on a file row. Used by file detail screen with
/// debouncing handled at the call site.
Future<void> updateFileNotes(
  SupabaseClient client,
  String fileId,
  String notes,
) {
  return client
      .from('files')
      .update({'notes': notes}) // null-safe text column
      .eq('id', fileId);
}

/// Single-file lookup for the detail screen — derived from the same live
/// stream so notes/scan-status updates appear immediately.
final fileByIdProvider =
    Provider.autoDispose.family<AsyncValue<FileModel?>, String>((ref, id) {
  final all = ref.watch(ownerFilesStreamProvider);
  return all.whenData((files) {
    for (final f in files) {
      if (f.id == id) return f;
    }
    return null;
  });
});
