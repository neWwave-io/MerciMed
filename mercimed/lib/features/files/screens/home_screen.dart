import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../features/auth/providers/auth_provider.dart';
import '../../../features/family/providers/family_provider.dart';
import '../../../features/family/widgets/invite_family_sheet.dart';
import '../../../shared/models/folder.dart';
import '../../../shared/models/profile.dart';
import '../../../shared/theme/app_theme.dart';
import '../providers/files_provider.dart';

const String _kGeneralFolderName = 'General';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  bool _generalEnsureInFlight = false;
  bool _foldersOpen = true;
  bool _chatFoldersOpen = true;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Returns the existing root-level "General" folder for the auth user, or
  /// creates one and waits for it to appear in the live stream. Returns the
  /// folder id, or null if the user is signed out / insert fails.
  Future<String?> _ensureGeneralFolderId() async {
    final client = ref.read(supabaseClientProvider);
    final user = client.auth.currentUser;
    if (user == null) return null;

    // Look up directly so we don't depend on the live stream having caught up.
    final existing = await client
        .from('folders')
        .select('id')
        .eq('user_id', user.id)
        .filter('parent_folder_id', 'is', null)
        .eq('name', _kGeneralFolderName)
        .limit(1)
        .maybeSingle();
    if (existing != null) return existing['id'] as String;

    final inserted = await client
        .from('folders')
        .insert({'user_id': user.id, 'name': _kGeneralFolderName})
        .select('id')
        .single();
    return inserted['id'] as String;
  }

  /// Auto-create "General" once after folders first load, if it's missing.
  /// Only runs when the user is viewing their own records.
  void _maybeBootstrapGeneral(List<Folder> folders, String? activeOwner) {
    if (activeOwner != null) return;
    if (_generalEnsureInFlight) return;
    final hasGeneral = folders.any(
      (f) => f.parentFolderId == null && f.name == _kGeneralFolderName,
    );
    if (hasGeneral) return;
    _generalEnsureInFlight = true;
    _ensureGeneralFolderId().whenComplete(() {
      if (mounted) _generalEnsureInFlight = false;
    });
  }

  Future<void> _showFolderActions(Folder folder) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFCBD5E0),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  folder.name,
                  style: const TextStyle(
                    color: AppTheme.primaryDark,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.edit_rounded, color: AppTheme.primaryDark),
              title: const Text('Rename'),
              onTap: () => Navigator.pop(ctx, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: Color(0xFFD64B4B)),
              title: const Text(
                'Delete',
                style: TextStyle(color: Color(0xFFD64B4B)),
              ),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (action == 'rename') {
      await _showRenameFolderDialog(folder);
    } else if (action == 'delete') {
      await _confirmDeleteFolder(folder);
    }
  }

  Future<void> _showRenameFolderDialog(Folder folder) async {
    final newName = await showDialog<String>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (_) => _FolderNameDialog(
        icon: Icons.edit_rounded,
        title: 'Rename folder',
        confirmLabel: 'Save',
        initialName: folder.name,
      ),
    );
    if (newName != null && newName.isNotEmpty && newName != folder.name) {
      await ref
          .read(folderNotifierProvider.notifier)
          .rename(folder.id, newName);
    }
  }

  Future<void> _confirmDeleteFolder(Folder folder) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (_) => _DeleteFolderDialog(folderName: folder.name),
    );
    if (confirmed == true) {
      await ref.read(folderNotifierProvider.notifier).delete(folder.id);
    }
  }

  Future<void> _showNewFolderDialog() async {
    final draft = await showDialog<_FolderDraft>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (_) => const _NewFolderDialog(),
    );
    if (draft != null && draft.name.isNotEmpty) {
      await ref
          .read(folderNotifierProvider.notifier)
          .create(draft.name, notes: draft.notes);
    }
  }

  /// Builds the slivers for a single collapsible folder section (header +
  /// grid). Returns a list of slivers so the outer CustomScrollView can
  /// inline them. [foldersAsync] is either the standard or chat-folders
  /// async value, both yielding `List<Folder>` filtered to that bucket.
  List<Widget> _buildFolderSection({
    required String title,
    required AsyncValue<List<Folder>> foldersAsync,
    required AsyncValue<Map<String, FolderStats>> statsAsync,
    required bool isOpen,
    required VoidCallback onToggle,
    required String emptyMessage,
    required int colorOffset,
  }) {
    final folders = foldersAsync.value ?? const <Folder>[];
    final filtered = _query.isEmpty
        ? folders
        : folders
            .where((f) => f.name.toLowerCase().contains(_query))
            .toList();
    final totalFiles = statsAsync.value == null
        ? 0
        : folders.fold<int>(
            0,
            (sum, f) => sum + (statsAsync.value?[f.id]?.fileCount ?? 0),
          );

    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 12),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onToggle,
            child: Row(
              children: [
                AnimatedRotation(
                  duration: const Duration(milliseconds: 180),
                  turns: isOpen ? 0 : -0.25,
                  child: const Icon(
                    Icons.expand_more_rounded,
                    size: 18,
                    color: Color(0xFF4A5568),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF4A5568),
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.6,
                  ),
                ),
                const Spacer(),
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
            ),
          ),
        ),
      ),
      if (isOpen)
        if (filtered.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
              child: Center(
                child: Text(
                  _query.isEmpty ? emptyMessage : 'No results for "$_query".',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppTheme.muted,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
              ),
            ),
          )
        else
          SliverPadding(
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
                  colorIndex: idx + colorOffset,
                  stats: statsAsync.value?[folder.id],
                  onTap: () => context.push('/folder/${folder.id}'),
                  onLongPress: () => _showFolderActions(folder),
                );
              },
            ),
          ),
    ];
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

  String _activeOwnerName(List<Profile>? family, String activeId) {
    if (family == null) return 'family member';
    final match = family.firstWhere(
      (p) => p.id == activeId,
      orElse: () => Profile(id: activeId, createdAt: DateTime.now()),
    );
    final name = match.fullName?.trim();
    if (name == null || name.isEmpty) return 'family member';
    return name.split(' ').first;
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(currentUserProfileProvider);
    final foldersAsync = ref.watch(foldersProvider(null));
    final chatFoldersAsync = ref.watch(chatFoldersProvider);
    final statsAsync = ref.watch(folderStatsProvider);
    final familyAsync = ref.watch(familyMembersForHomeProvider);
    final activeOwner   = ref.watch(activeOwnerProvider);

    // Lazily ensure the default "General" folder exists for the auth user.
    if (foldersAsync is AsyncData<List<Folder>>) {
      _maybeBootstrapGeneral(foldersAsync.value, activeOwner);
    }

    // Reset bootstrap guard when the viewed owner switches so we re-check
    // if the user returns to their own records later.
    ref.listen<String?>(activeOwnerProvider, (_, _) {
      _generalEnsureInFlight = false;
    });

    return Scaffold(
      backgroundColor: Colors.transparent,
      // Hide the "new folder" FAB when viewing a family member's records —
      // the viewer can't create folders on someone else's account.
      floatingActionButton: activeOwner == null
          ? Padding(
              // Lift above the floating glass nav bar in MainShell.
              padding: const EdgeInsets.only(bottom: 81),
              child: _NewFolderFab(onTap: _showNewFolderDialog),
            )
          : null,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            // ── Viewing-family banner ────────────────────────────────
            if (activeOwner != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                  child: _ViewingFamilyBanner(
                    name: _activeOwnerName(familyAsync.value, activeOwner),
                    onExit: () =>
                        ref.read(activeOwnerProvider.notifier).state = null,
                  ),
                ),
              ),

            // ── Top bar ───────────────────────────────────────────────
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(24, 16, 24, 0),
                child: Text(
                  'MerciMed',
                  style: TextStyle(
                    color: AppTheme.primaryDark,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                    height: 1.3,
                  ),
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
                          isYou: activeOwner == null,
                          onTap: activeOwner == null
                              ? null
                              : () => ref
                                  .read(activeOwnerProvider.notifier)
                                  .state = null,
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
                                isYou: activeOwner == p.id,
                                onTap: () => ref
                                    .read(activeOwnerProvider.notifier)
                                    .state = p.id,
                              ),
                            )).toList(),
                        loading: () => <Widget>[],
                        error: (_, _) => <Widget>[],
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 16),
                        child: _AddFamilyButton(
                          onTap: () => showInviteFamilySheet(context),
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
                child: _GlassSearchField(
                  controller: _searchCtrl,
                  onChanged: (v) =>
                      setState(() => _query = v.toLowerCase()),
                ),
              ),
            ),

            ..._buildFolderSection(
              title: 'FOLDERS',
              foldersAsync: foldersAsync,
              statsAsync: statsAsync,
              isOpen: _foldersOpen,
              onToggle: () => setState(() => _foldersOpen = !_foldersOpen),
              emptyMessage: 'Setting up your records…',
              colorOffset: 0,
            ),
            // Hide the Chat Folders section entirely when viewing a family
            // member's records — those folders are private to the chat owner.
            if (activeOwner == null)
              ..._buildFolderSection(
                title: 'CHAT FOLDERS',
                foldersAsync: chatFoldersAsync,
                statsAsync: statsAsync,
                isOpen: _chatFoldersOpen,
                onToggle: () =>
                    setState(() => _chatFoldersOpen = !_chatFoldersOpen),
                emptyMessage:
                    'Upload a file in chat to start one — Mercie names it after your conversation.',
                colorOffset: 3,
              ),

            const SliverToBoxAdapter(child: SizedBox(height: 120)),
          ],
        ),
      ),
    );
  }
}

