import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../features/family/providers/family_provider.dart';
import '../../../shared/models/folder.dart';
import '../../../shared/theme/app_theme.dart';
import '../providers/files_provider.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning,';
    if (h < 17) return 'Good afternoon,';
    return 'Good evening,';
  }

  String _initial(String? fullName) {
    if (fullName == null || fullName.trim().isEmpty) return '?';
    return fullName.trim()[0].toUpperCase();
  }

  Future<void> _showNewFolderDialog() async {
    final ctrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('New folder'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'Folder name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (confirmed == true && ctrl.text.trim().isNotEmpty) {
      await ref.read(folderNotifierProvider.notifier).create(ctrl.text.trim());
    }
    ctrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync  = ref.watch(currentUserProfileProvider);
    final foldersAsync  = ref.watch(foldersProvider(null));
    final statsAsync    = ref.watch(folderStatsProvider);
    final familyAsync   = ref.watch(familyMembersForHomeProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // ── Top bar ───────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                child: Row(
                  children: [
                    Text(
                      'MerciMed',
                      style: const TextStyle(
                        color: AppTheme.primaryDark,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                        height: 1.3,
                      ),
                    ),
                    const Spacer(),
                    _GlassMenuButton(
                      onSelected: (v) {
                        if (v == 'new_folder') _showNewFolderDialog();
                      },
                    ),
                  ],
                ),
              ),
            ),

            // ── Family avatars ────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 24),
                child: SizedBox(
                  height: 102,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    children: [
                      profileAsync.when(
                        data: (p) => _AvatarItem(
                          label: 'You',
                          initial: _initial(p?.fullName),
                          isYou: true,
                        ),
                        loading: () => const _AvatarItem(
                          label: 'You',
                          initial: '?',
                          isYou: true,
                        ),
                        error: (_, _) => const SizedBox.shrink(),
                      ),
                      ...familyAsync.when(
                        data: (members) => members.map((p) => Padding(
                              padding: const EdgeInsets.only(left: 16),
                              child: _AvatarItem(
                                label: p.fullName?.split(' ').first ?? '?',
                                initial: _initial(p.fullName),
                                isYou: false,
                              ),
                            )).toList(),
                        loading: () => <Widget>[],
                        error: (_, _) => <Widget>[],
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 16),
                        child: _AddFamilyButton(
                          onTap: () => context.go('/family'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ── Greeting ──────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
                child: profileAsync.when(
                  data: (p) {
                    final first = p?.fullName?.split(' ').first ?? '';
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Good evening,',
                          style: TextStyle(
                            color: AppTheme.primaryDark,
                            fontSize: 32,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.8,
                            height: 1.15,
                          ),
                        ),
                        if (first.isNotEmpty)
                          Text(
                            '$first.',
                            style: const TextStyle(
                              color: AppTheme.primaryDark,
                              fontSize: 32,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.8,
                              height: 1.15,
                            ),
                          ),
                      ],
                    );
                  },
                  loading: () => Text(
                    _greeting,
                    style: const TextStyle(
                      color: AppTheme.primaryDark,
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.8,
                    ),
                  ),
                  error: (_, _) => Text(
                    _greeting,
                    style: const TextStyle(
                      color: AppTheme.primaryDark,
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),

            // ── Search bar ────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.78),
                    borderRadius: BorderRadius.circular(32),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 12,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (v) =>
                        setState(() => _query = v.toLowerCase()),
                    autocorrect: false,
                    style: const TextStyle(
                      color: AppTheme.primaryDark,
                      fontSize: 14,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search your records',
                      hintStyle: TextStyle(
                        color: AppTheme.primaryDark.withValues(alpha: 0.45),
                        fontSize: 14,
                      ),
                      prefixIcon: Padding(
                        padding: const EdgeInsets.only(left: 18, right: 12),
                        child: Icon(
                          Icons.search_rounded,
                          color: AppTheme.primaryDark.withValues(alpha: 0.55),
                          size: 22,
                        ),
                      ),
                      prefixIconConstraints: const BoxConstraints(
                        minWidth: 0,
                        minHeight: 0,
                      ),
                      suffixIcon: Padding(
                        padding: const EdgeInsets.only(right: 18),
                        child: Align(
                          widthFactor: 1.0,
                          alignment: Alignment.centerRight,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '⌘K',
                              style: TextStyle(
                                fontSize: 10,
                                color: AppTheme.primaryDark
                                    .withValues(alpha: 0.6),
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                        ),
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 0,
                        vertical: 18,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // ── Folders header ────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
                child: foldersAsync.when(
                  data: (folders) {
                    final totalFiles = statsAsync.value?.values
                            .fold(0, (a, b) => a + b.fileCount) ??
                        0;
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text(
                          'FOLDERS',
                          style: TextStyle(
                            color: Color(0xFF4A5568),
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.6,
                          ),
                        ),
                        if (folders.isNotEmpty)
                          Text(
                            '${folders.length} · $totalFiles file${totalFiles == 1 ? '' : 's'}',
                            style: const TextStyle(
                              color: Color(0xFF4A5568),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.4,
                            ),
                          ),
                      ],
                    );
                  },
                  loading: () => const Text(
                    'FOLDERS',
                    style: TextStyle(
                      color: Color(0xFF4A5568),
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.6,
                    ),
                  ),
                  error: (_, _) => const Text(
                    'FOLDERS',
                    style: TextStyle(
                      color: Color(0xFF4A5568),
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.6,
                    ),
                  ),
                ),
              ),
            ),

            // ── Folder grid ───────────────────────────────────────────
            foldersAsync.when(
              data: (folders) {
                final filtered = _query.isEmpty
                    ? folders
                    : folders
                        .where((f) =>
                            f.name.toLowerCase().contains(_query))
                        .toList();

                if (filtered.isEmpty) {
                  return SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 40),
                      child: Center(
                        child: Text(
                          _query.isEmpty
                              ? 'No folders yet.\nTap ··· to create one.'
                              : 'No results for "$_query".',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppTheme.muted,
                            fontSize: 14,
                            height: 1.6,
                          ),
                        ),
                      ),
                    ),
                  );
                }

                return SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  sliver: SliverGrid.builder(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      childAspectRatio: 1.0,
                    ),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final folder = filtered[i];
                      final idx = folders.indexOf(folder);
                      return _FolderCard(
                        folder: folder,
                        colorIndex: idx,
                        stats: statsAsync.value?[folder.id],
                        onTap: () =>
                            context.push('/folder/${folder.id}'),
                      );
                    },
                  ),
                );
              },
              loading: () => const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(top: 60),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
              error: (_, _) => const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(top: 40),
                  child: Center(
                    child: Text(
                      'Could not load folders.',
                      style: TextStyle(color: AppTheme.muted),
                    ),
                  ),
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 120)),
          ],
        ),
      ),
    );
  }
}

