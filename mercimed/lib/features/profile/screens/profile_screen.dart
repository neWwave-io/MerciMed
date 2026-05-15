import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../features/family/providers/family_provider.dart';
import '../../../features/family/widgets/invite_family_sheet.dart';
import '../../../features/files/providers/files_provider.dart';
import '../../../shared/models/profile.dart';
import '../../../shared/theme/app_theme.dart';
import '../../auth/providers/auth_provider.dart';
import '../widgets/edit_profile_sheet.dart';

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
    final filesAsync = ref.watch(ownerFilesStreamProvider);
    final foldersAsync = ref.watch(foldersProvider(null));

    final fileCount = filesAsync.value?.length ?? 0;
    final folderCount = foldersAsync.value?.length ?? 0;

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
            fileCount: fileCount,
            folderCount: folderCount,
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => _buildBody(
            context,
            ref,
            user?.email ?? '',
            null,
            familyAsync.value ?? const <Profile>[],
            pendingAsync.value ?? const <PendingRequest>[],
            fileCount: fileCount,
            folderCount: folderCount,
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
    List<PendingRequest> pending, {
    required int fileCount,
    required int folderCount,
  }) {
    final fullName = profile?.fullName ?? email.split('@').first;
    final initial = _initial(profile?.fullName, 'S');
    final since = _shortMonthYear(profile?.createdAt);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 140),
      children: [
        // ── Top bar ───────────────────────────────────────────────
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 12, 0, 12),
          child: Text(
            'Profile',
            style: TextStyle(
              color: AppTheme.primaryDark,
              fontSize: 32,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
              height: 1.15,
            ),
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
                  GestureDetector(
                    onTap: () => showEditProfileSheet(context, profile),
                    child: _ProfileAvatar(
                      initial: initial,
                      url: profile?.avatarUrl,
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
                  _EditProfileButton(
                    onTap: () => showEditProfileSheet(context, profile),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _MembershipStat(label: 'FILES', value: '$fileCount'),
                  _MembershipStat(label: 'FOLDERS', value: '$folderCount'),
                  _MembershipStat(label: 'SINCE', value: since),
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
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          // Soft drop — grounds the card on the gradient.
          BoxShadow(
            color: AppTheme.primaryDark.withValues(alpha: 0.08),
            blurRadius: 24,
            spreadRadius: -2,
            offset: const Offset(0, 10),
          ),
          // Subtle top lift — sells the floating glass.
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.5),
            blurRadius: 14,
            spreadRadius: -6,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withValues(alpha: 0.62),
                  Colors.white.withValues(alpha: 0.38),
                ],
              ),
            ),
            padding: padding,
            child: child,
          ),
        ),
      ),
    );
  }
}

// ── Edit profile pill ─────────────────────────────────────────────────────────

class _EditProfileButton extends StatelessWidget {
  final VoidCallback onTap;
  const _EditProfileButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(100),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(100),
            border: Border.all(
              color: AppTheme.primaryDark.withValues(alpha: 0.12),
            ),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.edit_rounded,
                size: 13,
                color: AppTheme.primaryDark,
              ),
              SizedBox(width: 6),
              Text(
                'Edit',
                style: TextStyle(
                  color: AppTheme.primaryDark,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Profile avatar (glass circle, shows photo if uploaded) ─────────────────────

class _ProfileAvatar extends StatelessWidget {
  final String initial;
  final String? url;

  const _ProfileAvatar({required this.initial, this.url});

  @override
  Widget build(BuildContext context) {
    const size = 72.0;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primaryDark.withValues(alpha: 0.10),
                  blurRadius: 18,
                  spreadRadius: -2,
                  offset: const Offset(0, 6),
                ),
                BoxShadow(
                  color: Colors.white.withValues(alpha: 0.45),
                  blurRadius: 12,
                  spreadRadius: -4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
          ),
          ClipOval(
            child: (url != null && url!.isNotEmpty)
                ? CachedNetworkImage(
                    imageUrl: url!,
                    width: size,
                    height: size,
                    fit: BoxFit.cover,
                    placeholder: (_, _) => _glassFallback(initial),
                    errorWidget: (_, _, _) => _glassFallback(initial),
                  )
                : _glassFallback(initial),
          ),
        ],
      ),
    );
  }

  Widget _glassFallback(String initial) {
    const size = 72.0;
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white.withValues(alpha: 0.55),
              Colors.white.withValues(alpha: 0.28),
            ],
          ),
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