// ── New-folder dialog (name + notes + AI revise) ─────────────────────────────

class _FolderDraft {
  final String name;
  final String? notes;
  const _FolderDraft({required this.name, this.notes});
}

class _NewFolderDialog extends ConsumerStatefulWidget {
  const _NewFolderDialog();

  @override
  ConsumerState<_NewFolderDialog> createState() => _NewFolderDialogState();
}

class _NewFolderDialogState extends ConsumerState<_NewFolderDialog> {
  final _nameCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _revising = false;
  String? _reviseError;

  @override
  void initState() {
    super.initState();
    _nameCtrl.addListener(_onNameChanged);
  }

  @override
  void dispose() {
    _nameCtrl
      ..removeListener(_onNameChanged)
      ..dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _onNameChanged() => setState(() {});

  bool get _canSubmit => _nameCtrl.text.trim().isNotEmpty;

  Future<void> _revise() async {
    final text = _notesCtrl.text.trim();
    if (text.isEmpty || _revising) return;
    setState(() {
      _revising = true;
      _reviseError = null;
    });
    try {
      final client = ref.read(supabaseClientProvider);
      final revised = await reviseNote(
        client,
        text,
        context: _nameCtrl.text.trim().isEmpty
            ? null
            : 'Folder name: ${_nameCtrl.text.trim()}',
      );
      _notesCtrl.text = revised;
      _notesCtrl.selection = TextSelection.collapsed(offset: revised.length);
    } catch (e) {
      final msg = e is Exception ? e.toString().replaceFirst('Exception: ', '') : '$e';
      setState(() => _reviseError = msg);
    } finally {
      if (mounted) setState(() => _revising = false);
    }
  }

  void _submit() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    final notes = _notesCtrl.text.trim();
    Navigator.of(context).pop(
      _FolderDraft(name: name, notes: notes.isEmpty ? null : notes),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 30,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(22, 26, 22, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppTheme.primaryDark.withValues(alpha: 0.07),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.create_new_folder_outlined,
                  color: AppTheme.primaryDark,
                  size: 26,
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Center(
              child: Text(
                'New folder',
                style: TextStyle(
                  color: AppTheme.primaryDark,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),
            ),
            const SizedBox(height: 18),

            // ── Name field ───────────────────────────────────────
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF1F4F8),
                borderRadius: BorderRadius.circular(14),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _nameCtrl,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                style: const TextStyle(
                  color: AppTheme.primaryDark,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  hintText: 'Folder name',
                  hintStyle: TextStyle(
                    color: AppTheme.primaryDark.withValues(alpha: 0.4),
                    fontWeight: FontWeight.w500,
                  ),
                  isDense: true,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // ── Notes label ──────────────────────────────────────
            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 6),
              child: Text(
                'Notes (optional)',
                style: TextStyle(
                  color: Color(0xFF4A5568),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
            ),

            // ── Notes field ──────────────────────────────────────
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF1F4F8),
                borderRadius: BorderRadius.circular(14),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _notesCtrl,
                maxLines: 4,
                minLines: 3,
                textCapitalization: TextCapitalization.sentences,
                style: const TextStyle(
                  color: AppTheme.primaryDark,
                  fontSize: 14,
                  height: 1.4,
                ),
                decoration: InputDecoration(
                  hintText:
                      'What\'s this folder for? e.g. lab results from Dr. Pham, summer 2025.',
                  hintStyle: TextStyle(
                    color: AppTheme.primaryDark.withValues(alpha: 0.4),
                    fontWeight: FontWeight.w400,
                  ),
                  isDense: true,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),

            // ── AI revise row ────────────────────────────────────
            const SizedBox(height: 10),
            Row(
              children: [
                if (_reviseError != null)
                  Expanded(
                    child: Text(
                      _reviseError!,
                      style: const TextStyle(
                        color: Color(0xFFD64B4B),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  )
                else
                  const Spacer(),
                _ReviseAiButton(
                  loading: _revising,
                  enabled: _notesCtrl.text.trim().isNotEmpty,
                  onTap: _revise,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Action buttons ───────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: _DialogButton(
                    label: 'Cancel',
                    onTap: () => Navigator.of(context).pop(),
                    variant: _BtnVariant.secondary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _DialogButton(
                    label: 'Create',
                    onTap: _canSubmit ? _submit : null,
                    variant: _BtnVariant.primary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviseAiButton extends StatelessWidget {
  final bool loading;
  final bool enabled;
  final VoidCallback onTap;

  const _ReviseAiButton({
    required this.loading,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final active = enabled && !loading;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: active ? onTap : null,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 160),
          opacity: active ? 1.0 : 0.5,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF2D6B6B), Color(0xFF2A2150)],
              ),
              borderRadius: BorderRadius.circular(999),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF2D6B6B).withValues(alpha: 0.25),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (loading)
                  const SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.8,
                      color: Colors.white,
                    ),
                  )
                else
                  const Icon(
                    Icons.auto_awesome_rounded,
                    color: Colors.white,
                    size: 14,
                  ),
                const SizedBox(width: 6),
                Text(
                  loading ? 'Polishing…' : 'Revise with AI',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Folder name dialog (rename only) ──────────────────────────────────────────

class _FolderNameDialog extends StatefulWidget {
  final IconData icon;
  final String title;
  final String confirmLabel;
  final String initialName;

  const _FolderNameDialog({
    required this.icon,
    required this.title,
    required this.confirmLabel,
    this.initialName = '',
  });

  @override
  State<_FolderNameDialog> createState() => _FolderNameDialogState();
}

class _FolderNameDialogState extends State<_FolderNameDialog> {
  late final TextEditingController _ctrl;
  bool _canSubmit = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialName)
      ..selection = TextSelection(
        baseOffset: 0,
        extentOffset: widget.initialName.length,
      );
    _canSubmit = _ctrl.text.trim().isNotEmpty;
    _ctrl.addListener(() {
      final ok = _ctrl.text.trim().isNotEmpty;
      if (ok != _canSubmit) setState(() => _canSubmit = ok);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final v = _ctrl.text.trim();
    if (v.isEmpty) return;
    Navigator.of(context).pop(v);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 30,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppTheme.primaryDark.withValues(alpha: 0.07),
                shape: BoxShape.circle,
              ),
              child: Icon(
                widget.icon,
                color: AppTheme.primaryDark,
                size: 26,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              widget.title,
              style: const TextStyle(
                color: AppTheme.primaryDark,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 18),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF1F4F8),
                borderRadius: BorderRadius.circular(14),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _ctrl,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                style: const TextStyle(
                  color: AppTheme.primaryDark,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  hintText: 'Folder name',
                  hintStyle: TextStyle(
                    color: AppTheme.primaryDark.withValues(alpha: 0.4),
                    fontWeight: FontWeight.w500,
                  ),
                  isDense: true,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _DialogButton(
                    label: 'Cancel',
                    onTap: () => Navigator.of(context).pop(),
                    variant: _BtnVariant.secondary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _DialogButton(
                    label: widget.confirmLabel,
                    onTap: _canSubmit ? _submit : null,
                    variant: _BtnVariant.primary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Delete-folder confirmation dialog ─────────────────────────────────────────

class _DeleteFolderDialog extends StatelessWidget {
  final String folderName;
  const _DeleteFolderDialog({required this.folderName});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 30,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: const Color(0xFFD64B4B).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.delete_outline_rounded,
                color: Color(0xFFD64B4B),
                size: 28,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Delete folder?',
              style: TextStyle(
                color: AppTheme.primaryDark,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 10),
            Text.rich(
              TextSpan(
                style: const TextStyle(
                  color: Color(0xFF4A5568),
                  fontSize: 14,
                  height: 1.5,
                  fontWeight: FontWeight.w500,
                ),
                children: [
                  const TextSpan(text: 'Delete '),
                  TextSpan(
                    text: '"$folderName"',
                    style: const TextStyle(
                      color: AppTheme.primaryDark,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const TextSpan(
                    text:
                        '? Files inside will be kept — they will move to the root.',
                  ),
                ],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: _DialogButton(
                    label: 'Cancel',
                    onTap: () => Navigator.of(context).pop(false),
                    variant: _BtnVariant.secondary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _DialogButton(
                    label: 'Delete',
                    onTap: () => Navigator.of(context).pop(true),
                    variant: _BtnVariant.destructive,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shared dialog button ──────────────────────────────────────────────────────

enum _BtnVariant { primary, secondary, destructive }

class _DialogButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final _BtnVariant variant;

  const _DialogButton({
    required this.label,
    required this.onTap,
    required this.variant,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    Color bg;
    Color fg;
    switch (variant) {
      case _BtnVariant.primary:
        bg = const Color(0xFF1A212B);
        fg = Colors.white;
        break;
      case _BtnVariant.destructive:
        bg = const Color(0xFFD64B4B);
        fg = Colors.white;
        break;
      case _BtnVariant.secondary:
        bg = const Color(0xFFF1F4F8);
        fg = AppTheme.primaryDark;
        break;
    }
    if (disabled) {
      bg = bg.withValues(alpha: 0.45);
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.1,
            ),
          ),
        ),
      ),
    );
  }
}

// ── New-folder FAB ────────────────────────────────────────────────────────────

class _NewFolderFab extends StatelessWidget {
  final VoidCallback onTap;
  const _NewFolderFab({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryDark.withValues(alpha: 0.28),
            blurRadius: 22,
            spreadRadius: -2,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Material(
        color: AppTheme.primaryDark,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: const SizedBox(
            width: 60,
            height: 60,
            child: Icon(
              Icons.create_new_folder_outlined,
              size: 26,
              color: Colors.white,
            ),
          ),
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
  final VoidCallback? onLongPress;

  const _FolderCard({
    required this.folder,
    required this.colorIndex,
    this.stats,
    required this.onTap,
    this.onLongPress,
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
      onLongPress: onLongPress,
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
  final VoidCallback? onTap;

  const _AvatarItem({
    required this.label,
    required this.initial,
    required this.isYou,
    this.onTap,
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

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
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
      ),
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

// ── Viewing-family banner ──────────────────────────────────────────────────────

class _ViewingFamilyBanner extends StatelessWidget {
  final String name;
  final VoidCallback onExit;

  const _ViewingFamilyBanner({required this.name, required this.onExit});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1A212B),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.visibility_rounded, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              "Viewing $name's records",
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: onExit,
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              minimumSize: const Size(0, 32),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Exit',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Glass search field ─────────────────────────────────────────────────────────

class _GlassSearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  const _GlassSearchField({
    required this.controller,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    const radius = 999.0; // fully pill-shaped

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          // Soft drop — grounds the pill on the gradient.
          BoxShadow(
            color: AppTheme.primaryDark.withValues(alpha: 0.08),
            blurRadius: 22,
            spreadRadius: -2,
            offset: const Offset(0, 8),
          ),
          // Subtle top lift — sells the floating-glass feel.
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.5),
            blurRadius: 12,
            spreadRadius: -6,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
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
            child: TextField(
              controller: controller,
              onChanged: onChanged,
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
    );
  }
}

