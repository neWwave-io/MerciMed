import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/chat_message.dart';

class ChatState {
  final List<ChatMessage> messages;
  final bool isStreaming;
  final String streamingBuffer;

  const ChatState({
    this.messages = const [],
    this.isStreaming = false,
    this.streamingBuffer = '',
  });

  ChatState copyWith({
    List<ChatMessage>? messages,
    bool? isStreaming,
    String? streamingBuffer,
  }) =>
      ChatState(
        messages: messages ?? this.messages,
        isStreaming: isStreaming ?? this.isStreaming,
        streamingBuffer: streamingBuffer ?? this.streamingBuffer,
      );
}

class ChatNotifier extends StateNotifier<ChatState> {
  ChatNotifier() : super(const ChatState());

  // Full implementation in Session 6
  Future<void> sendMessage(String userId, String message) async {}

  void clearHistory() => state = const ChatState();
}

final chatProvider = StateNotifierProvider<ChatNotifier, ChatState>(
  (_) => ChatNotifier(),
);
