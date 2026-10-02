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
  final Map<String, int> unreadCounts;
  final String? currentChatUserId;
  final String? errorMessage;
  final bool hasMoreMessages;
  final bool isTyping;
  final String? typingUserId;
  final List<User> searchResults;
  final bool isSearching;

  /// Number of attachment uploads currently in flight. The composer disables
  /// its attach button while > 0 so uploads stay serialized and a second tap
  /// can't stack a duplicate send behind the first.
  final int pendingUploads;

  const ChatState({
    this.status = ChatStatus.initial,
    this.messages = const [],
    this.conversations = const {},
    this.lastMessages = const {},
    this.unreadCounts = const {},
    this.currentChatUserId,
    this.errorMessage,
    this.hasMoreMessages = true,
    this.isTyping = false,
    this.typingUserId,
    this.searchResults = const [],
    this.isSearching = false,
    this.pendingUploads = 0,
  });

  ChatState copyWith({
    ChatStatus? status,
    List<Message>? messages,
    Map<String, User>? conversations,
    Map<String, Message>? lastMessages,
    Map<String, int>? unreadCounts,
    String? currentChatUserId,
    String? errorMessage,

    /// Set to true to clear a previously shown error. copyWith can't
    /// distinguish "no change" from "set to null" for nullable fields, so
    /// without this flag a shown snackbar message would linger in state and
    /// suppress the next identical error via the listener's change guard.
    bool clearErrorMessage = false,

    /// Set to true to clear [currentChatUserId] when leaving a chat screen.
    /// Same nullable-field limitation as above: without the flag the stale
    /// open-chat id could never be reset to null.
    bool clearCurrentChat = false,
    bool? hasMoreMessages,
    bool? isTyping,
    String? typingUserId,
    List<User>? searchResults,
    bool? isSearching,
    int? pendingUploads,
  }) {
    return ChatState(
      status: status ?? this.status,
      messages: messages ?? this.messages,
      conversations: conversations ?? this.conversations,
      lastMessages: lastMessages ?? this.lastMessages,
      unreadCounts: unreadCounts ?? this.unreadCounts,
      currentChatUserId:
          clearCurrentChat ? null : (currentChatUserId ?? this.currentChatUserId),
      pendingUploads: pendingUploads ?? this.pendingUploads,
      errorMessage:
          clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
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
        unreadCounts,
        currentChatUserId,
        errorMessage,
        hasMoreMessages,
        isTyping,
        typingUserId,
        searchResults,
        isSearching,
        pendingUploads,
      ];
}
