import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../features/family/providers/family_provider.dart';
import '../../../features/family/widgets/invite_family_sheet.dart';
import '../../../features/files/providers/files_provider.dart';
import '../../../shared/models/profile.dart';
import '../../../shared/theme/app_theme.dart';
import '../../auth/providers/auth_provider.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  String _initial(String? name, String fallback) {
    if (name == null || name.trim().isEmpty) return fallback;
    return name.trim()[0].toUpperCase();
  }

  String _firstName(String? full) {
    if (full == null || full.trim().isEmpty) return '';
    return full.trim().split(' ').first;
  }

  String _memberNumber(String id) {
    final hash = id.hashCode.abs() % 999;
    return 'No. ${hash.toString().padLeft(3, '0')}';
  }

  String _shortMonthYear(DateTime? dt) {
    if (dt == null) return '—';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.year}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final profileAsync = ref.watch(currentUserProfileProvider);
    final familyAsync = ref.watch(familyMembersForHomeProvider);
    final pendingAsync = ref.watch(pendingRequestsProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: profileAsync.when(
          data: (profile) => _buildBody(
            context,
            ref,
            user?.email ?? profile?.email ?? '',
            profile,
            familyAsync.value ?? const <Profile>[],
            pendingAsync.value ?? const <PendingRequest>[],
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => _buildBody(
            context,
            ref,
            user?.email ?? '',
            null,
            familyAsync.value ?? const <Profile>[],
            pendingAsync.value ?? const <PendingRequest>[],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    String email,
    Profile? profile,
    List<Profile> family,
    List<PendingRequest> pending,
  ) {
    final fullName = profile?.fullName ?? email.split('@').first;
    final initial = _initial(profile?.fullName, 'S');
    final memberId = _memberNumber(profile?.id ?? email);
    final since = _shortMonthYear(profile?.createdAt);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 140),
      children: [
        // ── Top bar ───────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 0, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text(
                'Profile',
                style: TextStyle(
                  color: AppTheme.primaryDark,
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                  height: 1.15,
                ),
              ),
              const Spacer(),
              _GlassCircleButton(
                icon: Icons.light_mode_rounded,
                onTap: () {},
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // ── Profile card ──────────────────────────────────────────
        _GlassCard(
          radius: 32,
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: const BoxDecoration(
                      color: Color(0xFFE1EFEC),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      initial,
                      style: const TextStyle(
                        color: AppTheme.primaryDark,
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fullName.isEmpty ? 'Member' : fullName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppTheme.primaryDark,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF4A5568),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _MembershipStat(label: 'MEMBER', value: memberId),
                  _MembershipStat(label: 'SINCE', value: since),
                  const _MembershipStat(label: 'PLAN', value: 'Founders'),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // ── Pending requests ─────────────────────────────────────
        if (pending.isNotEmpty) ...[
          const _SectionHeader(
            label: 'INCOMING',
            subtitle: 'requests',
          ),
          const SizedBox(height: 12),
          _GlassCard(
            radius: 24,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Column(
              children: [
                for (var i = 0; i < pending.length; i++) ...[
                  if (i > 0)
                    const Divider(height: 1, color: Color(0x14000000)),
                  _PendingRequestRow(
                    request: pending[i],
                    onApprove: () => ref
                        .read(familyNotifierProvider.notifier)
                        .approve(pending[i].id),
                    onDecline: () => ref
                        .read(familyNotifierProvider.notifier)
                        .decline(pending[i].id),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],

        // ── Family ────────────────────────────────────────────────
        _SectionHeader(
          label: 'FAMILY',
          subtitle: '${family.length} member${family.length == 1 ? '' : 's'}',
          trailing: 'Invite +',
          onTrailing: () => showInviteFamilySheet(context),
        ),
        const SizedBox(height: 12),
        _GlassCard(
          radius: 28,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: family.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: Text(
                      'No family members yet.',
                      style: TextStyle(
                        color: Color(0xFF6B7C8C),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    for (final p in family.take(4))
                      _FamilyMember(
                        initial: _initial(p.fullName, '?'),
                        name: _firstName(p.fullName),
                        permission: 'VIEW',
                      ),
                  ],
                ),
        ),

        const SizedBox(height: 24),

        // ── Care team ─────────────────────────────────────────────
        const _SectionHeader(
          label: 'CARE TEAM',
          subtitle: '0 doctors',
        ),
        const SizedBox(height: 12),
        _GlassCard(
          radius: 28,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Center(
              child: Text(
                'Your saved doctors will appear here.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppTheme.primaryDark.withValues(alpha: 0.55),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),

        const SizedBox(height: 32),

        // ── Sign out ──────────────────────────────────────────────
        Center(
          child: TextButton.icon(
            onPressed: () async {
              await ref.read(authNotifierProvider.notifier).logout();
              if (context.mounted) context.go('/login');
            },
            icon: const Icon(
              Icons.logout_rounded,
              size: 18,
              color: Color(0xFFD64B4B),
            ),
            label: const Text(
              'Sign out',
              style: TextStyle(
                color: Color(0xFFD64B4B),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Glass card ─────────────────────────────────────────────────────────────────

class _GlassCard extends StatelessWidget {
  final double radius;
  final EdgeInsetsGeometry padding;
  final Widget child;

  const _GlassCard({
    required this.radius,
    required this.padding,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.78),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.85),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 14,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}

// ── Glass circle button ────────────────────────────────────────────────────────

class _GlassCircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _GlassCircleButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Material(
          color: Colors.white.withValues(alpha: 0.7),
          shape: const CircleBorder(
            side: BorderSide(color: Colors.white, width: 1),
          ),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Icon(
                icon,
                size: 22,
                color: AppTheme.primaryDark,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Membership stat ────────────────────────────────────────────────────────────

class _MembershipStat extends StatelessWidget {
  final String label;
  final String value;
  const _MembershipStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF4A5568),
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            color: AppTheme.primaryDark,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

// ── Section header ─────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  final String subtitle;
  final String? trailing;
  final VoidCallback? onTrailing;

  const _SectionHeader({
    required this.label,
    required this.subtitle,
    this.trailing,
    this.onTrailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF4A5568),
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.6,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            subtitle,
            style: const TextStyle(
              color: AppTheme.primaryDark,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          if (trailing != null)
            GestureDetector(
              onTap: onTrailing,
              behavior: HitTestBehavior.opaque,
              child: Text(
                trailing!,
                style: const TextStyle(
                  color: Color(0xFF4A5568),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Pending request row ───────────────────────────────────────────────────────

class _PendingRequestRow extends StatelessWidget {
  final PendingRequest request;
  final VoidCallback onApprove;
  final VoidCallback onDecline;

  const _PendingRequestRow({
    required this.request,
    required this.onApprove,
    required this.onDecline,
  });

  String get _initial {
    final n = request.fromProfile.fullName?.trim();
    if (n != null && n.isNotEmpty) return n[0].toUpperCase();
    final e = request.fromProfile.email;
    if (e != null && e.isNotEmpty) return e[0].toUpperCase();
    return '?';
  }

  String get _displayName {
    final n = request.fromProfile.fullName?.trim();
    if (n != null && n.isNotEmpty) return n;
    return request.fromProfile.email ?? 'Someone';
  }

  @override
  Widget build(BuildContext context) {
    final rel = request.relationshipType;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: Color(0xFFE3EFE9),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              _initial,
              style: const TextStyle(
                color: AppTheme.primaryDark,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.primaryDark,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  rel == null
                      ? 'wants to view your records'
                      : 'as $rel — wants to view your records',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF6B7C8C),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onDecline,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: const Size(0, 32),
              foregroundColor: const Color(0xFFD64B4B),
            ),
            child: const Text(
              'Decline',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
          ElevatedButton(
            onPressed: onApprove,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1A212B),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              minimumSize: const Size(0, 34),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              textStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
              elevation: 0,
            ),
            child: const Text('Approve'),
          ),
        ],
      ),
    );
  }
}

// ── Family member tile ────────────────────────────────────────────────────────

class _FamilyMember extends StatelessWidget {
  final String initial;
  final String name;
  final String permission;

  const _FamilyMember({
    required this.initial,
    required this.name,
    required this.permission,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: const BoxDecoration(
            color: Color(0xFFE3EFE9),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            initial,
            style: const TextStyle(
              color: AppTheme.primaryDark,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          name.isEmpty ? '—' : name,
          style: const TextStyle(
            color: AppTheme.primaryDark,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          permission,
          style: const TextStyle(
            color: Color(0xFF6B7C8C),
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }
}
