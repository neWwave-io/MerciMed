import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../features/auth/providers/auth_provider.dart';
import '../../../shared/models/chat_message.dart';
import '../../../shared/theme/app_theme.dart';
import '../providers/chat_provider.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _inputCtrl.addListener(() {
      final next = _inputCtrl.text.trim().isNotEmpty;
      if (next != _hasText) setState(() => _hasText = next);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
  }

  void _scrollToEnd() {
    if (!_scrollCtrl.hasClients) return;
    _scrollCtrl.animateTo(
      _scrollCtrl.position.maxScrollExtent,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _inputCtrl.text;
    if (text.trim().isEmpty) return;
    final user = ref.read(supabaseClientProvider).auth.currentUser;
    final userId = user?.id ?? '';
    final persisted = ref.read(chatMessagesStreamProvider).value ?? const [];
    _inputCtrl.clear();
    ref.read(chatProvider.notifier).sendMessage(
          userId: userId,
          message: text,
          persistedHistory: persisted,
        );
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
  }

  @override
  Widget build(BuildContext context) {
    final live = ref.watch(chatProvider);
    final persistedAsync = ref.watch(chatMessagesStreamProvider);
    final persisted = persistedAsync.value ?? const <ChatMessage>[];

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
                optimisticUser: showOptimistic ? live.optimisticUser : null,
                streamingBuffer: live.streamingBuffer,
                isStreaming: live.isStreaming,
                errorMessage: live.errorMessage,
              ),
            ),
            _ChatInputBar(
              controller: _inputCtrl,
              hasText: _hasText,
              onSend: _send,
              disabled: live.isStreaming,
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
            onPressed: () =>
                ref.read(chatProvider.notifier).clearLocal(),
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
  final ChatMessage? optimisticUser;
  final String streamingBuffer;
  final bool isStreaming;
  final String? errorMessage;

  const _Messages({
    required this.scrollCtrl,
    required this.messages,
    required this.optimisticUser,
    required this.streamingBuffer,
    required this.isStreaming,
    required this.errorMessage,
  });

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
        ],
        if (optimisticUser != null) ...[
          const SizedBox(height: 16),
          _ChatBubble(
            text: optimisticUser!.content,
            isSent: true,
            time: _shortTime(optimisticUser!.createdAt),
          ),
        ],
        if (showLiveBubble) ...[
          const SizedBox(height: 16),
          if (streamingBuffer.isNotEmpty)
            _ChatBubble(
              text: streamingBuffer,
              isSent: false,
              time: _shortTime(DateTime.now()),
            )
          else
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
              text,
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

// ── Input bar ──────────────────────────────────────────────────────────────────

class _ChatInputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool hasText;
  final bool disabled;
  final VoidCallback onSend;

  const _ChatInputBar({
    required this.controller,
    required this.hasText,
    required this.onSend,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.paddingOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 8, 20, bottomPad + 12),
      child: ClipRRect(
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
                  onPressed: () {},
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
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      isCollapsed: true,
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _SendOrMicButton(
                  hasText: hasText,
                  onTap: onSend,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SendOrMicButton extends StatelessWidget {
  final bool hasText;
  final VoidCallback onTap;

  const _SendOrMicButton({required this.hasText, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: const BoxDecoration(
            color: Color(0xFF1A212B),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: Icon(
              hasText ? Icons.arrow_upward_rounded : Icons.mic_none_rounded,
              key: ValueKey(hasText),
              color: Colors.white,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }
}
