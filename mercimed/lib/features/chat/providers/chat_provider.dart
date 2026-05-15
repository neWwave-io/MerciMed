import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/cache/local_db.dart';
import '../../../shared/models/chat_message.dart';
import '../../../shared/models/conversation.dart';
import '../../../supabase_config.dart';
import '../../auth/providers/auth_provider.dart';

// ── Conversations stream ─────────────────────────────────────────────────────

/// Reconciler: subscribes to the Supabase `conversations` stream and
/// upserts the snapshot into drift. Tombstones rows missing from the
/// server view. Conversations don't have a `dirty` flag because there is
/// no offline write path for them in v1+v2.
final _conversationHydrationProvider = Provider.autoDispose<void>((ref) {
  final client = ref.watch(supabaseClientProvider);
  final db = ref.watch(localDbProvider);
  final user = client.auth.currentUser;
  if (user == null) return;
  final ownerId = user.id;

  final sub = client
      .from('conversations')
      .stream(primaryKey: ['id'])
      .eq('user_id', ownerId)
      .listen((rows) async {
        try {
          final list =
              rows.map<Conversation>(Conversation.fromJson).toList(
                    growable: false,
                  );
          await db.upsertConversations(list);
          await db.deleteConversationsNotIn(
            ownerId: ownerId,
            keepIds: list.map((c) => c.id).toSet(),
          );
        } catch (e, st) {
          debugPrint('conversations hydration failed: $e\n$st');
        }
      });
  ref.onDispose(sub.cancel);
});

/// Local-first stream of conversations for the signed-in user.
/// Backed by drift so the list is available offline.
final conversationsStreamProvider =
    StreamProvider.autoDispose<List<Conversation>>((ref) {
  ref.watch(_conversationHydrationProvider); // keep reconciler alive
  final client = ref.watch(supabaseClientProvider);
  final db = ref.watch(localDbProvider);
  final user = client.auth.currentUser;
  if (user == null) return Stream.value(const []);
  return db.watchConversationsForOwner(user.id);
});

/// Currently selected conversation id. null = "use latest, or create one
/// when the user sends a message". Set by the header buttons.
final activeConversationIdProvider = StateProvider<String?>((_) => null);

/// Convenience: the active conversation id resolved against the live list.
/// If null, falls back to the most recent conversation; if none exist, null.
final effectiveConversationIdProvider = Provider.autoDispose<String?>((ref) {
  final explicit = ref.watch(activeConversationIdProvider);
  if (explicit != null) return explicit;
  final list = ref.watch(conversationsStreamProvider).value ?? const [];
  return list.isEmpty ? null : list.first.id;
});

// ── Messages stream (scoped to active conversation) ──────────────────────────

/// Reconciler for chat messages, scoped to whichever conversation is
/// currently active. Re-subscribes when [effectiveConversationIdProvider]
/// flips. Cancellation on dispose handles the switch cleanly.
final _messageHydrationProvider = Provider.autoDispose<void>((ref) {
  final client = ref.watch(supabaseClientProvider);
  final db = ref.watch(localDbProvider);
  final user = client.auth.currentUser;
  final convId = ref.watch(effectiveConversationIdProvider);
  if (user == null || convId == null) return;

  final sub = client
      .from('chat_messages')
      .stream(primaryKey: ['id'])
      .eq('conversation_id', convId)
      .listen((rows) async {
        try {
          final list = rows
              .map<ChatMessage>(ChatMessage.fromJson)
              .toList(growable: false);
          await db.upsertMessages(list);
          await db.deleteMessagesNotIn(
            conversationId: convId,
            keepIds: list.map((m) => m.id).toSet(),
          );
        } catch (e, st) {
          debugPrint('messages hydration failed: $e\n$st');
        }
      });
  ref.onDispose(sub.cancel);
});

final chatMessagesStreamProvider =
    StreamProvider.autoDispose<List<ChatMessage>>((ref) {
  ref.watch(_messageHydrationProvider);
  final db = ref.watch(localDbProvider);
  final convId = ref.watch(effectiveConversationIdProvider);
  if (convId == null) return Stream.value(const []);
  return db.watchMessagesForConversation(convId).map((list) {
    // Mirror the previous client-side ordering tie-break.
    final sorted = [...list]
      ..sort((a, b) {
        final cmp = a.createdAt.compareTo(b.createdAt);
        if (cmp != 0) return cmp;
        if (a.role == 'user' && b.role != 'user') return -1;
        if (a.role != 'user' && b.role == 'user') return 1;
        return a.id.compareTo(b.id);
      });
    return sorted;
  });
});

// ── Live composer state (optimistic + streaming) ────────────────────────────

class ChatLive {
  final ChatMessage? optimisticUser;
  final bool isStreaming;
  final String streamingBuffer;
  final String? errorMessage;

  const ChatLive({
    this.optimisticUser,
    this.isStreaming = false,
    this.streamingBuffer = '',
    this.errorMessage,
  });

  ChatLive copyWith({
    ChatMessage? optimisticUser,
    bool? isStreaming,
    String? streamingBuffer,
    String? errorMessage,
    bool clearOptimistic = false,
    bool clearError = false,
  }) =>
      ChatLive(
        optimisticUser:
            clearOptimistic ? null : (optimisticUser ?? this.optimisticUser),
        isStreaming: isStreaming ?? this.isStreaming,
        streamingBuffer: streamingBuffer ?? this.streamingBuffer,
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      );
}

