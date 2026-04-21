import 'package:equatable/equatable.dart';
import '../../../data/models/message_model.dart';
import '../../../data/models/user_model.dart';

enum ChatStatus {
  initial,
  loading,
  loaded,
  sending,
  error,
}

class ChatState extends Equatable {
  final ChatStatus status;
  final List<Message> messages;
  final Map<String, User> conversations;
  final Map<String, Message> lastMessages;
  final String? currentChatUserId;
  final String? errorMessage;
  final bool hasMoreMessages;
  final bool isTyping;
  final String? typingUserId;
  final List<User> searchResults;
  final bool isSearching;

  const ChatState({
    this.status = ChatStatus.initial,
    this.messages = const [],
    this.conversations = const {},
    this.lastMessages = const {},
    this.currentChatUserId,
    this.errorMessage,
    this.hasMoreMessages = true,
    this.isTyping = false,
    this.typingUserId,
    this.searchResults = const [],
    this.isSearching = false,
  });

  ChatState copyWith({
    ChatStatus? status,
    List<Message>? messages,
    Map<String, User>? conversations,
    Map<String, Message>? lastMessages,
    String? currentChatUserId,
    String? errorMessage,
    bool? hasMoreMessages,
    bool? isTyping,
    String? typingUserId,
    List<User>? searchResults,
    bool? isSearching,
  }) {
    return ChatState(
      status: status ?? this.status,
      messages: messages ?? this.messages,
      conversations: conversations ?? this.conversations,
      lastMessages: lastMessages ?? this.lastMessages,
      currentChatUserId: currentChatUserId ?? this.currentChatUserId,
      errorMessage: errorMessage ?? this.errorMessage,
      hasMoreMessages: hasMoreMessages ?? this.hasMoreMessages,
      isTyping: isTyping ?? this.isTyping,
      typingUserId: typingUserId ?? this.typingUserId,
      searchResults: searchResults ?? this.searchResults,
      isSearching: isSearching ?? this.isSearching,
    );
  }

  @override
  List<Object?> get props => [
        status,
        messages,
        conversations,
        lastMessages,
        currentChatUserId,
        errorMessage,
        hasMoreMessages,
        isTyping,
        typingUserId,
        searchResults,
        isSearching,
      ];
}
