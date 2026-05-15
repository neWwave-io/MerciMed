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
import 'features/profile/screens/edit_profile_screen.dart';
import 'features/profile/screens/profile_screen.dart';
import 'shared/widgets/animated_background.dart';
import 'shared/widgets/app_bottom_nav.dart';
import 'shared/widgets/offline_banner.dart';

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

/// Default page transition for the whole app: a sequenced fade-through.
///
/// The outgoing screen fades out in the first half, the incoming screen
/// fades in in the second half — so the two never overlap visually. The
/// shared animated background remains visible through the brief gap, which
/// reads as a clean cross-dissolve instead of two transparent screens
/// stacked on top of each other.
CustomTransitionPage<void> _fadePage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 260),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    transitionsBuilder: (_, animation, secondaryAnimation, child) {
      // Incoming: invisible until halfway, then fades in.
      final fadeIn = CurvedAnimation(
        parent: animation,
        curve: const Interval(0.5, 1.0, curve: Curves.easeOut),
      );
      // Outgoing: fully visible until halfway, then fades out.
      final fadeOut = CurvedAnimation(
        parent: secondaryAnimation,
        curve: const Interval(0.0, 0.5, curve: Curves.easeIn),
      );
      return AnimatedBuilder(
        animation: Listenable.merge([animation, secondaryAnimation]),
        builder: (_, _) {
          final opacity = fadeIn.value * (1.0 - fadeOut.value);
          return Opacity(opacity: opacity, child: child);
        },
        child: child,
      );
    },
  );
}

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
      GoRoute(
        path: '/login',
        pageBuilder: (_, state) => _fadePage(state, const LoginScreen()),
      ),
      GoRoute(
        path: '/register',
        pageBuilder: (_, state) => _fadePage(state, const RegisterScreen()),
      ),
      ShellRoute(
        builder: (context, state, child) =>
            MainShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(
            path: '/home',
            pageBuilder: (_, state) => _fadePage(state, const HomeScreen()),
          ),
          GoRoute(
            path: '/folder/:id',
            pageBuilder: (_, state) => _fadePage(
              state,
              FolderScreen(folderId: state.pathParameters['id']!),
            ),
          ),
          GoRoute(
            path: '/file/:id',
            pageBuilder: (_, state) => _fadePage(
              state,
              FileDetailScreen(fileId: state.pathParameters['id']!),
            ),
          ),
          GoRoute(
            path: '/chat',
            pageBuilder: (_, state) => _fadePage(state, const ChatScreen()),
          ),
          GoRoute(
            path: '/family',
            pageBuilder: (_, state) => _fadePage(state, const FamilyScreen()),
          ),
          GoRoute(
            path: '/profile',
            pageBuilder: (_, state) => _fadePage(state, const ProfileScreen()),
          ),
          GoRoute(
            path: '/profile/edit',
            pageBuilder: (_, state) =>
                _fadePage(state, const EditProfileScreen()),
          ),
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

  bool get _hideNav =>
      location.startsWith('/chat') ||
      location.startsWith('/folder') ||
      location.startsWith('/file') ||
      location.startsWith('/profile/edit');

  @override
  Widget build(BuildContext context) {
    return AnimatedBackground(
      child: Scaffold(
        extendBody: true,
        backgroundColor: Colors.transparent,
        body: OfflineBanner(child: child),
        bottomNavigationBar: _hideNav
            ? null
            : AppBottomNav(
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
