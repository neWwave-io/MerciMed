import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../features/auth/providers/auth_provider.dart';
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

final foldersProvider =
    FutureProvider.family<List<Folder>, String?>((ref, parentId) async {
  final client = ref.watch(supabaseClientProvider);
  final user = client.auth.currentUser;
  if (user == null) return [];

  final base = client.from('folders').select().eq('user_id', user.id);
  final raw = parentId == null
      ? await base.isFilter('parent_folder_id', null).order('created_at')
      : await base.eq('parent_folder_id', parentId).order('created_at');

  return (raw as List)
      .map((e) => Folder.fromJson(e as Map<String, dynamic>))
      .toList();
});

final folderStatsProvider =
    FutureProvider<Map<String, FolderStats>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final user = client.auth.currentUser;
  if (user == null) return {};

  final raw = await client
      .from('files')
      .select('folder_id, created_at')
      .eq('user_id', user.id)
      .not('folder_id', 'is', null);

  final stats = <String, FolderStats>{};
  for (final row in (raw as List)) {
    final fid = row['folder_id'] as String?;
    if (fid == null) continue;
    final dt = DateTime.parse(row['created_at'] as String);
    final cur = stats[fid];
    if (cur == null) {
      stats[fid] = FolderStats(fileCount: 1, lastUpdated: dt);
    } else {
      final newest =
          (cur.lastUpdated != null && cur.lastUpdated!.isAfter(dt))
              ? cur.lastUpdated
              : dt;
      stats[fid] = FolderStats(fileCount: cur.fileCount + 1, lastUpdated: newest);
    }
  }
  return stats;
});

final filesProvider =
    FutureProvider.family<List<FileModel>, String?>((ref, folderId) async {
  final client = ref.watch(supabaseClientProvider);
  final user = client.auth.currentUser;
  if (user == null) return [];

  final base = client.from('files').select().eq('user_id', user.id);
  final raw = folderId == null
      ? await base
          .isFilter('folder_id', null)
          .order('created_at', ascending: false)
      : await base
          .eq('folder_id', folderId)
          .order('created_at', ascending: false);

  return (raw as List)
      .map((e) => FileModel.fromJson(e as Map<String, dynamic>))
      .toList();
});

class FolderNotifier extends StateNotifier<AsyncValue<void>> {
  final SupabaseClient _client;
  final Ref _ref;

  FolderNotifier(this._client, this._ref) : super(const AsyncValue.data(null));

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
      _ref.invalidate(foldersProvider);
      _ref.invalidate(folderStatsProvider);
    });
  }
}

final folderNotifierProvider =
    StateNotifierProvider<FolderNotifier, AsyncValue<void>>(
  (ref) => FolderNotifier(ref.watch(supabaseClientProvider), ref),
);