// ── Folder color palette ───────────────────────────────────────────────────────

const _kFolderColors = [
  Color(0xFFD64B4B),
  Color(0xFF2D6B6B),
  Color(0xFFD4943A),
  Color(0xFF4A7B8B),
  Color(0xFF7B6B8A),
  Color(0xFF5A8A6B),
];

// ── Folder card ────────────────────────────────────────────────────────────────

class _FolderCard extends StatelessWidget {
  final Folder folder;
  final int colorIndex;
  final FolderStats? stats;
  final VoidCallback onTap;

  const _FolderCard({
    required this.folder,
    required this.colorIndex,
    this.stats,
    required this.onTap,
  });

  String _timeAgo(DateTime? dt) {
    if (dt == null) return '';
    final d = DateTime.now().difference(dt);
    if (d.inDays > 60) return 'Updated ${d.inDays ~/ 30}mo ago';
    if (d.inDays > 6)  return 'Updated ${d.inDays ~/ 7}w ago';
    if (d.inDays > 0)  return 'Updated ${d.inDays}d ago';
    if (d.inHours > 0) return 'Updated ${d.inHours}h ago';
    if (d.inMinutes > 0) return 'Updated ${d.inMinutes}m ago';
    return 'Updated just now';
  }

  @override
  Widget build(BuildContext context) {
    final color = _kFolderColors[colorIndex % _kFolderColors.length];
    final count = stats?.fileCount ?? 0;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 18,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(top: 6),
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const Spacer(),
                if (count > 0)
                  Text(
                    '$count',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF4A5568),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
            const Spacer(),
            Text(
              folder.name,
              style: const TextStyle(
                color: AppTheme.primaryDark,
                fontSize: 17,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
                height: 1.2,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Text(
              _timeAgo(stats?.lastUpdated),
              style: const TextStyle(
                color: Color(0xFF6B7C8C),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Avatar item ────────────────────────────────────────────────────────────────

class _AvatarItem extends StatelessWidget {
  final String label;
  final String initial;
  final bool isYou;

  const _AvatarItem({
    required this.label,
    required this.initial,
    required this.isYou,
  });

  @override
  Widget build(BuildContext context) {
    const tile = Color(0xFFE3EFE9); // soft mint surface
    const accentRing = Color(0xFF1E293B);

    final circle = Container(
      width: 60,
      height: 60,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: tile,
      ),
      child: Center(
        child: Text(
          initial,
          style: const TextStyle(
            color: AppTheme.primaryDark,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 68,
          height: 68,
          child: isYou
              ? Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: accentRing, width: 1.6),
                  ),
                  padding: const EdgeInsets.all(3),
                  child: circle,
                )
              : Center(child: circle),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF4A5568),
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }
}

// ── Add family button ──────────────────────────────────────────────────────────

class _AddFamilyButton extends StatelessWidget {
  final VoidCallback onTap;
  const _AddFamilyButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CustomPaint(
            painter: _DashedCirclePainter(
              color: const Color(0xFF4A5568).withValues(alpha: 0.55),
            ),
            child: const SizedBox(
              width: 68,
              height: 68,
              child: Center(
                child: Icon(
                  Icons.add_rounded,
                  size: 22,
                  color: Color(0xFF4A5568),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Add',
            style: TextStyle(
              color: Color(0xFF4A5568),
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _DashedCirclePainter extends CustomPainter {
  final Color color;
  _DashedCirclePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    final radius = size.width / 2;
    final center = Offset(radius, radius);
    const dashCount = 28;
    const gapFraction = 0.45;
    final sweepPerSegment = (2 * 3.141592653589793) / dashCount;
    final dashSweep = sweepPerSegment * (1 - gapFraction);

    for (var i = 0; i < dashCount; i++) {
      final start = i * sweepPerSegment;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - 0.7),
        start,
        dashSweep,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DashedCirclePainter old) => old.color != color;
}

// ── Glass menu button (top bar) ────────────────────────────────────────────────

class _GlassMenuButton extends StatelessWidget {
  final ValueChanged<String> onSelected;
  const _GlassMenuButton({required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.55),
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.9),
          width: 1,
        ),
      ),
      child: PopupMenuButton<String>(
        icon: const Icon(
          Icons.more_vert_rounded,
          size: 20,
          color: AppTheme.primaryDark,
        ),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 38, height: 38),
        color: Colors.white,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        onSelected: onSelected,
        itemBuilder: (_) => const [
          PopupMenuItem(
            value: 'new_folder',
            child: Text('New folder'),
          ),
        ],
      ),
    );
  }
}
