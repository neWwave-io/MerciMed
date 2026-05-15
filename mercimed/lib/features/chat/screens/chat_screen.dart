import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../../features/auth/providers/auth_provider.dart';
import '../../../features/files/providers/files_provider.dart';
import '../../../shared/models/chat_message.dart';
import '../../../shared/models/conversation.dart';
import '../../../shared/models/file_model.dart';
import '../../../shared/theme/app_theme.dart';
import '../providers/chat_provider.dart';

Future<void> _openConversationsSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const _ConversationsSheet(),
  );
}

class _ConversationsSheet extends ConsumerWidget {
  const _ConversationsSheet();

  String _relative(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${(diff.inDays / 7).floor()}w ago';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final convs = ref.watch(conversationsStreamProvider).value ?? const <Conversation>[];
    final activeId = ref.watch(effectiveConversationIdProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.35,
      maxChildSize: 0.9,
      builder: (_, scrollCtrl) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.85),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.7),
                width: 1,
              ),
            ),
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFCBD5E0),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 16, 8),
                  child: Row(
                    children: [
                      const Text(
                        'Conversations',
                        style: TextStyle(
                          color: AppTheme.primaryDark,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () async {
                          await ref
                              .read(chatProvider.notifier)
                              .startNewConversation();
                          if (context.mounted) Navigator.pop(context);
                        },
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('New'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: convs.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(32),
                            child: Text(
                              'No conversations yet — tap "New" to start one.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Color(0xFF6B7C8C),
                                fontSize: 14,
                              ),
                            ),
                          ),
                        )
                      : ListView.separated(
                          controller: scrollCtrl,
                          padding:
                              const EdgeInsets.fromLTRB(20, 4, 20, 24),
                          itemCount: convs.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 8),
                          itemBuilder: (_, i) {
                            final c = convs[i];
                            final isActive = c.id == activeId;
                            return Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: () {
                                  ref.read(chatProvider.notifier).switchTo(c.id);
                                  Navigator.pop(context);
                                },
                                child: Container(
                                  padding: const EdgeInsets.fromLTRB(
                                    14,
                                    12,
                                    8,
                                    12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isActive
                                        ? AppTheme.primaryDark
                                            .withValues(alpha: 0.08)
                                        : Colors.white
                                            .withValues(alpha: 0.7),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: isActive
                                          ? AppTheme.primaryDark
                                              .withValues(alpha: 0.25)
                                          : Colors.white
                                              .withValues(alpha: 0.9),
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        isActive
                                            ? Icons.chat_bubble_rounded
                                            : Icons.chat_bubble_outline_rounded,
                                        size: 18,
                                        color: AppTheme.primaryDark,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              (c.title?.trim().isNotEmpty ??
                                                      false)
                                                  ? c.title!
                                                  : 'New chat',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: AppTheme.primaryDark,
                                                fontSize: 14,
                                                fontWeight: FontWeight.w700,
                                                letterSpacing: -0.2,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              _relative(c.updatedAt),
                                              style: const TextStyle(
                                                color: Color(0xFF6B7C8C),
                                                fontSize: 11,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Delete',
                                        onPressed: () async {
                                          final ok = await showDialog<bool>(
                                            context: context,
                                            barrierColor: Colors.black
                                                .withValues(alpha: 0.4),
                                            builder: (dctx) => AlertDialog(
                                              title: const Text(
                                                'Delete conversation?',
                                              ),
                                              content: const Text(
                                                'This removes every message in this chat. Your files are kept.',
                                              ),
                                              actions: [
                                                TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(dctx, false),
                                                  child: const Text('Cancel'),
                                                ),
                                                TextButton(
                                                  style: TextButton.styleFrom(
                                                    foregroundColor: const Color(
                                                      0xFFD64B4B,
                                                    ),
                                                  ),
                                                  onPressed: () =>
                                                      Navigator.pop(dctx, true),
                                                  child: const Text('Delete'),
                                                ),
                                              ],
                                            ),
                                          );
                                          if (ok == true) {
                                            // If deleting the active one, also clear
                                            // active so a fresh one is picked.
                                            if (isActive) {
                                              await ref
                                                  .read(chatProvider.notifier)
                                                  .deleteActiveConversation();
                                            } else {
                                              await ref
                                                  .read(supabaseClientProvider)
                                                  .from('conversations')
                                                  .delete()
                                                  .eq('id', c.id);
                                            }
                                          }
                                        },
                                        icon: const Icon(
                                          Icons.delete_outline_rounded,
                                          color: Color(0xFFD64B4B),
                                          size: 20,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
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

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _hasText = false;
  bool _listening = false;
  String _speechBase = ''; // text already in the field before recording
  // Files the user has uploaded in this session that haven't been sent in a
  // message yet — rendered as chips above the input bar.
  List<FileModel> _pendingAttachments = const [];

  void _removeAttachment(FileModel f) {
    setState(() {
      _pendingAttachments =
          _pendingAttachments.where((x) => x.id != f.id).toList();
    });
  }

  /// Builds the actual content string sent to the chat function. Embeds
  /// `[[file:NAME]]` markers for any pending attachments so the AI sees them
  /// AND the bubble's _refsIn picks up the file name. The markers are
  /// stripped from on-screen display by [stripMarkdown].
  String _buildOutgoingMessage(String typed, List<FileModel> atts) {
    if (atts.isEmpty) return typed;
    final prefix = atts.map((f) => '[[file:${f.fileName}]]').join(' ');
    if (typed.isEmpty) return prefix;
    return '$prefix\n\n$typed';
  }

  @override
  void initState() {
    super.initState();
    _inputCtrl.addListener(() {
      final next = _inputCtrl.text.trim().isNotEmpty;
      if (next != _hasText) setState(() => _hasText = next);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
  }

  Future<void> _toggleVoice() async {
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    final available = await _speech.initialize(
      onStatus: (status) {
        if (!mounted) return;
        if (status == 'done' || status == 'notListening') {
          setState(() => _listening = false);
        }
      },
      onError: (_) {
        if (mounted) setState(() => _listening = false);
      },
    );
    if (!available) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('Microphone or speech recognition not available.'),
      ));
      return;
    }
    _speechBase = _inputCtrl.text;
    setState(() => _listening = true);
    await _speech.listen(
      onResult: (result) {
        final transcript = result.recognizedWords;
        final joined = _speechBase.isEmpty
            ? transcript
            : '$_speechBase $transcript'.trim();
        _inputCtrl.value = TextEditingValue(
          text: joined,
          selection: TextSelection.collapsed(offset: joined.length),
        );
      },
      listenOptions: stt.SpeechListenOptions(
        listenMode: stt.ListenMode.dictation,
        partialResults: true,
        cancelOnError: true,
      ),
      pauseFor: const Duration(seconds: 3),
    );
  }

  void _scrollToEnd({bool animated = false}) {
    if (!_scrollCtrl.hasClients) return;
    final target = _scrollCtrl.position.maxScrollExtent;
    if (animated) {
      _scrollCtrl.animateTo(
        target,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
      );
    } else {
      _scrollCtrl.jumpTo(target);
    }
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  /// Chat-side file upload. Silent: no preview / notes / folder picker —
  /// users are sharing the file with Mercie, not filing a record. We still
  /// quietly create (or reuse) a chat folder per conversation and stash
  /// every chat upload in it, so the home screen's "Chat Folders" section
  /// keeps them tidy.
  Future<void> _pickAndUpload() async {
    final uploadNotifier = ref.read(uploadNotifierProvider.notifier);
    final folderNotifier = ref.read(folderNotifierProvider.notifier);
    final chatNotifier = ref.read(chatProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);

    // Pick first so the user can cancel before we touch any state.
    final draft = await uploadNotifier.pickFile();
    if (!mounted) return;
    if (draft == null) {
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

    // Background: ensure conversation + chat folder, then upload.
    var convId = ref.read(effectiveConversationIdProvider);
    convId ??= await chatNotifier.startNewConversation();
    if (convId == null) return;

    // Ask the AI to pick a meaningful folder name from the conversation +
    // the filename. Falls back to filename-without-extension, then to a
    // generic placeholder. We only do this if the conversation doesn't
    // already have a chat folder (otherwise we just reuse it).
    final history = (ref.read(chatMessagesStreamProvider).value ?? const [])
        .map((m) => {'role': m.role, 'content': m.content})
        .toList();
    final pending = _inputCtrl.text.trim();
    final suggested = await suggestChatFolderName(
      ref.read(supabaseClientProvider),
      fileName: draft.displayName,
      message: pending.isEmpty ? null : pending,
      history: history,
    );
    final fallbackName = _fileBaseName(draft.displayName);
    final folderName = (suggested != null && suggested.isNotEmpty)
        ? suggested
        : (fallbackName.isNotEmpty
            ? fallbackName
            : 'Chat — ${_shortDateTime(DateTime.now())}');

    final chatFolderId = await folderNotifier.ensureChatFolderForConversation(
      conversationId: convId,
      name: folderName,
    );
    if (chatFolderId == null) return;

    // Quick "uploading" cue while the file flies up.
    messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
      content: Text('Sharing ${draft.displayName} with Mercie…'),
    ));

    final id = await uploadNotifier.upload(
      folderId: chatFolderId,
      file: draft.file,
      displayName: draft.displayName,
    );

    if (!mounted) return;
    final err = ref.read(uploadNotifierProvider).errorMessage;
    if (id == null && err != null) {
      messenger.clearSnackBars();
      messenger.showSnackBar(SnackBar(
        backgroundColor: const Color(0xFFD64B4B),
        behavior: SnackBarBehavior.floating,
        content: Text(err, style: const TextStyle(color: Colors.white)),
      ));
      return;
    }
    if (id == null) return;
    // Find the newly inserted file in the live stream so we can show its
    // preview chip with the right id (waits a moment if the stream hasn't
    // refreshed yet).
    FileModel? newFile;
    for (var attempt = 0; attempt < 10; attempt++) {
      final files = ref.read(ownerFilesStreamProvider).value ?? const [];
      newFile = files.where((f) => f.id == id).cast<FileModel?>().firstWhere(
            (_) => true,
            orElse: () => null,
          );
      if (newFile != null) break;
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
    if (!mounted) return;
    if (newFile != null) {
      setState(() {
        _pendingAttachments = [..._pendingAttachments, newFile!];
      });
    } else {
      // Fall back to a synthetic FileModel from the draft so the chip still
      // renders even if the live stream is slow.
      setState(() {
        _pendingAttachments = [
          ..._pendingAttachments,
          FileModel(
            id: id,
            userId: '',
            folderId: chatFolderId,
            fileName: draft.displayName,
            fileType: draft.mimeType,
            storagePath: '',
            aiScanStatus: 'pending',
            createdAt: DateTime.now(),
          ),
        ];
      });
    }
  }

  String _fileBaseName(String displayName) {
    final dot = displayName.lastIndexOf('.');
    final base = dot > 0 ? displayName.substring(0, dot) : displayName;
    // Replace separators with spaces, title-case-ish.
    final cleaned = base
        .replaceAll(RegExp(r'[_\-]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return cleaned;
  }

  String _shortDateTime(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '${months[d.month - 1]} ${d.day} $h:$m';
  }

  Future<void> _send() async {
    final typed = _inputCtrl.text.trim();
    final atts = _pendingAttachments;
    if (typed.isEmpty && atts.isEmpty) return;

    final user = ref.read(supabaseClientProvider).auth.currentUser;
    final userId = user?.id ?? '';
    final persisted = ref.read(chatMessagesStreamProvider).value ?? const [];

    final outgoing = _buildOutgoingMessage(typed, atts);

    _inputCtrl.clear();
    setState(() => _pendingAttachments = const []);

    ref.read(chatProvider.notifier).sendMessage(
          userId: userId,
          message: outgoing,
          persistedHistory: persisted,
        );
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
  }

  @override
  Widget build(BuildContext context) {
    final live = ref.watch(chatProvider);
    final persistedAsync = ref.watch(chatMessagesStreamProvider);
    final persisted = persistedAsync.value ?? const <ChatMessage>[];
    final filesAsync = ref.watch(ownerFilesStreamProvider);
    final allFiles = filesAsync.value ?? const <FileModel>[];

    // Auto-scroll when either persisted history grows or a token arrives.
    ref.listen<ChatLive>(chatProvider, (_, _) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
    });
    ref.listen<AsyncValue<List<ChatMessage>>>(chatMessagesStreamProvider,
        (_, _) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
    });

    // Hide the optimistic bubble once its content lands in the persisted
    // stream (the edge function inserts it after [DONE]).
    final showOptimistic = live.optimisticUser != null &&
        !persisted.any((m) =>
            m.role == 'user' && m.content == live.optimisticUser!.content);

    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const _ChatHeader(),
            Expanded(
              child: _Messages(
                scrollCtrl: _scrollCtrl,
                messages: persisted,
                allFiles: allFiles,
                optimisticUser: showOptimistic ? live.optimisticUser : null,
                streamingBuffer: live.streamingBuffer,
                isStreaming: live.isStreaming,
                errorMessage: live.errorMessage,
              ),
            ),
            _ChatInputBar(
              controller: _inputCtrl,
              hasText: _hasText || _pendingAttachments.isNotEmpty,
              onSend: _send,
              onAddFile: _pickAndUpload,
              onMic: _toggleVoice,
              listening: _listening,
              disabled: live.isStreaming,
              attachments: _pendingAttachments,
              onRemoveAttachment: _removeAttachment,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Header ─────────────────────────────────────────────────────────────────────

class _ChatHeader extends ConsumerWidget {
  const _ChatHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 16, 12),
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
              size: 20,
              color: AppTheme.primaryDark,
            ),
          ),
          const SizedBox(width: 4),
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Center(
              child: Text(
                'm',
                style: TextStyle(
                  color: AppTheme.primaryDark,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Mercie',
                  style: TextStyle(
                    color: AppTheme.primaryDark,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    _Dot(color: Color(0xFF10B981)),
                    SizedBox(width: 6),
                    Text(
                      'reads only your records',
                      style: TextStyle(
                        color: Color(0xFF4A5568),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Conversation history',
            onPressed: () => _openConversationsSheet(context, ref),
            icon: const Icon(
              Icons.chat_bubble_outline_rounded,
              size: 22,
              color: AppTheme.primaryDark,
            ),
          ),
          IconButton(
            tooltip: 'Start a new conversation',
            onPressed: () async {
              await ref.read(chatProvider.notifier).startNewConversation();
            },
            icon: const Icon(
              Icons.add_circle_outline_rounded,
              size: 24,
              color: AppTheme.primaryDark,
            ),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  final Color color;
  const _Dot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

// ── Messages list ──────────────────────────────────────────────────────────────

class _Messages extends StatelessWidget {
  final ScrollController scrollCtrl;
  final List<ChatMessage> messages;
  final List<FileModel> allFiles;
  final ChatMessage? optimisticUser;
  final String streamingBuffer;
  final bool isStreaming;
  final String? errorMessage;

  const _Messages({
    required this.scrollCtrl,
    required this.messages,
    required this.allFiles,
    required this.optimisticUser,
    required this.streamingBuffer,
    required this.isStreaming,
    required this.errorMessage,
  });

  /// Files the AI (or the user) named in [text]. Pass 1 is exact substring,
  /// Pass 2 is fuzzy token matching for misspellings. De-duplicated by
  /// **filename** (not just id) so when the user has re-uploaded the same
  /// file across conversations, the chat shows a single card for it — we
  /// keep the most recent row per name.
  List<FileModel> _refsIn(String text) {
    if (text.isEmpty || allFiles.isEmpty) return const [];
    final lower = text.toLowerCase();

    // Newest-first across the whole library so the de-duped winner is the
    // most recent copy of a given filename.
    final pool = [...allFiles]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final out = <FileModel>[];
    final seenName = <String>{}; // lowercased filename

    bool tryAdd(FileModel f) {
      final n = f.fileName.toLowerCase();
      if (n.isEmpty || seenName.contains(n)) return false;
      out.add(f);
      seenName.add(n);
      return true;
    }

    // Pass 1: exact-substring match — strongest signal.
    for (final f in pool) {
      final name = f.fileName.toLowerCase();
      if (name.isEmpty || seenName.contains(name)) continue;
      if (lower.contains(name)) tryAdd(f);
    }

    // Pass 2: token-overlap fallback.
    for (final f in pool) {
      if (seenName.contains(f.fileName.toLowerCase())) continue;
      final base = f.fileName.toLowerCase();
      final tokens = base
          .replaceAll(RegExp(r'\.(pdf|jpe?g|png|heic|webp|gif)$'), '')
          .split(RegExp(r'[\s_\-.]+'))
          .where((t) => t.length >= 3 &&
              !const {'report', 'scan', 'file', 'doc', 'image'}.contains(t))
          .toList();
      if (tokens.isEmpty) continue;
      final hits = tokens.where((t) => lower.contains(t)).length;
      if (hits >= (tokens.length / 2).ceil() && hits >= 1) tryAdd(f);
    }
    return out;
  }

  String get _todayLabel => 'TODAY';

  @override
  Widget build(BuildContext context) {
    final hasReal = messages.isNotEmpty || optimisticUser != null;
    final showLiveBubble = isStreaming || streamingBuffer.isNotEmpty;

    return ListView(
      controller: scrollCtrl,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      children: [
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              _todayLabel,
              style: TextStyle(
                color: AppTheme.primaryDark.withValues(alpha: 0.45),
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.6,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (!hasReal && !showLiveBubble && errorMessage == null)
          _ChatBubble(
            text:
                'Good morning. I read only your medical records — ask me anything.',
            isSent: false,
            time: _shortTime(DateTime.now()),
          ),
        for (var i = 0; i < messages.length; i++) ...[
          if (i > 0) const SizedBox(height: 16),
          _ChatBubble(
            text: messages[i].content,
            isSent: messages[i].role == 'user',
            time: _shortTime(messages[i].createdAt),
          ),
          // Render file preview cards under any bubble that names a file.
          // For an assistant bubble, drop any file already shown under the
          // immediately preceding user bubble — otherwise the same upload
          // renders twice (once for the user's attachment, once because
          // the AI repeated the filename in its reply).
          Builder(builder: (_) {
            final refs = _refsIn(messages[i].content);
            if (refs.isEmpty) return const SizedBox.shrink();
            var visible = refs;
            if (messages[i].role != 'user' &&
                i > 0 &&
                messages[i - 1].role == 'user') {
              final prev = _refsIn(messages[i - 1].content)
                  .map((f) => f.fileName.toLowerCase())
                  .toSet();
              visible = refs
                  .where((f) => !prev.contains(f.fileName.toLowerCase()))
                  .toList();
              if (visible.isEmpty) return const SizedBox.shrink();
            }
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _FileRefsRow(
                files: visible,
                alignRight: messages[i].role == 'user',
              ),
            );
          }),
        ],
        if (optimisticUser != null) ...[
          const SizedBox(height: 16),
          _ChatBubble(
            text: optimisticUser!.content,
            isSent: true,
            time: _shortTime(optimisticUser!.createdAt),
          ),
          Builder(builder: (_) {
            final refs = _refsIn(optimisticUser!.content);
            if (refs.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _FileRefsRow(files: refs, alignRight: true),
            );
          }),
        ],
        if (showLiveBubble) ...[
          const SizedBox(height: 16),
          if (streamingBuffer.isNotEmpty) ...[
            _ChatBubble(
              text: streamingBuffer,
              isSent: false,
              time: _shortTime(DateTime.now()),
            ),
            Builder(builder: (_) {
              final refs = _refsIn(streamingBuffer);
              if (refs.isEmpty) return const SizedBox.shrink();
              // Drop any file the user just attached on the previous turn.
              final prevSource = optimisticUser ??
                  (messages.isNotEmpty && messages.last.role == 'user'
                      ? messages.last
                      : null);
              if (prevSource != null) {
                final prev = _refsIn(prevSource.content)
                    .map((f) => f.fileName.toLowerCase())
                    .toSet();
                final visible = refs
                    .where((f) => !prev.contains(f.fileName.toLowerCase()))
                    .toList();
                if (visible.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _FileRefsRow(files: visible),
                );
              }
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _FileRefsRow(files: refs),
              );
            }),
          ] else
            const _TypingDotsBubble(),
        ],
        if (errorMessage != null) ...[
          const SizedBox(height: 16),
          _SystemErrorBubble(message: errorMessage!),
        ],
      ],
    );
  }

  static String _shortTime(DateTime dt) {
    final h = dt.hour;
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class _TypingDotsBubble extends StatefulWidget {
  const _TypingDotsBubble();

  @override
  State<_TypingDotsBubble> createState() => _TypingDotsBubbleState();
}

class _TypingDotsBubbleState extends State<_TypingDotsBubble>
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
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.9),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
            bottomLeft: Radius.circular(6),
            bottomRight: Radius.circular(20),
          ),
        ),
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (_, _) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) {
                final t = ((_ctrl.value + i * 0.18) % 1.0);
                final scale = 0.6 + 0.4 * (t < 0.5 ? t * 2 : (1 - t) * 2);
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryDark.withValues(alpha: 0.55),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                );
              }),
            );
          },
        ),
      ),
    );
  }
}

