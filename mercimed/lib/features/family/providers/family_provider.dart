import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../features/auth/providers/auth_provider.dart';
import '../../../shared/models/profile.dart';
import '../../../shared/models/relationship.dart';

/// Holds the user id whose records the home screen is currently viewing.
/// null means "me". Set via [setActiveOwner].
final activeOwnerProvider = StateProvider<String?>((_) => null);

/// Resolves [activeOwnerProvider] against the auth user — always returns a
/// concrete id (or null only if not signed in).
final effectiveOwnerIdProvider = Provider<String?>((ref) {
  final override = ref.watch(activeOwnerProvider);
  if (override != null) return override;
  // Watch the auth-aware user so this re-resolves on login/logout.
  final user = ref.watch(currentUserProvider);
  return user?.id;
});

/// True when the user is viewing someone else's records.
final isViewingFamilyProvider = Provider<bool>((ref) {
  final override = ref.watch(activeOwnerProvider);
  return override != null;
});

final familyProvider = FutureProvider<List<Relationship>>((_) async => []);

/// Live stream of relationships where I am the requester.
final _outgoingRelationshipsStreamProvider =
    StreamProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
  final client = ref.watch(supabaseClientProvider);
  final user = client.auth.currentUser;
  if (user == null) return Stream.value(const []);
  return client
      .from('relationships')
      .stream(primaryKey: ['id'])
      .eq('requester_id', user.id);
});

/// Live stream of relationships where I am the target.
final _incomingRelationshipsStreamProvider =
    StreamProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
  final client = ref.watch(supabaseClientProvider);
  final user = client.auth.currentUser;
  if (user == null) return Stream.value(const []);
  return client
      .from('relationships')
      .stream(primaryKey: ['id'])
      .eq('target_id', user.id);
});

/// Approved family members — used in the home avatar row. Implemented as a
/// StreamProvider so every realtime UPDATE on `relationships` (e.g. someone
/// approving your pending invite) emits a fresh family list without the
/// FutureProvider's rebuild delay.
final familyMembersForHomeProvider =
    StreamProvider.autoDispose<List<Profile>>((ref) {
  final client = ref.watch(supabaseClientProvider);
  final user = client.auth.currentUser;
  if (user == null) return Stream.value(const []);

  final controller = StreamController<List<Profile>>();
  Set<String> lastIds = {};
  List<Profile> lastProfiles = const [];
  bool initialized = false;

  Future<void> publish() async {
    final outgoing =
        ref.read(_outgoingRelationshipsStreamProvider).value ?? const [];
    final incoming =
        ref.read(_incomingRelationshipsStreamProvider).value ?? const [];
    final ids = <String>{
      for (final r in outgoing)
        if (r['status'] == 'approved') r['target_id'] as String,
      for (final r in incoming)
        if (r['status'] == 'approved') r['requester_id'] as String,
    };
    final sameSet =
        ids.length == lastIds.length && ids.every(lastIds.contains);
    if (sameSet && initialized) {
      // No relationship change — re-emit cached so subscribers don't get
      // stuck on the initial empty state.
      if (!controller.isClosed) controller.add(lastProfiles);
      return;
    }
    lastIds = ids;
    initialized = true;
    if (ids.isEmpty) {
      lastProfiles = const [];
      if (!controller.isClosed) controller.add(lastProfiles);
      return;
    }
    try {
      final rows = await client
          .from('profiles')
          .select()
          .inFilter('id', ids.toList());
      lastProfiles = (rows as List)
          .map((p) => Profile.fromJson(p as Map<String, dynamic>))
          .toList();
      if (!controller.isClosed) controller.add(lastProfiles);
    } catch (_) {
      if (!controller.isClosed) controller.add(lastProfiles);
    }
  }

  // Listen reactively to both relationship streams. Any INSERT / UPDATE /
  // DELETE on relationships flips one of these, which calls publish().
  ref.listen(
    _outgoingRelationshipsStreamProvider,
    (_, _) => publish(),
    fireImmediately: true,
  );
  ref.listen(
    _incomingRelationshipsStreamProvider,
    (_, _) => publish(),
    fireImmediately: true,
  );

  ref.onDispose(controller.close);
  return controller.stream;
});

