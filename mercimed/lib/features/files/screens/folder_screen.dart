import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';

import '../../../features/auth/providers/auth_provider.dart';
import '../../../shared/models/file_model.dart';
import '../../../shared/models/folder.dart';
import '../../../shared/theme/app_theme.dart';
import '../providers/files_provider.dart';

const _kFolderColors = [
  Color(0xFFC26D6D),
  Color(0xFF5A9A94),
  Color(0xFFB5945A),
  Color(0xFF5A8BA5),
  Color(0xFF7B6B8A),
  Color(0xFF5A8A6B),
];

enum _DocFilter { all, pdf, image }

enum _ViewMode { list, grid }

class FolderScreen extends ConsumerStatefulWidget {
  final String folderId;

  const FolderScreen({required this.folderId, super.key});

  @override
  ConsumerState<FolderScreen> createState() => _FolderScreenState();
}

enum _SortMode { newest, oldest, nameAsc, nameDesc }

class _FolderScreenState extends ConsumerState<FolderScreen> {
  _DocFilter _filter = _DocFilter.all;
  _ViewMode _viewMode = _ViewMode.list;
  _SortMode _sort = _SortMode.newest;

  bool _searchActive = false;
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Color _folderColor(List<Folder> folders, String id) {
    final idx = folders.indexWhere((f) => f.id == id);
    final i = idx < 0 ? id.hashCode.abs() : idx;
    return _kFolderColors[i % _kFolderColors.length];
  }

  String _timeAgo(DateTime? dt) {
    if (dt == null) return 'just now';
    final d = DateTime.now().difference(dt);
    if (d.inDays > 60) return '${d.inDays ~/ 30} months ago';
    if (d.inDays > 6)  return '${d.inDays ~/ 7} weeks ago';
    if (d.inDays > 0)  return '${d.inDays} days ago';
    if (d.inHours > 0) return '${d.inHours}h ago';
    if (d.inMinutes > 0) return '${d.inMinutes}m ago';
    return 'just now';
  }

