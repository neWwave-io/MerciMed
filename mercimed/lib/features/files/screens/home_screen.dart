import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../features/auth/providers/auth_provider.dart';
import '../../../features/family/providers/family_provider.dart';
import '../../../features/family/widgets/invite_family_sheet.dart';
import '../../../shared/models/folder.dart';
import '../../../shared/models/profile.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/app_bottom_sheet.dart';
import '../providers/files_provider.dart';
import '../util/folder_icon.dart';
import '../widgets/add_menu_sheet.dart';
import 'folder_screen.dart' show UploadConfirm, UploadPreviewDialog;

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
    final action = await showAppBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: SafeArea(
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

  /// Opens the 3-option add menu (new folder / upload files / create folder
  /// with files). Wired to the home-screen FAB.
  void _openAddMenu() {
    showAddMenuSheet(
      context: context,
      onNewFolder: _showNewFolderDialog,
      onFileUpload: _uploadIntoGeneral,
      onFolderWithFiles: _createFolderAndUpload,
    );
  }

  /// Pick files → upload them into the user's "General" folder (creating it
  /// if absent). One preview dialog per file so the user can attach notes
  /// individually.
  Future<void> _uploadIntoGeneral() async {
    final folderId = await _ensureGeneralFolderId();
    if (folderId == null || !mounted) return;
    final folder = await _resolveFolderById(folderId);
    if (folder == null || !mounted) return;
    await _pickAndCommitUploads(folder);
  }

  /// Show the new-folder dialog, then upload any picked files into the new
  /// folder. If the user cancels the file picker we still keep the folder
  /// they just created — they may want it empty.
  Future<void> _createFolderAndUpload() async {
    final draft = await showDialog<_FolderDraft>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (_) => const _NewFolderDialog(),
    );
    if (draft == null || draft.name.isEmpty || !mounted) return;

    final client = ref.read(supabaseClientProvider);
    final user = client.auth.currentUser;
    if (user == null) return;

    final inserted = await client
        .from('folders')
        .insert({
          'user_id': user.id,
          'name': draft.name,
          if (draft.notes != null && draft.notes!.trim().isNotEmpty)
            'notes': draft.notes!.trim(),
        })
        .select()
        .single();
    final newFolder = Folder.fromJson(inserted);
    if (!mounted) return;
    // Realtime on `folders` will surface the new row in the home grid; no
    // explicit invalidation needed.
    await _pickAndCommitUploads(newFolder);
  }

  /// Resolves a folder id to a [Folder] for the [UploadPreviewDialog]. Reads
  /// the live stream first, falls back to a direct fetch when the stream
  /// hasn't caught up yet (e.g. just-created folder).
  Future<Folder?> _resolveFolderById(String id) async {
    final cached = ref.read(foldersProvider(null)).value ?? const <Folder>[];
    for (final f in cached) {
      if (f.id == id) return f;
    }
    final client = ref.read(supabaseClientProvider);
    final row = await client
        .from('folders')
        .select()
        .eq('id', id)
        .maybeSingle();
    if (row == null) return null;
    return Folder.fromJson(row);
  }

  Future<void> _pickAndCommitUploads(Folder folder) async {
    final notifier = ref.read(uploadNotifierProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    final drafts = await notifier.pickFiles();
    if (drafts == null || drafts.isEmpty || !mounted) {
      final err = ref.read(uploadNotifierProvider).errorMessage;
      if (err != null) {
        messenger.clearSnackBars();
        messenger.showSnackBar(SnackBar(
          backgroundColor: const Color(0xFFD64B4B),
          behavior: SnackBarBehavior.floating,
          content: Text(err, style: const TextStyle(color: Colors.white)),
        ));
      }
      return;
    }

    for (final draft in drafts) {
      if (!mounted) return;
      final confirmed = await showDialog<UploadConfirm>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.5),
        builder: (_) => UploadPreviewDialog(draft: draft, folder: folder),
      );
      if (!mounted || confirmed == null) continue;
      await notifier.upload(
        folderId: confirmed.folderId,
        file: draft.file,
        displayName: draft.displayName,
        notes: confirmed.notes,
      );
      if (!mounted) return;
      final err = ref.read(uploadNotifierProvider).errorMessage;
      if (err != null) {
        messenger.clearSnackBars();
        messenger.showSnackBar(SnackBar(
          backgroundColor: const Color(0xFFD64B4B),
          behavior: SnackBarBehavior.floating,
          content: Text(err, style: const TextStyle(color: Colors.white)),
        ));
      }
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
    final isInitialLoading = foldersAsync.value == null;
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
        if (isInitialLoading)
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
              itemCount: 4,
              itemBuilder: (_, _) => const _FolderCardSkeleton(),
            ),
          )
        else if (filtered.isEmpty)
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
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _ReorderableFolderGrid(
                folders: filtered,
                colorOffset: colorOffset,
                statsAsync: statsAsync,
                reorderEnabled: _query.isEmpty,
                onOpen: (f) => context.push('/folder/${f.id}'),
                onLongPressActions: _showFolderActions,
                onReorder: (newOrder) async {
                  // Optimistic UI lives inside the grid; here we persist.
                  try {
                    await persistFolderOrder(
                      ref.read(supabaseClientProvider),
                      newOrder,
                    );
                  } catch (e) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      backgroundColor: const Color(0xFFD64B4B),
                      behavior: SnackBarBehavior.floating,
                      content: Text(
                        'Could not save folder order: $e',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ));
                  }
                },
              ),
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
      // Hide the "add" FAB when viewing a family member's records — the viewer
      // can't create folders / upload files on someone else's account.
      floatingActionButton: activeOwner == null
          ? Padding(
              // Lift above the floating glass nav bar in MainShell.
              padding: const EdgeInsets.only(bottom: 81),
              child: _AddMenuFab(onTap: _openAddMenu),
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
                          avatarUrl: p?.avatarUrl,
                          onTap: activeOwner == null
                              ? null
                              : () => ref
                                  .read(activeOwnerProvider.notifier)
                                  .state = null,
                        ),
                        loading: () => const _AvatarItemSkeleton(),
                        error: (_, _) => const SizedBox.shrink(),
                      ),
                      ...familyAsync.when(
                        data: (members) => members.map((p) => Padding(
                              padding: const EdgeInsets.only(left: 16),
                              child: _AvatarItem(
                                label: p.fullName?.split(' ').first ?? '?',
                                initial: _initial(p.fullName),
                                isYou: activeOwner == p.id,
                                avatarUrl: p.avatarUrl,
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

// ── Add-menu FAB ─────────────────────────────────────────────────────────────

class _AddMenuFab extends StatelessWidget {
  final VoidCallback onTap;
  const _AddMenuFab({required this.onTap});

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
              Icons.add_rounded,
              size: 28,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Folder color palette ───────────────────────────────────────────────────────

// Mint-family accents tuned for AppTheme. Keep this list in sync with the
// matching `_kFolderColors` in folder_screen.dart — the same folder should
// pick up the same color across both screens.
const _kFolderColors = [
  Color(0xFF2D6B6B), // teal (primary)
  Color(0xFF5A8A6B), // sage
  Color(0xFF7BA8A8), // soft mint
  Color(0xFF4A7B8B), // slate blue
  Color(0xFF6BA591), // deep mint
  Color(0xFF8AB0B0), // sky
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
    final accent = _kFolderColors[colorIndex % _kFolderColors.length];
    final count = stats?.fileCount ?? 0;
    final icon = iconForFolder(folder);

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white,
              accent.withValues(alpha: 0.10),
            ],
          ),
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
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, color: accent, size: 22),
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
            if (count > 0)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: _FilePreviewGrid(count: count, accent: color),
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

// ── Reorderable folder grid ────────────────────────────────────────────────────

/// 2-column folder grid that supports long-press drag-and-drop reordering.
///
/// While the user drags, the grid maintains its own local order so the UI
/// stays responsive without waiting for Supabase. On drop, the new order is
/// pushed up via [onReorder] for persistence; if persistence fails, the
/// stream's authoritative order eventually overwrites the local state.
class _ReorderableFolderGrid extends StatefulWidget {
  final List<Folder> folders;
  final int colorOffset;
  final AsyncValue<Map<String, FolderStats>> statsAsync;
  final bool reorderEnabled;
  final void Function(Folder) onOpen;
  final void Function(Folder) onLongPressActions;
  final void Function(List<Folder> newOrder) onReorder;

  const _ReorderableFolderGrid({
    required this.folders,
    required this.colorOffset,
    required this.statsAsync,
    required this.reorderEnabled,
    required this.onOpen,
    required this.onLongPressActions,
    required this.onReorder,
  });

  @override
  State<_ReorderableFolderGrid> createState() => _ReorderableFolderGridState();
}

class _ReorderableFolderGridState extends State<_ReorderableFolderGrid> {
  late List<Folder> _local = List.of(widget.folders);
  int? _draggingIndex;
  int? _hoverIndex;

  @override
  void didUpdateWidget(covariant _ReorderableFolderGrid old) {
    super.didUpdateWidget(old);
    // Only sync from incoming when no drag is in flight, otherwise the stream
    // update would yank the tile out from under the user's finger.
    if (_draggingIndex == null) {
      final incoming = widget.folders;
      final changed = incoming.length != _local.length ||
          !List.generate(incoming.length, (i) => i)
              .every((i) => incoming[i].id == _local[i].id);
      if (changed) _local = List.of(incoming);
    }
  }

  void _move(int from, int to) {
    if (from == to) return;
    setState(() {
      final f = _local.removeAt(from);
      _local.insert(to, f);
    });
    widget.onReorder(List.of(_local));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const cross = 2;
        const gap = 16.0;
        final tileWidth = (constraints.maxWidth - gap) / cross;
        final tileHeight = tileWidth; // childAspectRatio: 1.0

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cross,
            crossAxisSpacing: gap,
            mainAxisSpacing: gap,
            childAspectRatio: 1.0,
          ),
          itemCount: _local.length,
          itemBuilder: (_, i) {
            final folder = _local[i];
            // Color follows the ORIGINAL folder identity (its index in the
            // incoming list + offset), so a tile keeps the same dot color
            // even after the user reorders it.
            final originalIdx = widget.folders.indexOf(folder);
            final colorIdx = (originalIdx < 0 ? i : originalIdx) +
                widget.colorOffset;
            return _ReorderableTile(
              index: i,
              tileWidth: tileWidth,
              tileHeight: tileHeight,
              folder: folder,
              colorIndex: colorIdx,
              stats: widget.statsAsync.value?[folder.id],
              reorderEnabled: widget.reorderEnabled,
              isDragging: _draggingIndex == i,
              isHover: _hoverIndex == i && _draggingIndex != i,
              onTap: () => widget.onOpen(folder),
              onActions: () => widget.onLongPressActions(folder),
              onDragStart: () => setState(() => _draggingIndex = i),
              onDragEnd: () => setState(() {
                _draggingIndex = null;
                _hoverIndex = null;
              }),
              onWillAccept: (sourceIdx) =>
                  sourceIdx != null && sourceIdx != i,
              onHover: (sourceIdx) {
                if (sourceIdx == null || sourceIdx == i) return;
                if (_hoverIndex != i) {
                  setState(() => _hoverIndex = i);
                }
              },
              onAccept: (sourceIdx) => _move(sourceIdx, i),
            );
          },
        );
      },
    );
  }
}