class ChatNotifier extends StateNotifier<ChatLive> {
  final Ref _ref;
  final SupabaseClient _client;
  final Dio _dio;
  CancelToken? _cancel;

  ChatNotifier(this._ref, this._client)
      : _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(minutes: 2),
        )),
        super(const ChatLive());

  /// Creates a new conversation row and switches the active id to it.
  /// Returns the new conversation id (or null if not signed in).
  Future<String?> startNewConversation({String? title}) async {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    _cancel?.cancel('switching-conversation');
    state = const ChatLive();
    final inserted = await _client
        .from('conversations')
        .insert({'user_id': user.id, 'title': title})
        .select('id')
        .single();
    final id = inserted['id'] as String;
    _ref.read(activeConversationIdProvider.notifier).state = id;
    return id;
  }

  /// Switch to an existing conversation (no insert).
  void switchTo(String conversationId) {
    _cancel?.cancel('switching-conversation');
    state = const ChatLive();
    _ref.read(activeConversationIdProvider.notifier).state = conversationId;
  }

  /// Ensures there's an active conversation to write into, creating one on
  /// demand the first time the user types in a fresh session.
  Future<String?> _ensureConversation() async {
    final existing = _ref.read(effectiveConversationIdProvider);
    if (existing != null) return existing;
    return startNewConversation();
  }

  Future<void> sendMessage({
    required String userId,
    required String message,
    required List<ChatMessage> persistedHistory,
  }) async {
    final trimmed = message.trim();
    if (trimmed.isEmpty || state.isStreaming) return;

    final convId = await _ensureConversation();
    if (convId == null) return;

    final optimistic = ChatMessage(
      id: 'local-${DateTime.now().microsecondsSinceEpoch}',
      userId: userId,
      conversationId: convId,
      role: 'user',
      content: trimmed,
      createdAt: DateTime.now(),
    );
    state = state.copyWith(
      optimisticUser: optimistic,
      isStreaming: true,
      streamingBuffer: '',
      clearError: true,
    );

    final history = persistedHistory
        .map((m) => {'role': m.role, 'content': m.content})
        .toList();

    _cancel = CancelToken();

    try {
      final session = _client.auth.currentSession;
      final token = session?.accessToken ?? supabaseAnonKey;
      final response = await _dio.post<ResponseBody>(
        '$supabaseUrl/functions/v1/chat',
        data: {
          'user_id': userId,
          'conversation_id': convId,
          'message': trimmed,
          'history': history,
        },
        options: Options(
          responseType: ResponseType.stream,
          headers: {
            'Authorization': 'Bearer $token',
            'apikey': supabaseAnonKey,
            'Content-Type': 'application/json',
            'Accept': 'text/event-stream',
          },
        ),
        cancelToken: _cancel,
      );

      final stream = response.data?.stream;
      if (stream == null) throw Exception('No response stream');

      String pending = '';
      final buffer = StringBuffer();

      await for (final chunk in stream) {
        pending += utf8.decode(chunk, allowMalformed: true);
        while (true) {
          final idx = pending.indexOf('\n\n');
          if (idx < 0) break;
          final raw = pending.substring(0, idx);
          pending = pending.substring(idx + 2);

          for (final line in raw.split('\n')) {
            final l = line.trimLeft();
            if (!l.startsWith('data:')) continue;
            final payload = l.substring(5).trimLeft();
            if (payload == '[DONE]') {
              _finalize();
              return;
            }
            try {
              final parsed = jsonDecode(payload) as Map<String, dynamic>;
              final tok = parsed['token'] as String?;
              if (tok != null && tok.isNotEmpty) {
                buffer.write(tok);
                state = state.copyWith(streamingBuffer: buffer.toString());
              }
            } catch (_) {/* skip malformed */}
          }
        }
      }
      _finalize();
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        state = const ChatLive();
        return;
      }
      _failChat();
    } catch (_) {
      _failChat();
    }
  }

  void _finalize() {
    state = const ChatLive();
  }

  void _failChat() {
    state = state.copyWith(
      isStreaming: false,
      streamingBuffer: '',
      errorMessage: 'Mercie is unavailable right now.',
      clearOptimistic: true,
    );
  }

  void cancelStreaming() {
    _cancel?.cancel('user-cancel');
  }

  void clearError() => state = state.copyWith(clearError: true);
  void clearLocal() => state = const ChatLive();

  /// Deletes the currently-active conversation entirely (its messages cascade
  /// because of the FK). Falls back to no active conversation; the next send
  /// will create a fresh one.
  Future<void> deleteActiveConversation() async {
    final convId = _ref.read(effectiveConversationIdProvider);
    if (convId == null) return;
    _cancel?.cancel('clear-history');
    state = const ChatLive();
    _ref.read(activeConversationIdProvider.notifier).state = null;
    await _client.from('conversations').delete().eq('id', convId);
  }

  /// Renames a conversation (used for titling once we have first user
  /// message context).
  Future<void> renameConversation(String conversationId, String title) async {
    await _client
        .from('conversations')
        .update({'title': title, 'updated_at': DateTime.now().toIso8601String()})
        .eq('id', conversationId);
  }

  @override
  void dispose() {
    _cancel?.cancel('disposed');
    _dio.close(force: true);
    super.dispose();
  }
}

final chatProvider = StateNotifierProvider<ChatNotifier, ChatLive>(
  (ref) => ChatNotifier(ref, ref.watch(supabaseClientProvider)),
);
