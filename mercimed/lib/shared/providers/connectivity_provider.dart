// Network connectivity providers.
//
// Surfaces a coarse online/offline signal that the offline banner + the cache
// layer key off. We deliberately treat ANY non-`none` interface as "online"
// — captive-portal / metered-connection nuances aren't worth handling at this
// layer (HTTP errors from the cache layer will catch those cases).

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Live stream of connectivity changes. `connectivity_plus` 6+ emits a list
/// because a device can be connected to wifi + cellular simultaneously.
final connectivityStreamProvider =
    StreamProvider<List<ConnectivityResult>>((ref) {
  return Connectivity().onConnectivityChanged;
});

/// True when at least one interface is connected. Optimistic-default `true`
/// until the first stream emission so the UI doesn't flash an "offline"
/// banner during cold start.
final isOnlineProvider = Provider<bool>((ref) {
  final async = ref.watch(connectivityStreamProvider);
  return async.maybeWhen(
    data: (results) => results.any((r) => r != ConnectivityResult.none),
    orElse: () => true,
  );
});
