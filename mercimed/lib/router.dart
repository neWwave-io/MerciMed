import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'features/auth/screens/login_screen.dart';
import 'features/auth/screens/register_screen.dart';
import 'features/chat/screens/chat_screen.dart';
import 'features/family/screens/family_screen.dart';
import 'features/files/screens/file_detail_screen.dart';
import 'features/files/screens/folder_screen.dart';
import 'features/files/screens/home_screen.dart';
import 'features/profile/screens/profile_screen.dart';
import 'shared/widgets/animated_background.dart';
import 'shared/widgets/app_bottom_nav.dart';

class _AuthChangeNotifier extends ChangeNotifier {
  late final StreamSubscription<AuthState> _sub;
  _AuthChangeNotifier() {
    _sub = Supabase.instance.client.auth.onAuthStateChange
        .listen((_) => notifyListeners());
  }
  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

final _authNotifier = _AuthChangeNotifier();

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/home',
    refreshListenable: _authNotifier,
    redirect: (context, state) {
      final isLoggedIn =
          Supabase.instance.client.auth.currentSession != null;
      final loc = state.matchedLocation;
      final onAuth = loc == '/login' || loc == '/register';
      if (!isLoggedIn && !onAuth) return '/login';
      if (isLoggedIn && onAuth) return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, _) => const RegisterScreen()),
      ShellRoute(
        builder: (context, state, child) =>
            MainShell(location: state.matchedLocation, child: child),
        routes: [
          GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
          GoRoute(
            path: '/folder/:id',
            builder: (_, state) =>
                FolderScreen(folderId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/file/:id',
            builder: (_, state) =>
                FileDetailScreen(fileId: state.pathParameters['id']!),
          ),
          GoRoute(path: '/chat', builder: (_, _) => const ChatScreen()),
          GoRoute(path: '/family', builder: (_, _) => const FamilyScreen()),
          GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
        ],
      ),
    ],
  );
});

class MainShell extends StatelessWidget {
  final String location;
  final Widget child;

  const MainShell({required this.location, required this.child, super.key});

  int get _index {
    if (location.startsWith('/chat')) return 1;
    if (location.startsWith('/profile')) return 2;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBackground(
      child: Scaffold(
        extendBody: true,
        backgroundColor: Colors.transparent,
        body: child,
        bottomNavigationBar: AppBottomNav(
          currentIndex: _index,
          onTap: (i) {
            if (i == 0) context.go('/home');
            if (i == 1) context.go('/chat');
            if (i == 2) context.go('/profile');
          },
        ),
      ),
    );
  }
}