  Widget _defaultTopBar(Folder folder) {
    return Row(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/home');
            }
          },
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.arrow_back_ios_new_rounded,
                  size: 18,
                  color: AppTheme.primaryDark,
                ),
                SizedBox(width: 6),
                Text(
                  'Home',
                  style: TextStyle(
                    color: AppTheme.primaryDark,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        const Spacer(),
        IconButton(
          tooltip: 'Search files',
          onPressed: () => setState(() => _searchActive = true),
          icon: const Icon(
            Icons.search_rounded,
            size: 22,
            color: AppTheme.primaryDark,
          ),
        ),
        IconButton(
          tooltip: 'Folder options',
          onPressed: () => _showFolderMenu(folder),
          icon: const Icon(
            Icons.more_horiz_rounded,
            size: 22,
            color: AppTheme.primaryDark,
          ),
        ),
      ],
    );
  }

  Widget _searchBar() {
    return Row(
      children: [
        IconButton(
          tooltip: 'Close search',
          onPressed: () {
            _searchCtrl.clear();
            setState(() {
              _searchQuery = '';
              _searchActive = false;
            });
          },
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 18,
            color: AppTheme.primaryDark,
          ),
        ),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.9),
                width: 1,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: TextField(
              controller: _searchCtrl,
              autofocus: true,
              onChanged: (v) => setState(() => _searchQuery = v.trim()),
              style: const TextStyle(
                color: AppTheme.primaryDark,
                fontSize: 14,
              ),
              decoration: InputDecoration(
                hintText: 'Search file name or notes',
                hintStyle: TextStyle(
                  color: AppTheme.primaryDark.withValues(alpha: 0.45),
                ),
                isDense: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                suffixIcon: _searchQuery.isEmpty
                    ? null
                    : IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: const Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: Color(0xFF6B7C8C),
                        ),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _searchQuery = '');
                        },
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showFolderMenu(Folder folder) async {
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
              leading: Icon(
                _sort == _SortMode.newest
                    ? Icons.check_rounded
                    : Icons.schedule_rounded,
                color: AppTheme.primaryDark,
              ),
              title: const Text('Sort: Newest first'),
              onTap: () => Navigator.pop(ctx, 'sort_newest'),
            ),
            ListTile(
              leading: Icon(
                _sort == _SortMode.oldest
                    ? Icons.check_rounded
                    : Icons.history_rounded,
                color: AppTheme.primaryDark,
              ),
              title: const Text('Sort: Oldest first'),
              onTap: () => Navigator.pop(ctx, 'sort_oldest'),
            ),
            ListTile(
              leading: Icon(
                _sort == _SortMode.nameAsc
                    ? Icons.check_rounded
                    : Icons.sort_by_alpha_rounded,
                color: AppTheme.primaryDark,
              ),
              title: const Text('Sort: Name A → Z'),
              onTap: () => Navigator.pop(ctx, 'sort_name_asc'),
            ),
            ListTile(
              leading: Icon(
                _sort == _SortMode.nameDesc
                    ? Icons.check_rounded
                    : Icons.sort_by_alpha_rounded,
                color: AppTheme.primaryDark,
              ),
              title: const Text('Sort: Name Z → A'),
              onTap: () => Navigator.pop(ctx, 'sort_name_desc'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.edit_rounded, color: AppTheme.primaryDark),
              title: const Text('Rename folder'),
              onTap: () => Navigator.pop(ctx, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: Color(0xFFD64B4B)),
              title: const Text(
                'Delete folder',
                style: TextStyle(color: Color(0xFFD64B4B)),
              ),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'sort_newest':
        setState(() => _sort = _SortMode.newest);
      case 'sort_oldest':
        setState(() => _sort = _SortMode.oldest);
      case 'sort_name_asc':
        setState(() => _sort = _SortMode.nameAsc);
      case 'sort_name_desc':
        setState(() => _sort = _SortMode.nameDesc);
      case 'rename':
        await _renameFolder(folder);
      case 'delete':
        await _deleteFolder(folder);
    }
  }

  Future<void> _renameFolder(Folder folder) async {
    final ctrl = TextEditingController(text: folder.name);
    final newName = await showDialog<String>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Rename folder'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            hintText: 'Folder name',
            isDense: true,
            filled: false,
            border: UnderlineInputBorder(),
            enabledBorder: UnderlineInputBorder(),
            focusedBorder: UnderlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (newName != null && newName.isNotEmpty && newName != folder.name) {
      await ref.read(folderNotifierProvider.notifier).rename(folder.id, newName);
    }
  }

  Future<void> _deleteFolder(Folder folder) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete folder?'),
        content: Text(
          'Delete "${folder.name}"? Files inside will be kept — they move to the root.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFD64B4B)),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    await ref.read(folderNotifierProvider.notifier).delete(folder.id);
    if (!mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
  }

  Future<void> _onUploadTap(
    BuildContext context,
    WidgetRef ref,
    Folder folder,
  ) async {
    final notifier = ref.read(uploadNotifierProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);

    // Step 1: pick a file (no upload yet).
    final draft = await notifier.pickFile();
    if (!mounted) return;
    final pickErr = ref.read(uploadNotifierProvider).errorMessage;
    if (draft == null) {
      if (pickErr != null) {
        messenger.clearSnackBars();
        messenger.showSnackBar(SnackBar(
          backgroundColor: const Color(0xFFD64B4B),
          behavior: SnackBarBehavior.floating,
          content: Text(pickErr, style: const TextStyle(color: Colors.white)),
        ));
      }
      return;
    }

    // Step 2: confirm with preview + optional notes.
    if (!context.mounted) return;
    final confirmed = await showDialog<UploadConfirm>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (_) => UploadPreviewDialog(draft: draft, folder: folder),
    );
    if (!mounted || confirmed == null) return;

    // Step 3: upload + insert (notes + destination folder attached).
    // Scan auto-fires on insert via the DB webhook.
    final id = await notifier.upload(
      folderId: confirmed.folderId,
      file: draft.file,
      displayName: draft.displayName,
      notes: confirmed.notes,
    );

    if (!mounted) return;
    final err = ref.read(uploadNotifierProvider).errorMessage;
    if (id == null && err != null) {
      messenger.clearSnackBars();
      messenger.showSnackBar(SnackBar(
        backgroundColor: const Color(0xFFD64B4B),
        behavior: SnackBarBehavior.floating,
        content: Text(err, style: const TextStyle(color: Colors.white)),
        action: SnackBarAction(
          label: 'Retry',
          textColor: Colors.white,
          onPressed: () {
            notifier.clearError();
            _onUploadTap(context, ref, folder);
          },
        ),
      ));
    }
  }

  bool _matchesFilter(FileModel f) {
    if (_filter != _DocFilter.all) {
      final ext = _ext(f.fileName);
      if (_filter == _DocFilter.pdf && ext != 'pdf') return false;
      if (_filter == _DocFilter.image &&
          !const {'jpg', 'jpeg', 'png', 'heic', 'webp', 'gif'}.contains(ext)) {
        return false;
      }
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      final inName = f.fileName.toLowerCase().contains(q);
      final inNotes = (f.notes ?? '').toLowerCase().contains(q);
      if (!inName && !inNotes) return false;
    }
    return true;
  }

  int _compareForSort(FileModel a, FileModel b) {
    switch (_sort) {
      case _SortMode.newest:
        return b.createdAt.compareTo(a.createdAt);
      case _SortMode.oldest:
        return a.createdAt.compareTo(b.createdAt);
      case _SortMode.nameAsc:
        return a.fileName.toLowerCase().compareTo(b.fileName.toLowerCase());
      case _SortMode.nameDesc:
        return b.fileName.toLowerCase().compareTo(a.fileName.toLowerCase());
    }
  }

  static String _ext(String name) {
    final i = name.lastIndexOf('.');
    if (i < 0 || i == name.length - 1) return '';
    return name.substring(i + 1).toLowerCase();
  }

  @override
  Widget build(BuildContext context) {
    final foldersAsync = ref.watch(foldersProvider(null));
    final filesAsync = ref.watch(filesProvider(widget.folderId));

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: foldersAsync.maybeWhen(
        data: (folders) {
          final folder = folders.firstWhere(
            (f) => f.id == widget.folderId,
            orElse: () => Folder(
              id: widget.folderId,
              userId: '',
              name: 'Folder',
              createdAt: DateTime.now(),
            ),
          );
          return Consumer(
            builder: (context, ref, _) {
              final uploadState = ref.watch(uploadNotifierProvider);
              return _AddDocumentFab(
                uploadState: uploadState,
                onTap: () => _onUploadTap(context, ref, folder),
              );
            },
          );
        },
        orElse: () => const SizedBox.shrink(),
      ),
      body: Stack(
        children: [
          // ── White base + soft blobs (per design) ─────────────────
          const Positioned.fill(child: _FolderBackdrop()),

          // ── Content ──────────────────────────────────────────────
          foldersAsync.when(
            data: (folders) {
              final folder = folders.firstWhere(
                (f) => f.id == widget.folderId,
                orElse: () => Folder(
                  id: widget.folderId,
                  userId: '',
                  name: 'Folder',
                  createdAt: DateTime.now(),
                ),
              );
              final color = _folderColor(folders, folder.id);

              return filesAsync.when(
                data: (files) => _buildContent(folder, color, files),
                loading: () => _buildContent(folder, color, const []),
                error: (e, _) => _buildContent(folder, color, const []),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => const Center(
              child: Text(
                'Could not load folder.',
                style: TextStyle(color: AppTheme.muted),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(Folder folder, Color color, List<FileModel> files) {
    final filtered = files.where(_matchesFilter).toList()..sort(_compareForSort);
    final pdfCount = files.where((f) => _ext(f.fileName) == 'pdf').length;
    final imgCount = files.where((f) {
      final e = _ext(f.fileName);
      return const {'jpg', 'jpeg', 'png', 'heic', 'webp', 'gif'}.contains(e);
    }).length;
    final lastUpdated = files.isEmpty
        ? null
        : files
            .map((f) => f.createdAt)
            .reduce((a, b) => a.isAfter(b) ? a : b);

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 110),
            children: [
              // ── Top bar ─────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 16, 8),
                child: _searchActive
                    ? _searchBar()
                    : _defaultTopBar(folder),
              ),

              // ── Folder header ──────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          folder.name.toUpperCase(),
                          style: TextStyle(
                            color: color,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.6,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '${files.length} document${files.length == 1 ? '' : 's'}.',
                      style: const TextStyle(
                        color: AppTheme.primaryDark,
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.8,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      lastUpdated == null
                          ? 'No documents yet'
                          : 'Updated ${_timeAgo(lastUpdated)}',
                      style: const TextStyle(
                        color: Color(0xFF4A5568),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

              // ── Filter chips ───────────────────────────────────────
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  children: [
                    _FilterChip(
                      label: 'All • ${files.length}',
                      selected: _filter == _DocFilter.all,
                      onTap: () => setState(() => _filter = _DocFilter.all),
                    ),
                    const SizedBox(width: 12),
                    _FilterChip(
                      label: 'PDF • $pdfCount',
                      selected: _filter == _DocFilter.pdf,
                      onTap: () => setState(() => _filter = _DocFilter.pdf),
                    ),
                    const SizedBox(width: 12),
                    _FilterChip(
                      label: 'Images • $imgCount',
                      selected: _filter == _DocFilter.image,
                      onTap: () => setState(() => _filter = _DocFilter.image),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ── Count + view toggle ────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                child: Row(
                  children: [
                    Text(
                      filtered.isEmpty
                          ? 'No items'
                          : '${filtered.length} item${filtered.length == 1 ? '' : 's'}',
                      style: const TextStyle(
                        color: Color(0xFF4A5568),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const Spacer(),
                    _ViewModeToggle(
                      mode: _viewMode,
                      onChanged: (m) => setState(() => _viewMode = m),
                    ),
                  ],
                ),
              ),

              // ── Document list / grid ───────────────────────────────
              if (filtered.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 40, 24, 0),
                  child: Center(
                    child: Text(
                      files.isEmpty
                          ? 'No documents in this folder yet.\nTap the button below to add one.'
                          : 'No documents match this filter.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF6B7C8C),
                        fontSize: 14,
                        height: 1.6,
                      ),
                    ),
                  ),
                )
              else if (_viewMode == _ViewMode.list)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      for (var i = 0; i < filtered.length; i++) ...[
                        _DocumentItem(
                          file: filtered[i],
                          onTap: () =>
                              context.push('/file/${filtered[i].id}'),
                          onRetryScan: () => ref
                              .read(uploadNotifierProvider.notifier)
                              .retryScan(filtered[i].id),
                        ),
                        if (i < filtered.length - 1)
                          const SizedBox(height: 14),
                      ],
                    ],
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 14,
                      mainAxisSpacing: 14,
                      childAspectRatio: 0.82,
                    ),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) => _DocumentCard(
                      file: filtered[i],
                      onTap: () => context.push('/file/${filtered[i].id}'),
                      onRetryScan: () => ref
                          .read(uploadNotifierProvider.notifier)
                          .retryScan(filtered[i].id),
                    ),
                  ),
                ),
        ],
      ),
    );
  }
}

// ── White backdrop with soft radial blobs (matches design DSL) ────────────────

class _FolderBackdrop extends StatelessWidget {
  const _FolderBackdrop();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: Colors.white),
      child: CustomPaint(
        painter: _FolderBlobsPainter(),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _FolderBlobsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Top-center soft blue
    _blob(
      canvas,
      Offset(w * 0.6, h * -0.05),
      radius: w * 0.85,
      color: const Color(0xFFB6D2E0).withValues(alpha: 0.55),
    );

    // Bottom-left soft mint
    _blob(
      canvas,
      Offset(w * -0.25, h * 0.85),
      radius: w * 0.95,
      color: const Color(0xFFC7DFD8).withValues(alpha: 0.55),
    );

    // Bottom-right deeper mint
    _blob(
      canvas,
      Offset(w * 1.1, h * 1.05),
      radius: w * 1.0,
      color: const Color(0xFFCCE0D6).withValues(alpha: 0.55),
    );
  }

  void _blob(
    Canvas canvas,
    Offset center, {
    required double radius,
    required Color color,
  }) {
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [color, color.withValues(alpha: 0)],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 60);
    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(covariant _FolderBlobsPainter old) => false;
}

// ── Filter chip ────────────────────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF1A212B)
              : Colors.white.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
            color: selected
                ? const Color(0xFF1A212B)
                : Colors.white.withValues(alpha: 0.9),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppTheme.primaryDark,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}

