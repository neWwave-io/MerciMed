import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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

class FolderScreen extends ConsumerStatefulWidget {
  final String folderId;

  const FolderScreen({required this.folderId, super.key});

  @override
  ConsumerState<FolderScreen> createState() => _FolderScreenState();
}

class _FolderScreenState extends ConsumerState<FolderScreen> {
  _DocFilter _filter = _DocFilter.all;

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

  bool _matchesFilter(FileModel f) {
    if (_filter == _DocFilter.all) return true;
    final ext = _ext(f.fileName);
    if (_filter == _DocFilter.pdf) return ext == 'pdf';
    if (_filter == _DocFilter.image) {
      return const {'jpg', 'jpeg', 'png', 'heic', 'webp', 'gif'}.contains(ext);
    }
    return true;
  }

  static String _ext(String name) {
    final i = name.lastIndexOf('.');
    if (i < 0 || i == name.length - 1) return '';
    return name.substring(i + 1).toLowerCase();
  }

  @override
  Widget build(BuildContext context) {
    final foldersAsync = ref.watch(foldersProvider(null));
    final filesAsync   = ref.watch(filesProvider(widget.folderId));

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: foldersAsync.when(
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
    );
  }

  Widget _buildContent(Folder folder, Color color, List<FileModel> files) {
    final filtered = files.where(_matchesFilter).toList();
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
      child: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.only(bottom: 160),
            children: [
              // ── Top bar ─────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 12, 4),
                child: Row(
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
                      onPressed: () {},
                      icon: const Icon(
                        Icons.search_rounded,
                        size: 22,
                        color: AppTheme.primaryDark,
                      ),
                    ),
                    IconButton(
                      onPressed: () {},
                      icon: const Icon(
                        Icons.more_horiz_rounded,
                        size: 22,
                        color: AppTheme.primaryDark,
                      ),
                    ),
                  ],
                ),
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
                    const SizedBox(width: 10),
                    _FilterChip(
                      label: 'PDF • $pdfCount',
                      selected: _filter == _DocFilter.pdf,
                      onTap: () => setState(() => _filter = _DocFilter.pdf),
                    ),
                    const SizedBox(width: 10),
                    _FilterChip(
                      label: 'Images • $imgCount',
                      selected: _filter == _DocFilter.image,
                      onTap: () => setState(() => _filter = _DocFilter.image),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ── Document list ──────────────────────────────────────
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
              else
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      for (var i = 0; i < filtered.length; i++) ...[
                        _DocumentItem(
                          file: filtered[i],
                          onTap: () =>
                              context.push('/file/${filtered[i].id}'),
                        ),
                        if (i < filtered.length - 1)
                          const SizedBox(height: 12),
                      ],
                    ],
                  ),
                ),
            ],
          ),

          // ── Floating "Add to …" button ───────────────────────────
          Positioned(
            left: 0,
            right: 0,
            bottom: 24,
            child: Center(
              child: _AddDocumentButton(
                folderName: folder.name,
                onTap: () {
                  // Hook into upload flow.
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Upload to ${folder.name} — coming next'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
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

// ── Document row ───────────────────────────────────────────────────────────────

class _DocumentItem extends StatelessWidget {
  final FileModel file;
  final VoidCallback onTap;

  const _DocumentItem({required this.file, required this.onTap});

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

  bool get _isUploading =>
      file.aiScanStatus == 'pending' || file.aiScanStatus == 'processing';

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
                  if (_isUploading) ...[
                    const SizedBox(height: 6),
                    Row(
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
                          'Scanning…',
                          style: TextStyle(
                            color: Color(0xFF0D9488),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
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

// ── Bottom "Add to {folder}" button ────────────────────────────────────────────

class _AddDocumentButton extends StatelessWidget {
  final String folderName;
  final VoidCallback onTap;

  const _AddDocumentButton({required this.folderName, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF1A212B),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF1A212B).withValues(alpha: 0.28),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.add_rounded,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Add to $folderName',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