class _SystemErrorBubble extends StatelessWidget {
  final String message;
  const _SystemErrorBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFFDECEC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: const Color(0xFFD64B4B).withValues(alpha: 0.35),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: Color(0xFFD64B4B),
              size: 16,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                message,
                style: const TextStyle(
                  color: Color(0xFF8A2C2C),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Chat bubble ────────────────────────────────────────────────────────────────

/// Strips the small set of markdown markers the model sometimes emits so they
/// don't render as literal asterisks/underscores. We deliberately don't pull
/// in flutter_markdown — keeping bubbles as plain Text widgets is faster and
/// the AI is instructed not to use markdown in the first place.
String stripMarkdown(String s) {
  if (s.isEmpty) return s;
  String unwrap(String input, RegExp pattern) =>
      input.replaceAllMapped(pattern, (m) => m.group(1) ?? '');

  var out = s;
  // Bold / italic markers (back-references via replaceAllMapped — Dart's
  // replaceAll treats `$1` as a literal string).
  out = unwrap(out, RegExp(r'\*\*(.*?)\*\*'));
  out = unwrap(out, RegExp(r'__(.*?)__'));
  out = unwrap(out, RegExp(r'(?<!\*)\*(?!\*)([^*\n]+?)\*(?!\*)'));
  out = unwrap(out, RegExp(r'(?<!_)_(?!_)([^_\n]+?)_(?!_)'));
  // Inline code
  out = unwrap(out, RegExp(r'`([^`\n]+?)`'));
  // Strikethrough
  out = unwrap(out, RegExp(r'~~(.*?)~~'));
  // Headings / blockquote markers at line start
  out = out.replaceAll(RegExp(r'^\s{0,3}#{1,6}\s+', multiLine: true), '');
  out = out.replaceAll(RegExp(r'^\s{0,3}>\s+', multiLine: true), '');
  // Bullets / numbered lists prefix
  out = out.replaceAll(RegExp(r'^\s{0,3}[-*+]\s+', multiLine: true), '• ');
  // Internal attachment markers ([[file:Name.pdf]]). Stripped from display
  // but stay in the raw text so _refsIn can find the filename to render a
  // file card under the bubble.
  out = out.replaceAll(RegExp(r'\[\[file:[^\]]+\]\]'), '').trim();
  // Collapse the blank line that's left when the marker block sat alone.
  out = out.replaceAll(RegExp(r'^\s*\n+'), '');
  return out;
}

class _ChatBubble extends StatelessWidget {
  final String text;
  final bool isSent;
  final String time;

  const _ChatBubble({
    required this.text,
    required this.isSent,
    required this.time,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isSent ? const Color(0xFF1A212B) : Colors.white.withValues(alpha: 0.9);
    final fg = isSent ? Colors.white : AppTheme.primaryDark;
    final subtle = isSent
        ? Colors.white.withValues(alpha: 0.55)
        : AppTheme.primaryDark.withValues(alpha: 0.5);

    return Align(
      alignment: isSent ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.82,
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(isSent ? 20 : 6),
            bottomRight: Radius.circular(isSent ? 6 : 20),
          ),
          boxShadow: isSent
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 14,
                    offset: const Offset(0, 3),
                  ),
                ],
        ),
        child: Column(
          crossAxisAlignment:
              isSent ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              stripMarkdown(text),
              style: TextStyle(
                color: fg,
                fontSize: 15,
                height: 1.45,
                fontWeight: FontWeight.w400,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              time,
              style: TextStyle(
                color: subtle,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── File reference card (rendered under AI bubbles that mention a file) ─────

class _FileReferenceCard extends ConsumerStatefulWidget {
  final FileModel file;
  const _FileReferenceCard({required this.file});

  @override
  ConsumerState<_FileReferenceCard> createState() => _FileReferenceCardState();
}

class _FileReferenceCardState extends ConsumerState<_FileReferenceCard> {
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

  Color get _accent {
    if (_isPdf) return const Color(0xFFD64B4B);
    if (_isImage) return const Color(0xFF5A9A94);
    return const Color(0xFF6B7C8C);
  }

  IconData get _icon {
    if (_isPdf) return Icons.picture_as_pdf_outlined;
    if (_isImage) return Icons.image_outlined;
    return Icons.insert_drive_file_outlined;
  }

  String _shortDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[d.month - 1]} ${d.day.toString().padLeft(2, '0')}, ${d.year}';
  }

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
        final dir = await getTemporaryDirectory();
        final local = File('${dir.path}/file_${widget.file.id}.pdf');
        if (!await local.exists()) {
          final url = await client.storage
              .from('medical-files')
              .createSignedUrl(widget.file.storagePath, 3600);
          await Dio().download(url, local.path);
        }
        if (!mounted) return;
        setState(() {
          _pdfPath = local.path;
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

  Widget _preview() {
    if (_loading) {
      return Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 1.8,
            color: _accent.withValues(alpha: 0.6),
          ),
        ),
      );
    }
    if (_failed) {
      return Center(
        child: Icon(_icon, size: 48, color: _accent.withValues(alpha: 0.7)),
      );
    }
    if (_imageUrl != null) {
      return CachedNetworkImage(
        imageUrl: _imageUrl!,
        fit: BoxFit.cover,
        placeholder: (_, _) => Center(
          child: Icon(_icon, size: 42, color: _accent.withValues(alpha: 0.55)),
        ),
        errorWidget: (_, _, _) => Center(
          child: Icon(_icon, size: 42, color: _accent.withValues(alpha: 0.55)),
        ),
      );
    }
    if (_pdfPath != null) {
      // Unique key per file id so platform-view IDs don't collide when
      // multiple reference cards (or scrolled cards) render PDFView.
      return IgnorePointer(
        child: PDFView(
          key: ValueKey('pdfview-chat-${widget.file.id}'),
          filePath: _pdfPath!,
          enableSwipe: false,
          swipeHorizontal: false,
          autoSpacing: false,
          pageFling: false,
          fitPolicy: FitPolicy.WIDTH,
        ),
      );
    }
    return Center(
      child: Icon(_icon, size: 48, color: _accent.withValues(alpha: 0.7)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => context.push('/file/${widget.file.id}'),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.7),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ── Preview area (square) ──────────────────
                      AspectRatio(
                        aspectRatio: 1,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            // Tinted backdrop behind the preview so the glass
                            // tone bleeds in around the edges of the PDF/image.
                            Container(color: _accent.withValues(alpha: 0.08)),
                            ClipRRect(
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(19),
                                topRight: Radius.circular(19),
                              ),
                              child: _preview(),
                            ),
                            // Type chip overlay
                            Positioned(
                              top: 8,
                              left: 8,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: BackdropFilter(
                                  filter: ImageFilter.blur(
                                    sigmaX: 6,
                                    sigmaY: 6,
                                  ),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 7,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _accent.withValues(alpha: 0.85),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      _isPdf
                                          ? 'PDF'
                                          : _isImage
                                              ? 'IMG'
                                              : 'FILE',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.6,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // ── Footer (name + date + Open) ────────────
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.file.fileName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: AppTheme.primaryDark,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: -0.2,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _shortDate(widget.file.createdAt),
                                    style: const TextStyle(
                                      color: Color(0xFF6B7C8C),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                            _OpenPill(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
  }
}

// ── Horizontal row of refs + see-all sheet ───────────────────────────────────

class _FileRefsRow extends StatelessWidget {
  final List<FileModel> files;
  final bool alignRight;
  const _FileRefsRow({required this.files, this.alignRight = false});

  static const int _inlineMax = 3;

  Future<void> _openAll(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _AllFilesSheet(files: files),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = files.length <= _inlineMax
        ? files
        : files.take(_inlineMax).toList();
    final remaining = files.length - visible.length;
    final cross =
        alignRight ? CrossAxisAlignment.end : CrossAxisAlignment.start;

    return Column(
      crossAxisAlignment: cross,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 280,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            // Align trailing cards to the right edge by reversing when in
            // alignRight mode (start of the list shows on the right).
            reverse: alignRight,
            padding: EdgeInsets.zero,
            itemCount: visible.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              final idx = alignRight ? visible.length - 1 - i : i;
              return _FileReferenceCard(file: visible[idx]);
            },
          ),
        ),
        if (remaining > 0) ...[
          const SizedBox(height: 8),
          _SeeAllPill(
            label: 'See all ${files.length} files',
            onTap: () => _openAll(context),
          ),
        ],
      ],
    );
  }
}

class _SeeAllPill extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _SeeAllPill({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.7),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: AppTheme.primaryDark,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.arrow_forward_rounded,
                      color: AppTheme.primaryDark,
                      size: 14,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AllFilesSheet extends StatelessWidget {
  final List<FileModel> files;
  const _AllFilesSheet({required this.files});

  String _ext(String name) {
    final i = name.lastIndexOf('.');
    if (i < 0 || i == name.length - 1) return '';
    return name.substring(i + 1).toLowerCase();
  }

  String _shortDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[d.month - 1]} ${d.day.toString().padLeft(2, '0')}, ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (_, scrollCtrl) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.78),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.7),
                width: 1,
              ),
            ),
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFCBD5E0),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                  child: Row(
                    children: [
                      Text(
                        'Referenced files (${files.length})',
                        style: const TextStyle(
                          color: AppTheme.primaryDark,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(
                          Icons.close_rounded,
                          color: AppTheme.primaryDark,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                    itemCount: files.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final f = files[i];
                      final ext = _ext(f.fileName);
                      final isPdf = ext == 'pdf' ||
                          (f.fileType?.toLowerCase().contains('pdf') ?? false);
                      final isImg = const {
                        'jpg', 'jpeg', 'png', 'heic', 'webp', 'gif'
                      }.contains(ext);
                      final accent = isPdf
                          ? const Color(0xFFD64B4B)
                          : isImg
                              ? const Color(0xFF5A9A94)
                              : const Color(0xFF6B7C8C);
                      final icon = isPdf
                          ? Icons.picture_as_pdf_outlined
                          : isImg
                              ? Icons.image_outlined
                              : Icons.insert_drive_file_outlined;

                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () {
                            Navigator.pop(context);
                            context.push('/file/${f.id}');
                          },
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.9),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: accent.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(icon, color: accent, size: 22),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        f.fileName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: AppTheme.primaryDark,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: -0.2,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _shortDate(f.createdAt),
                                        style: const TextStyle(
                                          color: Color(0xFF6B7C8C),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
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
                        ),
                      );
                    },
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

class _OpenPill extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: AppTheme.primaryDark.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.25),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Text(
                'Open',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
              SizedBox(width: 4),
              Icon(
                Icons.arrow_forward_rounded,
                color: Colors.white,
                size: 14,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Input bar ──────────────────────────────────────────────────────────────────

class _ChatInputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool hasText;
  final bool disabled;
  final bool listening;
  final VoidCallback onSend;
  final VoidCallback onAddFile;
  final VoidCallback onMic;
  final List<FileModel> attachments;
  final void Function(FileModel) onRemoveAttachment;

  const _ChatInputBar({
    required this.controller,
    required this.hasText,
    required this.onSend,
    required this.onAddFile,
    required this.onMic,
    required this.listening,
    required this.attachments,
    required this.onRemoveAttachment,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.paddingOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 8, 20, bottomPad + 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (attachments.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SizedBox(
                height: 56,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.zero,
                  itemCount: attachments.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => _PendingAttachmentChip(
                    file: attachments[i],
                    onRemove: () => onRemoveAttachment(attachments[i]),
                  ),
                ),
              ),
            ),
          ClipRRect(
            borderRadius: BorderRadius.circular(40),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(40),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.85),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Upload a file',
                  onPressed: disabled ? null : onAddFile,
                  icon: const Icon(
                    Icons.add_rounded,
                    size: 24,
                    color: AppTheme.primaryDark,
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: controller,
                    minLines: 1,
                    maxLines: 4,
                    enabled: !disabled,
                    textInputAction: TextInputAction.send,
                    onSubmitted: disabled ? null : (_) => onSend(),
                    style: const TextStyle(
                      color: AppTheme.primaryDark,
                      fontSize: 14,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Ask Mercie about your health...',
                      hintStyle: TextStyle(
                        color: AppTheme.primaryDark.withValues(alpha: 0.5),
                        fontSize: 14,
                      ),
                      isDense: true,
                      isCollapsed: true,
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _SendOrMicButton(
                  hasText: hasText,
                  listening: listening,
                  onTap: hasText ? onSend : onMic,
                ),
              ],
            ),
          ),
        ),
      ),
        ],
      ),
    );
  }
}

