import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/models/chat_message.dart';
import '../../../supabase_config.dart';
import '../../auth/providers/auth_provider.dart';

/// Live persisted chat history from `chat_messages` — pushed by Supabase
/// Realtime, ordered chronologically. The chat edge function inserts both
/// the user and assistant rows after the stream completes, so this stream
/// naturally absorbs the conversation once the AI responds.
final chatMessagesStreamProvider =
    StreamProvider.autoDispose<List<ChatMessage>>((ref) {
  final client = ref.watch(supabaseClientProvider);
  final user = client.auth.currentUser;
  if (user == null) return Stream.value(const []);
  return client
      .from('chat_messages')
      .stream(primaryKey: ['id'])
      .eq('user_id', user.id)
      .order('created_at')
      .map((rows) => rows.map(ChatMessage.fromJson).toList());
});

/// In-flight state for the chat composer: an optimistic user bubble while
/// the edge function is responding, plus the streaming token buffer.
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
  final SupabaseClient _client;
  final Dio _dio;
  CancelToken? _cancel;

  ChatNotifier(this._client)
      : _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(minutes: 2),
        )),
        super(const ChatLive());

  Future<void> sendMessage({
    required String userId,
    required String message,
    required List<ChatMessage> persistedHistory,
  }) async {
    final trimmed = message.trim();
    if (trimmed.isEmpty || state.isStreaming) return;

    // 1. Optimistic user bubble — held in ChatLive until the stream
    //    re-emits with the persisted DB row.
    final optimistic = ChatMessage(
      id: 'local-${DateTime.now().microsecondsSinceEpoch}',
      userId: userId,
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
            } catch (_) {
              // skip malformed events
            }
          }
        }
      }

      // Stream closed without [DONE].
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

  /// Drop the in-flight buffer & optimistic message. The persisted stream
  /// will deliver the real DB rows for both user + assistant turns.
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

  /// Wipes the local in-flight state. Persisted history isn't affected.
  void clearLocal() => state = const ChatLive();

  @override
  void dispose() {
    _cancel?.cancel('disposed');
    _dio.close(force: true);
    super.dispose();
  }
}

final chatProvider = StateNotifierProvider<ChatNotifier, ChatLive>(
  (ref) => ChatNotifier(ref.watch(supabaseClientProvider)),
);
