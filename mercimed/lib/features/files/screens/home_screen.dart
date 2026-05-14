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
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
                child: Row(
                  children: [
                    Text(
                      'MerciMed',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                          ),
                    ),
                    const Spacer(),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_horiz_rounded, size: 22),
                      color: AppTheme.surface,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      onSelected: (v) {
                        if (v == 'new_folder') _showNewFolderDialog();
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'new_folder',
                          child: Text('New folder'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // ── Family avatars ────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 16),
                child: SizedBox(
                  height: 72,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
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
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                child: profileAsync.when(
                  data: (p) {
                    final first = p?.fullName?.split(' ').first ?? '';
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _greeting,
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(fontWeight: FontWeight.w400),
                        ),
                        if (first.isNotEmpty)
                          Text(
                            first,
                            style: Theme.of(context)
                                .textTheme
                                .headlineMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                      ],
                    );
                  },
                  loading: () => const SizedBox(height: 58),
                  error: (_, _) => Text(
                    _greeting,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ),
              ),
            ),

            // ── Search bar ────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppTheme.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 16,
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
                      hintStyle: const TextStyle(
                        color: AppTheme.muted,
                        fontSize: 14,
                      ),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: AppTheme.muted,
                        size: 18,
                      ),
                      suffixIcon: Padding(
                        padding: const EdgeInsets.only(right: 14),
                        child: Align(
                          widthFactor: 1.0,
                          alignment: Alignment.centerRight,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppTheme.surface,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              '⌘K',
                              style: TextStyle(
                                fontSize: 10,
                                color: AppTheme.muted,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 16,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // ── Folders header ────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                child: foldersAsync.when(
                  data: (folders) {
                    final totalFiles = statsAsync.value?.values
                            .fold(0, (a, b) => a + b.fileCount) ??
                        0;
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('FOLDERS',
                            style:
                                Theme.of(context).textTheme.labelSmall),
                        if (folders.isNotEmpty)
                          Text(
                            '${folders.length} · $totalFiles file${totalFiles == 1 ? '' : 's'}',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                      ],
                    );
                  },
                  loading: () => Text('FOLDERS',
                      style: Theme.of(context).textTheme.labelSmall),
                  error: (_, _) => Text('FOLDERS',
                      style: Theme.of(context).textTheme.labelSmall),
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
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverGrid.builder(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 1.05,
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
          color: AppTheme.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.07),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(top: 3),
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
                      color: AppTheme.muted,
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
                fontSize: 16,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              _timeAgo(stats?.lastUpdated),
              style: const TextStyle(
                color: AppTheme.muted,
                fontSize: 12,
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isYou ? AppTheme.surface : AppTheme.primaryDark,
            border: isYou
                ? Border.all(color: AppTheme.muted, width: 1.5)
                : null,
          ),
          child: Center(
            child: Text(
              initial,
              style: TextStyle(
                color: isYou ? AppTheme.primaryDark : AppTheme.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: AppTheme.muted,
            fontSize: 10,
            fontWeight: FontWeight.w500,
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
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: AppTheme.muted.withValues(alpha: 0.5),
                width: 1.5,
              ),
            ),
            child: const Center(
              child: Icon(Icons.add, size: 18, color: AppTheme.muted),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Add',
            style: TextStyle(
              color: AppTheme.muted,
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