// ── View-mode toggle (list / grid) ────────────────────────────────────────────

class _ViewModeToggle extends StatelessWidget {
  final _ViewMode mode;
  final ValueChanged<_ViewMode> onChanged;

  const _ViewModeToggle({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.9),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ToggleIcon(
            icon: Icons.format_list_bulleted_rounded,
            selected: mode == _ViewMode.list,
            onTap: () => onChanged(_ViewMode.list),
          ),
          _ToggleIcon(
            icon: Icons.grid_view_rounded,
            selected: mode == _ViewMode.grid,
            onTap: () => onChanged(_ViewMode.grid),
          ),
        ],
      ),
    );
  }
}

class _ToggleIcon extends StatelessWidget {
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ToggleIcon({
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? AppTheme.primaryDark : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Icon(
            icon,
            size: 16,
            color: selected ? Colors.white : const Color(0xFF6B7C8C),
          ),
        ),
      ),
    );
  }
}

// ── Document row ───────────────────────────────────────────────────────────────

class _DocumentItem extends StatelessWidget {
  final FileModel file;
  final VoidCallback onTap;
  final VoidCallback? onRetryScan;

  const _DocumentItem({
    required this.file,
    required this.onTap,
    this.onRetryScan,
  });

  String get _ext {
    final n = file.fileName;
    final i = n.lastIndexOf('.');
    if (i < 0 || i == n.length - 1) return '';
    return n.substring(i + 1).toLowerCase();
  }