class _ReorderableTile extends StatelessWidget {
  final int index;
  final double tileWidth;
  final double tileHeight;
  final Folder folder;
  final int colorIndex;
  final FolderStats? stats;
  final bool reorderEnabled;
  final bool isDragging;
  final bool isHover;
  final VoidCallback onTap;
  final VoidCallback onActions;
  final VoidCallback onDragStart;
  final VoidCallback onDragEnd;
  final bool Function(int?) onWillAccept;
  final void Function(int?) onHover;
  final void Function(int) onAccept;

  const _ReorderableTile({
    required this.index,
    required this.tileWidth,
    required this.tileHeight,
    required this.folder,
    required this.colorIndex,
    required this.stats,
    required this.reorderEnabled,
    required this.isDragging,
    required this.isHover,
    required this.onTap,
    required this.onActions,
    required this.onDragStart,
    required this.onDragEnd,
    required this.onWillAccept,
    required this.onHover,
    required this.onAccept,
  });

  @override
  Widget build(BuildContext context) {
    final card = _FolderCard(
      folder: folder,
      colorIndex: colorIndex,
      stats: stats,
      onTap: onTap,
      onLongPress: onActions,
    );

    return DragTarget<int>(
      onWillAcceptWithDetails: (d) => onWillAccept(d.data),
      onMove: (d) => onHover(d.data),
      onAcceptWithDetails: (d) => onAccept(d.data),
      builder: (context, candidate, _) {
        final highlight = isHover || candidate.isNotEmpty;
        final hidden = isDragging;
        Widget tile = AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            boxShadow: highlight
                ? [
                    BoxShadow(
                      color: AppTheme.primaryDark.withValues(alpha: 0.18),
                      blurRadius: 22,
                      spreadRadius: 1,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: AnimatedScale(
            duration: const Duration(milliseconds: 140),
            scale: highlight ? 1.03 : 1.0,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 120),
              opacity: hidden ? 0.0 : 1.0,
              child: card,
            ),
          ),
        );

        if (!reorderEnabled) return tile;

        return LongPressDraggable<int>(
          data: index,
          delay: const Duration(milliseconds: 280),
          hapticFeedbackOnStart: true,
          onDragStarted: onDragStart,
          onDraggableCanceled: (_, _) => onDragEnd(),
          onDragEnd: (_) => onDragEnd(),
          onDragCompleted: onDragEnd,
          feedback: Material(
            color: Colors.transparent,
            child: Transform.scale(
              scale: 1.06,
              child: SizedBox(
                width: tileWidth,
                height: tileHeight,
                child: card,
              ),
            ),
          ),
          // The DragTarget child already animates to hidden via opacity.
          childWhenDragging: tile,
          child: tile,
        );
      },
    );
  }
}

