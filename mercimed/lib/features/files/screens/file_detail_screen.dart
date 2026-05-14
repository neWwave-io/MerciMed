import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';

import '../../../features/auth/providers/auth_provider.dart';
import '../../../shared/models/file_model.dart';
import '../../../shared/theme/app_theme.dart';
import '../providers/files_provider.dart';

class FileDetailScreen extends ConsumerStatefulWidget {
  final String fileId;
  const FileDetailScreen({required this.fileId, super.key});

  @override
  ConsumerState<FileDetailScreen> createState() => _FileDetailScreenState();
}

class _FileDetailScreenState extends ConsumerState<FileDetailScreen> {
  final _notesCtrl = TextEditingController();
  Timer? _debounce;
  String _lastSaved = '';
  bool _seededNotes = false;

  @override
  void dispose() {
    _debounce?.cancel();
    final pending = _notesCtrl.text;
    if (pending != _lastSaved) {
      // Best-effort save on close.
      final client = ref.read(supabaseClientProvider);
      updateFileNotes(client, widget.fileId, pending).catchError((_) {});
    }
    _notesCtrl.dispose();
    super.dispose();
  }

  void _onNotesChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), () async {
      if (v == _lastSaved) return;
      try {
        await updateFileNotes(
          ref.read(supabaseClientProvider),
          widget.fileId,
          v,
        );
        _lastSaved = v;
      } catch (_) {
        // Soft-fail; next keystroke retries.
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final fileAsync = ref.watch(fileByIdProvider(widget.fileId));

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: fileAsync.when(
          data: (file) {
            if (file == null) return _NotFound();
            if (!_seededNotes) {
              _seededNotes = true;
              _notesCtrl.text = file.notes ?? '';
              _lastSaved = _notesCtrl.text;
            }
            return _DetailBody(
              file: file,
              notesCtrl: _notesCtrl,
              onNotesChanged: _onNotesChanged,
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => _NotFound(),
        ),
      ),
    );
  }
}

class _NotFound extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'File not found.',
            style: TextStyle(color: AppTheme.muted),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => context.go('/home'),
            child: const Text('Back to home'),
          ),
        ],
      ),
    );
  }
}

class _DetailBody extends ConsumerWidget {
  final FileModel file;
  final TextEditingController notesCtrl;
  final ValueChanged<String> onNotesChanged;

  const _DetailBody({
    required this.file,
    required this.notesCtrl,
    required this.onNotesChanged,
  });

  bool get _isPdf =>
      (file.fileType ?? '').toLowerCase().contains('pdf') ||
      file.fileName.toLowerCase().endsWith('.pdf');

  bool get _isImage {
    final t = (file.fileType ?? '').toLowerCase();
    if (t.startsWith('image/')) return true;
    final n = file.fileName.toLowerCase();
    return const ['.jpg', '.jpeg', '.png', '.heic', '.webp', '.gif']
        .any(n.endsWith);
  }

  Future<String> _signedUrl(WidgetRef ref) async {
    final client = ref.read(supabaseClientProvider);
    return client.storage
        .from('medical-files')
        .createSignedUrl(file.storagePath, 60 * 30); // 30 min
  }

  String _formatDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        // ── Top bar ───────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 16, 8),
          child: Row(
            children: [
              IconButton(
                onPressed: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/home');
                  }
                },
                icon: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  size: 18,
                  color: AppTheme.primaryDark,
                ),
              ),
              Expanded(
                child: Text(
                  file.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.primaryDark,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                onPressed: () {},
                icon: const Icon(
                  Icons.ios_share_rounded,
                  size: 20,
                  color: AppTheme.primaryDark,
                ),
              ),
            ],
          ),
        ),

        // ── Viewer ───────────────────────────────────────────────
        Expanded(
          child: FutureBuilder<String>(
            future: _signedUrl(ref),
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError || snap.data == null) {
                return const Center(
                  child: Text(
                    'Could not load file.',
                    style: TextStyle(color: AppTheme.muted),
                  ),
                );
              }
              if (_isPdf) {
                return _PdfViewer(url: snap.data!);
              }
              if (_isImage) {
                return InteractiveViewer(
                  child: Center(
                    child: CachedNetworkImage(
                      imageUrl: snap.data!,
                      fit: BoxFit.contain,
                      placeholder: (_, _) => const Center(
                        child: CircularProgressIndicator(),
                      ),
                      errorWidget: (_, _, _) => const Center(
                        child: Icon(Icons.broken_image_outlined,
                            color: AppTheme.muted),
                      ),
                    ),
                  ),
                );
              }
              return const Center(
                child: Text(
                  'Preview not supported for this file.',
                  style: TextStyle(color: AppTheme.muted),
                ),
              );
            },
          ),
        ),

        // ── Notes ────────────────────────────────────────────────
        _NotesCard(
          controller: notesCtrl,
          onChanged: onNotesChanged,
          createdAt: _formatDate(file.createdAt),
          status: file.aiScanStatus,
        ),
      ],
    );
  }
}

class _PdfViewer extends StatefulWidget {
  final String url;
  const _PdfViewer({required this.url});

  @override
  State<_PdfViewer> createState() => _PdfViewerState();
}

class _PdfViewerState extends State<_PdfViewer> {
  String? _path;
  String? _error;

  @override
  void initState() {
    super.initState();
    _download();
  }

  Future<void> _download() async {
    try {
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/preview_${DateTime.now().microsecondsSinceEpoch}.pdf',
      );
      final client = HttpClient();
      final req = await client.getUrl(Uri.parse(widget.url));
      final res = await req.close();
      final sink = file.openWrite();
      await res.pipe(sink);
      await sink.close();
      if (!mounted) return;
      setState(() => _path = file.path);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return const Center(
        child: Text('PDF preview failed.',
            style: TextStyle(color: AppTheme.muted)),
      );
    }
    if (_path == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return PDFView(
      filePath: _path!,
      enableSwipe: true,
      swipeHorizontal: false,
      autoSpacing: true,
      pageFling: true,
      pageSnap: true,
    );
  }
}

class _NotesCard extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String createdAt;
  final String status;

  const _NotesCard({
    required this.controller,
    required this.onChanged,
    required this.createdAt,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Container(
      margin: EdgeInsets.fromLTRB(16, 12, 16, bottom + 16),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Text(
                'NOTES',
                style: TextStyle(
                  color: Color(0xFF4A5568),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                ),
              ),
              const Spacer(),
              Text(
                'Added $createdAt',
                style: const TextStyle(
                  color: Color(0xFF6B7C8C),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            onChanged: onChanged,
            minLines: 2,
            maxLines: 5,
            style: const TextStyle(
              color: AppTheme.primaryDark,
              fontSize: 14,
              height: 1.4,
            ),
            decoration: const InputDecoration(
              hintText: 'Add a personal note about this record…',
              hintStyle: TextStyle(
                color: Color(0xFF6B7C8C),
                fontSize: 14,
              ),
              isCollapsed: true,
              contentPadding: EdgeInsets.symmetric(vertical: 6),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
          ),
        ],
      ),
    );
  }
}