class _PendingAttachmentChip extends StatelessWidget {
  final FileModel file;
  final VoidCallback onRemove;
  const _PendingAttachmentChip({required this.file, required this.onRemove});

  String get _ext {
    final n = file.fileName;
    final i = n.lastIndexOf('.');
    if (i < 0 || i == n.length - 1) return '';
    return n.substring(i + 1).toLowerCase();
  }

  bool get _isPdf =>
      _ext == 'pdf' || (file.fileType?.toLowerCase().contains('pdf') ?? false);
  bool get _isImage =>
      const {'jpg', 'jpeg', 'png', 'heic', 'webp', 'gif'}.contains(_ext);

  Color get _accent {
    if (_isPdf) return const Color(0xFFD64B4B);
    if (_isImage) return const Color(0xFF5A9A94);
    return const Color(0xFF6B7C8C);
  }

  IconData get _icon {
    if (_isPdf) return Icons.picture_as_pdf_outlined;
    if (_isImage) return Icons.image_outlined;
    return Icons.insert_drive_file_outlined;
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.9),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_icon, color: _accent, size: 18),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 130),
                child: Text(
                  file.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.primaryDark,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onRemove,
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(
                      Icons.close_rounded,
                      size: 14,
                      color: Color(0xFF6B7C8C),
                    ),
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

class _SendOrMicButton extends StatelessWidget {
  final bool hasText;
  final bool listening;
  final VoidCallback onTap;

  const _SendOrMicButton({
    required this.hasText,
    required this.listening,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fill = listening
        ? const Color(0xFFD64B4B)
        : const Color(0xFF1A212B);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: fill,
            shape: BoxShape.circle,
            boxShadow: listening
                ? [
                    BoxShadow(
                      color: const Color(0xFFD64B4B).withValues(alpha: 0.4),
                      blurRadius: 14,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: Icon(
              listening
                  ? Icons.stop_rounded
                  : hasText
                      ? Icons.arrow_upward_rounded
                      : Icons.mic_none_rounded,
              key: ValueKey('${hasText}_$listening'),
              color: Colors.white,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }
}