// ── Skeleton / shimmer scaffolding ─────────────────────────────────────────────

const Color _kSkelBase = Color(0xFFE2EAEF);

class _Shimmer extends StatefulWidget {
  final Widget child;
  const _Shimmer({required this.child});

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (rect) => LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: const [
              Color(0x00FFFFFF),
              Color(0xB3FFFFFF),
              Color(0x00FFFFFF),
            ],
            stops: const [0.35, 0.5, 0.65],
            transform: _SlidingGradientTransform(percent: _ctrl.value * 2 - 1),
          ).createShader(rect),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class _SlidingGradientTransform extends GradientTransform {
  final double percent;
  const _SlidingGradientTransform({required this.percent});
  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(bounds.width * percent, 0, 0);
  }
}

class _SkelBox extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;
  const _SkelBox({this.width, required this.height, this.radius = 6});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: _kSkelBase,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class _SkelCircle extends StatelessWidget {
  final double size;
  const _SkelCircle({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: _kSkelBase,
        shape: BoxShape.circle,
      ),
    );
  }
}

class _FolderCardSkeleton extends StatelessWidget {
  const _FolderCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
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
      child: const _Shimmer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _SkelCircle(size: 8),
                Spacer(),
                _SkelBox(width: 14, height: 13, radius: 3),
              ],
            ),
            SizedBox(height: 12),
            Row(
              children: [
                _SkelBox(width: 28, height: 38, radius: 5),
                SizedBox(width: 6),
                _SkelBox(width: 28, height: 38, radius: 5),
                SizedBox(width: 6),
                _SkelBox(width: 28, height: 38, radius: 5),
              ],
            ),
            Spacer(),
            _SkelBox(width: 110, height: 15, radius: 4),
            SizedBox(height: 8),
            _SkelBox(width: 70, height: 11, radius: 3),
          ],
        ),
      ),
    );
  }
}

