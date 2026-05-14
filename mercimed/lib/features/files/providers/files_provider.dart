import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
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
  final user = client.auth.currentUser;
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
      .map((rows) => rows.map(Folder.fromJson).toList());
});

/// Folders under a given parent (null = root). Reactively follows
/// [_ownerFoldersStreamProvider].
final foldersProvider =
    Provider.autoDispose.family<AsyncValue<List<Folder>>, String?>((ref, parentId) {
  final all = ref.watch(_ownerFoldersStreamProvider);
  return all.whenData((folders) =>
      folders.where((f) => f.parentFolderId == parentId).toList());
});

/// Live stream of ALL files for the active owner. Used as the basis for
/// both per-folder file lists and folder stats.
final _ownerFilesStreamProvider =
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
  final files = ref.watch(_ownerFilesStreamProvider);
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
  final all = ref.watch(_ownerFilesStreamProvider);
  return all.whenData(
    (files) => files.where((f) => f.folderId == folderId).toList(),
  );
});

class FolderNotifier extends StateNotifier<AsyncValue<void>> {
  final SupabaseClient _client;

  FolderNotifier(this._client) : super(const AsyncValue.data(null));

  Future<void> create(String name, {String? parentFolderId}) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await _client.from('folders').insert({
        'user_id': user.id,
        'name': name,
        'parent_folder_id': parentFolderId,
      });
      // No invalidation needed — foldersProvider is a live Supabase stream.
    });
  }
}

final folderNotifierProvider =
    StateNotifierProvider<FolderNotifier, AsyncValue<void>>(
  (ref) => FolderNotifier(ref.watch(supabaseClientProvider)),
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

class UploadNotifier extends StateNotifier<UploadState> {
  final SupabaseClient _client;

  UploadNotifier(this._client) : super(const UploadState());

  /// Picks a file and uploads it to the given folder. Returns the new
  /// file's id on success, or null if the user cancelled or it failed.
  Future<String?> pickAndUpload(String folderId) async {
    final user = _client.auth.currentUser;
    if (user == null) return null;

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'heic', 'webp'],
      withData: false,
    );
    if (result == null || result.files.isEmpty) return null;
    final picked = result.files.single;
    if (picked.path == null) {
      state = state.copyWith(errorMessage: 'Could not read file.');
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

    return upload(folderId: folderId, file: file, displayName: picked.name);
  }

  /// Direct upload (for retries with an existing File handle).
  Future<String?> upload({
    required String folderId,
    required File file,
    required String displayName,
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

      final inserted = await _client
          .from('files')
          .insert({
            'user_id': user.id,
            'folder_id': folderId,
            'file_name': displayName,
            'file_type': fileType,
            'storage_path': storagePath,
            'ai_scan_status': 'pending',
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
    } catch (e) {
      state = UploadState(
        isUploading: false,
        fileName: displayName,
        errorMessage: 'Upload failed. Tap to retry.',
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
  final all = ref.watch(_ownerFilesStreamProvider);
  return all.whenData((files) {
    for (final f in files) {
      if (f.id == id) return f;
    }
    return null;
  });
});
