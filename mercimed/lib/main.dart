import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'router.dart';
import 'shared/cache/outbox.dart';
import 'shared/theme/app_theme.dart';
import 'supabase_config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  runApp(const ProviderScope(child: MerciMedApp()));
}

class MerciMedApp extends ConsumerWidget {
  const MerciMedApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Boot the outbox worker the moment the root widget builds — it
    // subscribes to `isOnlineProvider` and drains queued offline writes
    // (currently just `update_file_notes`) on every reconnect.
    ref.watch(outboxWorkerProvider);
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'MerciMed',
      theme: AppTheme.lightTheme,
      debugShowCheckedModeBanner: false,
      routerConfig: router,
    );
  }
}