class PendingRequest {
  final String id;
  final Profile fromProfile;
  final String? relationshipType;
  final DateTime createdAt;

  const PendingRequest({
    required this.id,
    required this.fromProfile,
    this.relationshipType,
    required this.createdAt,
  });
}

/// Incoming pending requests — derived live from the incoming stream.
/// Profiles for the requesters are fetched on demand.
final pendingRequestsProvider =
    FutureProvider.autoDispose<List<PendingRequest>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final user = client.auth.currentUser;
  if (user == null) return const [];

  final incoming = ref.watch(_incomingRelationshipsStreamProvider).value ?? [];
  final pending = incoming.where((r) => r['status'] == 'pending').toList()
    ..sort((a, b) => (b['created_at'] as String)
        .compareTo(a['created_at'] as String));
  if (pending.isEmpty) return const [];

  final reqIds =
      pending.map((r) => r['requester_id'] as String).toSet().toList();
  final profiles = await client
      .from('profiles')
      .select()
      .inFilter('id', reqIds);

  final byId = {
    for (final p in (profiles as List).cast<Map<String, dynamic>>())
      p['id'] as String: Profile.fromJson(p),
  };

  return pending.map((r) {
    return PendingRequest(
      id: r['id'] as String,
      fromProfile: byId[r['requester_id']] ??
          Profile(id: r['requester_id'] as String, createdAt: DateTime.now()),
      relationshipType: r['relationship_type'] as String?,
      createdAt: DateTime.parse(r['created_at'] as String),
    );
  }).toList();
});

/// Suggested users to invite — the most recently joined members, excluding
/// the signed-in user and anyone the user is already related to. Powers the
/// initial grid in the invite sheet before the user types a query.
final suggestedUsersProvider =
    FutureProvider.autoDispose<List<Profile>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final user = ref.watch(currentUserProvider);
  if (user == null) return const [];

  final rows = await client
      .from('profiles')
      .select()
      .neq('id', user.id)
      .order('created_at', ascending: false)
      .limit(24);

  final outgoing = ref.watch(_outgoingRelationshipsStreamProvider).value ?? [];
  final incoming = ref.watch(_incomingRelationshipsStreamProvider).value ?? [];
  final relatedIds = <String>{
    for (final r in outgoing) r['target_id'] as String,
    for (final r in incoming) r['requester_id'] as String,
  };

  return (rows as List)
      .map((p) => Profile.fromJson(p as Map<String, dynamic>))
      .where((p) => !relatedIds.contains(p.id))
      .toList();
});

/// Live search over public.profiles by name or email. Excludes the signed-in
/// user and anyone the user is already related to (pending or approved).
final userSearchProvider = FutureProvider.autoDispose
    .family<List<Profile>, String>((ref, query) async {
  final client = ref.watch(supabaseClientProvider);
  final user = client.auth.currentUser;
  if (user == null) return const [];
  final q = query.trim();
  if (q.isEmpty) return const [];

  final escaped = q.replaceAll(',', '\\,').replaceAll(')', '\\)');
  final rows = await client
      .from('profiles')
      .select()
      .or('full_name.ilike.%$escaped%,email.ilike.%$escaped%')
      .neq('id', user.id)
      .limit(20);

  final outgoing = ref.watch(_outgoingRelationshipsStreamProvider).value ?? [];
  final incoming = ref.watch(_incomingRelationshipsStreamProvider).value ?? [];
  final relatedIds = <String>{
    for (final r in outgoing) r['target_id'] as String,
    for (final r in incoming) r['requester_id'] as String,
  };

  return (rows as List)
      .map((p) => Profile.fromJson(p as Map<String, dynamic>))
      .where((p) => !relatedIds.contains(p.id))
      .toList();
});