  String get _badge {
    if (_ext == 'pdf') return 'PDF';
    if (const {'jpg', 'jpeg', 'png', 'heic', 'webp', 'gif'}.contains(_ext)) {
      return 'IMG';
    }
    if (_ext.isEmpty) return 'FILE';
    return _ext.toUpperCase().substring(0, _ext.length.clamp(0, 4));
  }

  Color get _badgeColor {
    if (_ext == 'pdf') return const Color(0xFFD64B4B);
    if (const {'jpg', 'jpeg', 'png', 'heic', 'webp', 'gif'}.contains(_ext)) {
      return const Color(0xFF5A9A94);
    }
    return const Color(0xFF6B7C8C);
  }

  String _shortDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[d.month - 1]} ${d.day.toString().padLeft(2, '0')}';
  }

  String? get _statusBadge {
    switch (file.aiScanStatus) {
      case 'pending':
      case 'processing':
        return 'pending';
      case 'done':
      case 'completed':
        return 'done';
      case 'failed':
      case 'error':
        return 'failed';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 14,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Type badge
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: _badgeColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: Text(
                _badge,
                style: TextStyle(
                  color: _badgeColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
            ),
            const SizedBox(width: 14),
            // Title + meta
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    file.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.primaryDark,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _shortDate(file.createdAt),
                    style: const TextStyle(
                      color: Color(0xFF6B7C8C),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (_statusBadge != null) ...[
                    const SizedBox(height: 6),
                    _ScanStatusPill(
                      status: _statusBadge!,
                      onRetry: onRetryScan,
                    ),
                  ],
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: Color(0xFF6B7C8C),
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Document card (grid view) ─────────────────────────────────────────────────

class _DocumentCard extends StatelessWidget {
  final FileModel file;
  final VoidCallback onTap;
  final VoidCallback? onRetryScan;

  const _DocumentCard({
    required this.file,
    required this.onTap,
    this.onRetryScan,
  });

  String get _ext {
    final n = file.fileName;
    final i = n.lastIndexOf('.');
    if (i < 0 || i == n.length - 1) return '';
    return n.substring(i + 1).toLowerCase();
  }

  bool get _isPdf => _ext == 'pdf';
  bool get _isImage =>
      const {'jpg', 'jpeg', 'png', 'heic', 'webp', 'gif'}.contains(_ext);

  String get _badge {
    if (_isPdf) return 'PDF';
    if (_isImage) return 'IMG';
    if (_ext.isEmpty) return 'FILE';
    return _ext.toUpperCase().substring(0, _ext.length.clamp(0, 4));
  }

  Color get _badgeColor {
    if (_isPdf) return const Color(0xFFD64B4B);
    if (_isImage) return const Color(0xFF5A9A94);
    return const Color(0xFF6B7C8C);
  }

  IconData get _typeIcon {
    if (_isPdf) return Icons.picture_as_pdf_outlined;
    if (_isImage) return Icons.image_outlined;
    return Icons.insert_drive_file_outlined;
  }

  String _shortDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[d.month - 1]} ${d.day.toString().padLeft(2, '0')}';
  }

  String? get _statusBadge {
    switch (file.aiScanStatus) {
      case 'pending':
      case 'processing':
        return 'pending';
      case 'done':
      case 'completed':
        return 'done';
      case 'failed':
      case 'error':
        return 'failed';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 14,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Preview area ─────────────────────────────────────
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  width: double.infinity,
                  color: _badgeColor.withValues(alpha: 0.08),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _FilePreviewWidget(
                        file: file,
                        placeholderIcon: _typeIcon,
                        placeholderColor: _badgeColor,
                      ),
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: _badgeColor,
                            borderRadius: BorderRadius.circular(6),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.15),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Text(
                            _badge,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            // ── File name ───────────────────────────────────────
            Text(
              file.fileName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.primaryDark,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 4),
            // ── Date + status ───────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: Text(
                    _shortDate(file.createdAt),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF6B7C8C),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (_statusBadge != null)
                  _ScanStatusPill(
                    status: _statusBadge!,
                    onRetry: onRetryScan,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── File preview (image via signed URL, PDF via local PDFView) ───────────────

class _FilePreviewWidget extends ConsumerStatefulWidget {
  final FileModel file;
  final IconData placeholderIcon;
  final Color placeholderColor;

  const _FilePreviewWidget({
    required this.file,
    required this.placeholderIcon,
    required this.placeholderColor,
  });

  @override
  ConsumerState<_FilePreviewWidget> createState() => _FilePreviewWidgetState();
}

class _FilePreviewWidgetState extends ConsumerState<_FilePreviewWidget> {
  String? _imageUrl;
  String? _pdfPath;
  bool _loading = true;
  bool _failed = false;

  String get _ext {
    final n = widget.file.fileName;
    final i = n.lastIndexOf('.');
    if (i < 0 || i == n.length - 1) return '';
    return n.substring(i + 1).toLowerCase();
  }

  bool get _isPdf =>
      _ext == 'pdf' ||
      (widget.file.fileType?.toLowerCase().contains('pdf') ?? false);

  bool get _isImage =>
      const {'jpg', 'jpeg', 'png', 'heic', 'webp', 'gif'}.contains(_ext);

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final client = ref.read(supabaseClientProvider);
    try {
      if (_isImage) {
        final url = await client.storage
            .from('medical-files')
            .createSignedUrl(widget.file.storagePath, 3600);
        if (!mounted) return;
        setState(() {
          _imageUrl = url;
          _loading = false;
        });
      } else if (_isPdf) {
        final cacheDir = await getTemporaryDirectory();
        final localFile = File(
          '${cacheDir.path}/file_${widget.file.id}.pdf',
        );
        if (!await localFile.exists()) {
          final url = await client.storage
              .from('medical-files')
              .createSignedUrl(widget.file.storagePath, 3600);
          await Dio().download(url, localFile.path);
        }
        if (!mounted) return;
        setState(() {
          _pdfPath = localFile.path;
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  Widget _placeholder({Widget? overlay}) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: Icon(
            widget.placeholderIcon,
            size: 42,
            color: widget.placeholderColor.withValues(alpha: 0.75),
          ),
        ),
        if (overlay != null) Center(child: overlay),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return _placeholder(
        overlay: const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 1.6,
            color: Color(0xFF6B7C8C),
          ),
        ),
      );
    }
    if (_failed) return _placeholder();

    if (_imageUrl != null) {
      return CachedNetworkImage(
        imageUrl: _imageUrl!,
        fit: BoxFit.cover,
        placeholder: (_, _) => _placeholder(),
        errorWidget: (_, _, _) => _placeholder(),
      );
    }
    if (_pdfPath != null) {
      // Render page 1 as a static thumbnail (no interaction). Unique key
      // per file path so Flutter's platform-view registry doesn't reuse
      // the same UIKitView id across multiple cards/scrolling.
      return IgnorePointer(
        child: PDFView(
          key: ValueKey('pdfview-grid-${widget.file.id}'),
          filePath: _pdfPath!,
          enableSwipe: false,
          swipeHorizontal: false,
          autoSpacing: false,
          pageFling: false,
          fitPolicy: FitPolicy.WIDTH,
        ),
      );
    }
    return _placeholder();
  }
}

// ── Scan status pill ───────────────────────────────────────────────────────────

class _ScanStatusPill extends StatelessWidget {
  final String status; // 'pending' | 'done' | 'failed'
  final VoidCallback? onRetry;
  const _ScanStatusPill({required this.status, this.onRetry});

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case 'done':
        return _StaticBadge(
          color: const Color(0xFF0D9488),
          icon: Icons.check_rounded,
          label: 'Ready',
        );
      case 'failed':
        return _FailedBadge(onRetry: onRetry);
      default:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(
                strokeWidth: 1.4,
                color: Color(0xFF0D9488),
              ),
            ),
            SizedBox(width: 6),
            Text(
              'Saving securely',
              style: TextStyle(
                color: Color(0xFF0D9488),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            _AnimatedDots(),
          ],
        );
    }
  }
}

class _StaticBadge extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String label;
  const _StaticBadge({
    required this.color,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 12),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _FailedBadge extends StatelessWidget {
  final VoidCallback? onRetry;
  const _FailedBadge({this.onRetry});

  @override
  Widget build(BuildContext context) {
    const red = Color(0xFFD64B4B);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onRetry,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: red.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: red.withValues(alpha: 0.25)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: red, size: 12),
              const SizedBox(width: 4),
              const Text(
                'Failed',
                style: TextStyle(
                  color: red,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (onRetry != null) ...[
                const SizedBox(width: 8),
                Container(
                  width: 1,
                  height: 10,
                  color: red.withValues(alpha: 0.35),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.refresh_rounded, color: red, size: 12),
                const SizedBox(width: 3),
                const Text(
                  'Retry',
                  style: TextStyle(
                    color: red,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AnimatedDots extends StatefulWidget {
  const _AnimatedDots();

  @override
  State<_AnimatedDots> createState() => _AnimatedDotsState();
}

class _AnimatedDotsState extends State<_AnimatedDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) {
        final t = _ctrl.value;
        final n = (t * 3).floor() + 1; // 1, 2, or 3
        return Text(
          '.' * n,
          style: const TextStyle(
            color: Color(0xFF0D9488),
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        );
      },
    );
  }
}

// ── Upload-preview dialog (preview + notes + AI revise) ──────────────────────

class UploadConfirm {
  final String notes;
  final String folderId;
  const UploadConfirm({required this.notes, required this.folderId});
}

class UploadPreviewDialog extends ConsumerStatefulWidget {
  final FileUploadDraft draft;
  final Folder folder;

  const UploadPreviewDialog({
    super.key,
    required this.draft,
    required this.folder,
  });

  @override
  ConsumerState<UploadPreviewDialog> createState() =>
      UploadPreviewDialogState();
}

class UploadPreviewDialogState extends ConsumerState<UploadPreviewDialog> {
  final _notesCtrl = TextEditingController();
  bool _revising = false;
  String? _reviseError;
  late Folder _destination;

  @override
  void initState() {
    super.initState();
    _destination = widget.folder;
    _notesCtrl.addListener(() => setState(() {}));
  }

  Future<void> _pickFolder() async {
    final folders = ref.read(foldersProvider(null)).value ?? const <Folder>[];
    if (folders.isEmpty) return;
    final picked = await showModalBottomSheet<Folder>(
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
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Save to folder',
                  style: TextStyle(
                    color: AppTheme.primaryDark,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: folders.length,
                itemBuilder: (_, i) {
                  final f = folders[i];
                  final selected = f.id == _destination.id;
                  return ListTile(
                    leading: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: _kFolderColors[i % _kFolderColors.length],
                        shape: BoxShape.circle,
                      ),
                    ),
                    title: Text(f.name),
                    trailing: selected
                        ? const Icon(
                            Icons.check_rounded,
                            color: AppTheme.primaryDark,
                          )
                        : null,
                    onTap: () => Navigator.pop(ctx, f),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked != null && mounted) {
      setState(() => _destination = picked);
    }
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

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
        context:
            'File: ${widget.draft.displayName} in folder ${_destination.name}',
      );
      _notesCtrl.text = revised;
      _notesCtrl.selection = TextSelection.collapsed(offset: revised.length);
    } catch (e) {
      final msg = e is Exception
          ? e.toString().replaceFirst('Exception: ', '')
          : '$e';
      setState(() => _reviseError = msg);
    } finally {
      if (mounted) setState(() => _revising = false);
    }
  }

  void _save() {
    Navigator.of(context).pop(
      UploadConfirm(
        notes: _notesCtrl.text.trim(),
        folderId: _destination.id,
      ),
    );
  }

  String _sizeLabel() {
    final kb = widget.draft.sizeBytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(0)} KB';
    return '${(kb / 1024).toStringAsFixed(1)} MB';
  }

  Widget _buildPreview() {
    final draft = widget.draft;
    if (draft.isImage) {
      return Image.file(draft.file, fit: BoxFit.contain);
    }
    if (draft.isPdf) {
      return PDFView(
        key: ValueKey('pdfview-upload-${draft.file.path}'),
        filePath: draft.file.path,
        enableSwipe: true,
        swipeHorizontal: false,
        autoSpacing: false,
        pageFling: false,
        fitPolicy: FitPolicy.WIDTH,
      );
    }
    return const Center(
      child: Icon(
        Icons.insert_drive_file_outlined,
        size: 56,
        color: Color(0xFF6B7C8C),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 30,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(
                child: Text(
                  'Add to folder',
                  style: TextStyle(
                    color: AppTheme.primaryDark,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ── Preview ──────────────────────────────────────────
              Container(
                height: 240,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F4F8),
                  borderRadius: BorderRadius.circular(16),
                ),
                clipBehavior: Clip.antiAlias,
                child: _buildPreview(),
              ),
              const SizedBox(height: 10),

              // ── File meta line ──────────────────────────────────
              Row(
                children: [
                  Icon(
                    widget.draft.isPdf
                        ? Icons.picture_as_pdf_outlined
                        : widget.draft.isImage
                            ? Icons.image_outlined
                            : Icons.insert_drive_file_outlined,
                    size: 16,
                    color: const Color(0xFF4A5568),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      widget.draft.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.primaryDark,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    _sizeLabel(),
                    style: const TextStyle(
                      color: Color(0xFF4A5568),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // ── Destination folder ───────────────────────────────
              const Padding(
                padding: EdgeInsets.only(left: 4, bottom: 6),
                child: Text(
                  'Save to folder',
                  style: TextStyle(
                    color: Color(0xFF4A5568),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: _pickFolder,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F4F8),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.folder_outlined,
                          color: AppTheme.primaryDark,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _destination.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppTheme.primaryDark,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: Color(0xFF6B7C8C),
                          size: 18,
                        ),
                      ],
                    ),
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
                        'How did you feel? When, where, what symptoms.',
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
                    child: _DialogBtn(
                      label: 'Cancel',
                      onTap: () => Navigator.of(context).pop(),
                      filled: false,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _DialogBtn(
                      label: 'Upload',
                      onTap: _save,
                      filled: true,
                    ),
                  ),
                ],
              ),
            ],
          ),
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

class _DialogBtn extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool filled;
  const _DialogBtn({
    required this.label,
    required this.onTap,
    required this.filled,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: filled
                ? AppTheme.primaryDark
                : const Color(0xFFF1F4F8),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: filled ? Colors.white : AppTheme.primaryDark,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Add-document FAB ──────────────────────────────────────────────────────────

class _AddDocumentFab extends StatelessWidget {
  final UploadState uploadState;
  final VoidCallback onTap;

  const _AddDocumentFab({
    required this.uploadState,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final uploading = uploadState.isUploading;
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
          onTap: uploading ? null : onTap,
          child: SizedBox(
            width: 60,
            height: 60,
            child: Center(
              child: uploading
                  ? SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                        value: uploadState.progress < 0
                            ? null
                            : uploadState.progress,
                      ),
                    )
                  : const Icon(
                      Icons.note_add_outlined,
                      size: 26,
                      color: Colors.white,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
