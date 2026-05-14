import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/auth/providers/auth_provider.dart';
import '../../../shared/models/profile.dart';
import '../../../shared/models/relationship.dart';

final familyProvider = FutureProvider<List<Relationship>>((_) async => []);

final familyMembersForHomeProvider = FutureProvider<List<Profile>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final user = client.auth.currentUser;
  if (user == null) return [];

  final rels = await client
      .from('relationships')
      .select('requester_id, target_id')
      .or('requester_id.eq.${user.id},target_id.eq.${user.id}')
      .eq('status', 'approved');

  final otherIds = (rels as List).map<String>((r) {
    final reqId = r['requester_id'] as String;
    return reqId == user.id ? r['target_id'] as String : reqId;
  }).toList();

  if (otherIds.isEmpty) return [];

  final profiles = await client
      .from('profiles')
      .select()
      .inFilter('id', otherIds);

  return (profiles as List)
      .map((p) => Profile.fromJson(p as Map<String, dynamic>))
      .toList();
});