class FamilyInviteResult {
  final bool success;
  final String? errorMessage;
  const FamilyInviteResult.ok()
      : success = true,
        errorMessage = null;
  const FamilyInviteResult.fail(this.errorMessage) : success = false;
}

class FamilyNotifier extends StateNotifier<AsyncValue<void>> {
  final SupabaseClient _client;
  FamilyNotifier(this._client) : super(const AsyncValue.data(null));

  Future<FamilyInviteResult> sendInvite({
    required String email,
    required String relationshipType,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      return const FamilyInviteResult.fail('Please sign in again.');
    }
    final normalized = email.trim().toLowerCase();
    if (normalized.isEmpty) {
      return const FamilyInviteResult.fail('Enter an email address.');
    }

    try {
      final target = await _client
          .from('profiles')
          .select('id')
          .ilike('email', normalized)
          .maybeSingle();

      if (target == null) {
        return const FamilyInviteResult.fail(
          'No member with that email. They need to sign up first.',
        );
      }
      final targetId = target['id'] as String;
      if (targetId == user.id) {
        return const FamilyInviteResult.fail(
          "You can't add yourself.",
        );
      }

      // Check existing relationship in either direction
      final existing = await _client
          .from('relationships')
          .select('id, status')
          .or('and(requester_id.eq.${user.id},target_id.eq.$targetId),'
              'and(requester_id.eq.$targetId,target_id.eq.${user.id})')
          .maybeSingle();

      if (existing != null) {
        final status = existing['status'] as String?;
        if (status == 'approved') {
          return const FamilyInviteResult.fail('Already connected.');
        }
        return const FamilyInviteResult.fail('Request already sent.');
      }

      await _client.from('relationships').insert({
        'requester_id': user.id,
        'target_id': targetId,
        'relationship_type': relationshipType,
        'status': 'pending',
      });

      return const FamilyInviteResult.ok();
    } catch (e) {
      return FamilyInviteResult.fail('Could not send request: $e');
    }
  }

  /// Sends an invite to a user directly by their id (used by the new
  /// search-based picker). Returns a result so the UI can show errors.
  Future<FamilyInviteResult> sendInviteByUserId({
    required String targetUserId,
    required String relationshipType,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      return const FamilyInviteResult.fail('Please sign in again.');
    }
    if (targetUserId == user.id) {
      return const FamilyInviteResult.fail("You can't add yourself.");
    }
    try {
      final existing = await _client
          .from('relationships')
          .select('id, status')
          .or('and(requester_id.eq.${user.id},target_id.eq.$targetUserId),'
              'and(requester_id.eq.$targetUserId,target_id.eq.${user.id})')
          .maybeSingle();
      if (existing != null) {
        final status = existing['status'] as String?;
        return FamilyInviteResult.fail(
          status == 'approved' ? 'Already connected.' : 'Request already sent.',
        );
      }
      await _client.from('relationships').insert({
        'requester_id': user.id,
        'target_id': targetUserId,
        'relationship_type': relationshipType,
        'status': 'pending',
      });
      return const FamilyInviteResult.ok();
    } catch (e) {
      return FamilyInviteResult.fail('Could not send request: $e');
    }
  }

  Future<void> approve(String relationshipId) async {
    await _client
        .from('relationships')
        .update({'status': 'approved'}).eq('id', relationshipId);
    // No invalidation needed — pendingRequestsProvider and
    // familyMembersForHomeProvider are derived from live Supabase streams.
  }

  Future<void> decline(String relationshipId) async {
    await _client.from('relationships').delete().eq('id', relationshipId);
  }
}

final familyNotifierProvider =
    StateNotifierProvider<FamilyNotifier, AsyncValue<void>>(
  (ref) => FamilyNotifier(ref.watch(supabaseClientProvider)),
);