class _AvatarItemSkeleton extends StatelessWidget {
  const _AvatarItemSkeleton();

  @override
  Widget build(BuildContext context) {
    return const _Shimmer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 68,
            height: 68,
            child: Center(child: _SkelCircle(size: 60)),
          ),
          SizedBox(height: 8),
          _SkelBox(width: 28, height: 10, radius: 3),
        ],
      ),
    );
  }
}

/// Single row of up to 4 paper-card previews shown inside a folder tile
/// when it contains files. The last slot becomes a "+N" badge when there
/// are more than four files.
class _FilePreviewGrid extends StatelessWidget {
  final int count;
  final Color accent;
  const _FilePreviewGrid({required this.count, required this.accent});

  @override
  Widget build(BuildContext context) {
    final shown = count < 4 ? count : 4;
    final overflow = count - 4;
    const gap = 6.0;
    return SizedBox(
      height: 38,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < shown; i++) ...[
            if (i > 0) const SizedBox(width: gap),
            SizedBox(
              width: 28,
              height: 38,
              child: _MiniPaper(
                accent: accent,
                overflowLabel: (overflow > 0 && i == shown - 1)
                    ? '+$overflow'
                    : null,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MiniPaper extends StatelessWidget {
  final Color accent;
  final String? overflowLabel;
  const _MiniPaper({required this.accent, this.overflowLabel});

  @override
  Widget build(BuildContext context) {
    if (overflowLabel != null) {
      return Container(
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: accent.withValues(alpha: 0.35),
            width: 1,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          overflowLabel!,
          style: TextStyle(
            color: accent,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (_, c) {
        final w = c.maxWidth;
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(
              color: const Color(0xFFE2E8F0),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 3,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(5, 5, 5, 5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Container(
                width: w * 0.6,
                height: 3,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(1.5),
                ),
              ),
              const SizedBox(height: 4),
              Container(
                width: w * 0.82,
                height: 2,
                color: const Color(0xFFE2E8F0),
              ),
              const SizedBox(height: 2.5),
              Container(
                width: w * 0.65,
                height: 2,
                color: const Color(0xFFE2E8F0),
              ),
              const SizedBox(height: 2.5),
              Container(
                width: w * 0.5,
                height: 2,
                color: const Color(0xFFE2E8F0),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AvatarItem extends StatelessWidget {
  final String label;
  final String initial;
  final bool isYou;
  final String? avatarUrl;
  final VoidCallback? onTap;

  const _AvatarItem({
    required this.label,
    required this.initial,
    required this.isYou,
    this.avatarUrl,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const tile = Color(0xFFE3EFE9); // soft mint surface
    const accentRing = Color(0xFF1E293B);

    final initialFallback = Container(
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

    final hasUrl = avatarUrl != null && avatarUrl!.isNotEmpty;
    final circle = SizedBox(
      width: 60,
      height: 60,
      child: hasUrl
          ? ClipOval(
              child: CachedNetworkImage(
                imageUrl: avatarUrl!,
                width: 60,
                height: 60,
                fit: BoxFit.cover,
                placeholder: (_, _) => initialFallback,
                errorWidget: (_, _, _) => initialFallback,
              ),
            )
          : initialFallback,
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

class _AddFamilyButton extends StatefulWidget {
  final VoidCallback onTap;
  const _AddFamilyButton({required this.onTap});

  @override
  State<_AddFamilyButton> createState() => _AddFamilyButtonState();
}

class _AddFamilyButtonState extends State<_AddFamilyButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  );

  @override
  void dispose() {
    _glow.dispose();
    super.dispose();
  }

  void _handleTap() {
    _glow
      ..stop()
      ..forward(from: 0);
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handleTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _glow,
            builder: (_, _) {
              return CustomPaint(
                painter: _DashedCirclePainter(
                  color: const Color(0xFF4A5568).withValues(alpha: 0.55),
                ),
                foregroundPainter: _glow.isAnimating || _glow.value > 0
                    ? _GlowArcPainter(progress: _glow.value)
                    : null,
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
              );
            },
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

/// Two blue comet-tails that orbit the dashed ring in opposite directions,
/// starting from the top and meeting at the bottom, then continuing back to
/// the top. Uses a sweep gradient + blur for the comet-tail glow.
class _GlowArcPainter extends CustomPainter {
  final double progress; // 0..1, one full orbit
  _GlowArcPainter({required this.progress});

  static const double _pi = 3.141592653589793;
  static const double _twoPi = 6.283185307179586;
  static const double _tailSweep = 1.5; // ~86° comet tail
  // Vivid electric blue — pops on the mint background.
  static const Color _glowColor = Color(0xFF3B82F6);

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.width / 2 - 0.7;
    final center = Offset(size.width / 2, size.width / 2);
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Fade the whole effect out near the end so it doesn't snap.
    final fade = progress < 0.85 ? 1.0 : (1.0 - (progress - 0.85) / 0.15);

    // Two comets start at the top (12 o'clock) and run in opposite
    // directions — clockwise and counter-clockwise.
    final topAngle = -_pi / 2;
    final cwHead = topAngle + progress * _twoPi;
    final ccwHead = topAngle - progress * _twoPi;

    _drawComet(canvas, rect, head: cwHead, clockwise: true, fade: fade);
    _drawComet(canvas, rect, head: ccwHead, clockwise: false, fade: fade);
  }

  void _drawComet(
    Canvas canvas,
    Rect rect, {
    required double head,
    required bool clockwise,
    required double fade,
  }) {
    // Tail trails behind the head, so its angular start depends on direction.
    final start = clockwise ? head - _tailSweep : head;
    final shader = SweepGradient(
      startAngle: start,
      endAngle: start + _tailSweep,
      colors: clockwise
          ? [
              _glowColor.withValues(alpha: 0.0),
              _glowColor.withValues(alpha: 0.55 * fade),
              _glowColor.withValues(alpha: 0.95 * fade),
            ]
          : [
              _glowColor.withValues(alpha: 0.95 * fade),
              _glowColor.withValues(alpha: 0.55 * fade),
              _glowColor.withValues(alpha: 0.0),
            ],
      stops: const [0.0, 0.3, 1.0],
      transform: GradientRotation(start),
    ).createShader(rect);

    // Outer soft halo.
    final halo = Paint()
      ..shader = shader
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 6.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawArc(rect, start, _tailSweep, false, halo);

    // Crisp inner streak.
    final streak = Paint()
      ..shader = shader
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.4;
    canvas.drawArc(rect, start, _tailSweep, false, streak);
  }

  @override
  bool shouldRepaint(covariant _GlowArcPainter old) =>
      old.progress != progress;
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

