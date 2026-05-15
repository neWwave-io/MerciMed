// Thin "you're offline" strip rendered above all content.
//
// USED BY: router.dart MainShell — wrap the Scaffold body with this to show
// the banner across all routes. flutter-ui will wire this in. Until then it
// can be dropped into any Scaffold body to verify the behaviour locally.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/connectivity_provider.dart';
import '../theme/app_theme.dart';

class OfflineBanner extends ConsumerWidget {
  final Widget child;
  const OfflineBanner({required this.child, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(isOnlineProvider);
    return Column(
      mainAxisSize: MainAxisSize.max,
      children: [
        // Slides the bar in/out; SafeArea content shifts to make room so the
        // banner doesn't overlap status bar icons.
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          child: online ? const SizedBox.shrink() : const _OfflineStrip(),
        ),
        Expanded(child: child),
      ],
    );
  }
}

class _OfflineStrip extends StatelessWidget {
  const _OfflineStrip();

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    return Material(
      color: const Color(0xFFFFE7A8), // amber-tinted to match AppTheme palette
      elevation: 0,
      child: Padding(
        // Push below the status bar so the bar is always readable.
        padding: EdgeInsets.fromLTRB(12, topInset + 6, 12, 6),
        child: SizedBox(
          height: 24,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(
                Icons.wifi_off_rounded,
                size: 16,
                color: AppTheme.primaryDark,
              ),
              SizedBox(width: 8),
              Flexible(
                child: Text(
                  "You're offline. Some features are limited.",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppTheme.primaryDark,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
