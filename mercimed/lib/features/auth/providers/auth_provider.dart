import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mime/mime.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabaseClientProvider = Provider<SupabaseClient>(
  (_) => Supabase.instance.client,
);

final authStateProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(supabaseClientProvider).auth.onAuthStateChange;
});

final currentUserProvider = Provider<User?>((ref) {
  // Subscribe to auth state so this re-evaluates on login/logout.
  // Without this, the value captured at first build (often null on the
  // login screen) sticks until hot-reload.
  ref.watch(authStateProvider);
  return ref.watch(supabaseClientProvider).auth.currentUser;
});

class AuthNotifier extends StateNotifier<AsyncValue<void>> {
  final SupabaseClient _client;

  AuthNotifier(this._client) : super(const AsyncValue.data(null));

  Future<void> login(String email, String password) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => _client.auth.signInWithPassword(email: email, password: password),
    );
  }

  Future<void> register(
    String email,
    String password,
    String fullName, {
    File? avatar,
  }) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final res = await _client.auth.signUp(email: email, password: password);
      final user = res.user;
      if (user == null) return;

      String? avatarUrl;
      if (avatar != null) {
        avatarUrl = await _uploadAvatar(userId: user.id, file: avatar);
      }

      await _client.from('profiles').upsert({
        'id': user.id,
        'email': email,
        'full_name': fullName,
        'avatar_url': ?avatarUrl,
      });
    });
  }

  Future<String?> _uploadAvatar({
    required String userId,
    required File file,
  }) async {
    final mimeType = lookupMimeType(file.path) ?? 'image/jpeg';
    final ext = mimeType.split('/').last.replaceAll('jpeg', 'jpg');
    final path = '$userId/avatar.$ext';

    await _client.storage.from('avatars').upload(
          path,
          file,
          fileOptions: FileOptions(contentType: mimeType, upsert: true),
        );

    final url = _client.storage.from('avatars').getPublicUrl(path);
    // Cache-bust so CachedNetworkImage refetches after an overwrite.
    final sep = url.contains('?') ? '&' : '?';
    return '$url${sep}v=${DateTime.now().millisecondsSinceEpoch}';
  }

  Future<void> updateProfile({String? fullName, File? avatar}) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw StateError('Not signed in.');
    }
    final updates = <String, dynamic>{};
    final trimmedName = fullName?.trim();
    if (trimmedName != null && trimmedName.isNotEmpty) {
      updates['full_name'] = trimmedName;
    }
    if (avatar != null) {
      final url = await _uploadAvatar(userId: user.id, file: avatar);
      if (url != null) updates['avatar_url'] = url;
    }
    if (updates.isEmpty) return;
    await _client.from('profiles').update(updates).eq('id', user.id);
  }

  Future<void> logout() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _client.auth.signOut());
  }
}

final authNotifierProvider =
    StateNotifierProvider<AuthNotifier, AsyncValue<void>>(
  (ref) => AuthNotifier(ref.watch(supabaseClientProvider)),
);
