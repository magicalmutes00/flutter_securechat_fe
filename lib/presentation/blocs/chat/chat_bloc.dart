import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/models/message_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/services/api_client.dart';
import '../../../data/services/websocket_service.dart';
import 'chat_event.dart';
import 'chat_state.dart';

class ChatBloc extends Bloc<ChatEvent, ChatState> {
  final ApiClient _apiClient = ApiClient();
  final WebSocketService _wsService = WebSocketService();

  StreamSubscription? _messageSubscription;
  StreamSubscription? _typingSubscription;
  StreamSubscription? _statusSubscription;

  String? _currentViewingUserId;

  ChatBloc() : super(const ChatState()) {
    on<ChatLoadMessages>(_onLoadMessages);
    on<ChatSendTextMessage>(_onSendTextMessage);
    on<ChatSendFileMessage>(_onSendFileMessage);
    on<ChatReceiveMessage>(_onReceiveMessage);
    on<ChatUpdateMessageStatus>(_onUpdateMessageStatus);
    on<ChatSendTypingStatus>(_onSendTypingStatus);
    on<ChatLoadConversations>(_onLoadConversations);
    on<ChatSearchUsers>(_onSearchUsers);

    _subscribeToWebSocket();
  }

  void _subscribeToWebSocket() {
    _messageSubscription = _wsService.messageStream.listen((message) {
      add(ChatReceiveMessage(message));
    });

    _typingSubscription = _wsService.typingStream.listen((data) {
      // Handle typing indicator
    });

    _statusSubscription = _wsService.statusStream.listen((data) {
      if (data['type'] == 'message_sent') {
        add(ChatUpdateMessageStatus(
          messageId: data['data']['id'],
          status: 'sent',
        ));
      }
    });
  }

  void setCurrentViewingUser(String? userId) {
    _currentViewingUserId = userId;
  }

  Future<void> _onLoadMessages(
    ChatLoadMessages event,
    Emitter<ChatState> emit,
  ) async {
    emit(state.copyWith(
      status: ChatStatus.loading,
      currentChatUserId: event.userId,
    ));

    try {
      final messagesData = await _apiClient.getMessages(
        event.userId,
        limit: AppConstants.messagesPageSize,
      );

      final newMessages = messagesData
          .map((json) => Message.fromJson(json as Map<String, dynamic>))
          .toList()
          .reversed
          .toList();

      final existingIds = state.messages.map((m) => m.id).toSet();
      final uniqueNewMessages = newMessages
          .where((m) => !existingIds.contains(m.id))
          .toList();

      emit(state.copyWith(
        status: ChatStatus.loaded,
        messages: event.refresh ? uniqueNewMessages : [...state.messages, ...uniqueNewMessages],
        hasMoreMessages: newMessages.length >= AppConstants.messagesPageSize,
      ));
    } catch (e) {
      emit(state.copyWith(
        status: ChatStatus.error,
        errorMessage: e.toString(),
      ));
    }
  }

  Future<void> _onSendTextMessage(
    ChatSendTextMessage event,
    Emitter<ChatState> emit,
  ) async {
    final tempMessage = Message(
      id: 'temp_${DateTime.now().millisecondsSinceEpoch}',
      senderId: _wsService.currentUserId ?? '',
      receiverId: event.receiverId,
      messageType: AppConstants.messageTypeText,
      content: event.content,
      status: 'sent',
      createdAt: DateTime.now(),
    );

    // Update UI immediately
    final newLastMessages = Map<String, Message>.from(state.lastMessages);
    newLastMessages[event.receiverId] = tempMessage;

    List<Message> updatedMessages = [...state.messages, tempMessage];

    Map<String, User> updatedConversations = Map<String, User>.from(state.conversations);
    if (!state.conversations.containsKey(event.receiverId)) {
      final newUser = User(
        id: event.receiverId,
        displayName: null,
        email: null,
        phone: null,
        avatarUrl: null,
        isOnline: false,
        lastSeen: null,
      );
      updatedConversations[event.receiverId] = newUser;
    }

    emit(state.copyWith(
      status: ChatStatus.loaded,
      lastMessages: newLastMessages,
      messages: updatedMessages,
      conversations: updatedConversations,
    ));

    // Try to send via WebSocket, fallback to HTTP
    try {
      if (_wsService.isConnected) {
        _wsService.sendMessage(
          receiverId: event.receiverId,
          messageType: AppConstants.messageTypeText,
          content: event.content,
        );
      } else {
        await _apiClient.sendMessage({
          'receiver_id': event.receiverId,
          'message_type': AppConstants.messageTypeText,
          'content': event.content,
        });
      }
    } catch (e) {
      // Already updated UI optimistically
    }
  }

  Future<void> _onSendFileMessage(
    ChatSendFileMessage event,
    Emitter<ChatState> emit,
  ) async {
    emit(state.copyWith(status: ChatStatus.sending));

    try {
      final uploadResult = await _apiClient.uploadFile(
        event.filePath,
        event.messageType,
      );

      if (uploadResult['success'] == true) {
        if (_wsService.isConnected) {
          _wsService.sendMessage(
            receiverId: event.receiverId,
            messageType: event.messageType,
            content: '',
            fileUrl: uploadResult['url'],
            fileName: uploadResult['file_name'],
            fileSize: uploadResult['file_size'],
            mediaType: uploadResult['media_type'],
          );
        }
      }

      emit(state.copyWith(status: ChatStatus.loaded));
    } catch (e) {
      emit(state.copyWith(
        status: ChatStatus.error,
        errorMessage: e.toString(),
      ));
    }
  }

  void _onReceiveMessage(
    ChatReceiveMessage event,
    Emitter<ChatState> emit,
  ) {
    final message = event.message;
    final currentUserId = _wsService.currentUserId;

    // Skip own messages
    if (currentUserId != null && message.senderId == currentUserId) {
      return;
    }

    // Skip duplicates
    final existingIds = state.messages.map((m) => m.id).toSet();
    if (existingIds.contains(message.id)) {
      return;
    }

    // Add to messages if for current chat
    if (state.currentChatUserId != null &&
        (message.senderId == state.currentChatUserId ||
            message.receiverId == state.currentChatUserId)) {
      emit(state.copyWith(
        messages: [...state.messages, message],
      ));
    }

    // Update last message
    final newLastMessages = Map<String, Message>.from(state.lastMessages);
    newLastMessages[message.senderId] = message;

    // Add conversation if needed
    Map<String, User> updatedConversations = state.conversations;
    if (!state.conversations.containsKey(message.senderId)) {
      final newUser = User(
        id: message.senderId,
        displayName: null,
        email: null,
        phone: null,
        avatarUrl: null,
        isOnline: false,
        lastSeen: null,
      );
      updatedConversations = Map<String, User>.from(state.conversations);
      updatedConversations[message.senderId] = newUser;
    }

    emit(state.copyWith(
      lastMessages: newLastMessages,
      conversations: updatedConversations,
    ));
  }

  Future<void> _onUpdateMessageStatus(
    ChatUpdateMessageStatus event,
    Emitter<ChatState> emit,
  ) async {
    final updatedMessages = state.messages.map((message) {
      if (message.id == event.messageId) {
        return message.copyWith(status: event.status);
      }
      return message;
    }).toList();

    emit(state.copyWith(messages: updatedMessages));
  }

  void _onSendTypingStatus(
    ChatSendTypingStatus event,
    Emitter<ChatState> emit,
  ) {
    _wsService.sendTyping(event.receiverId, event.isTyping);
  }

  Future<void> _onLoadConversations(
    ChatLoadConversations event,
    Emitter<ChatState> emit,
  ) async {
    // Only show loading if we don't have conversations yet
    if (state.conversations.isEmpty) {
      emit(state.copyWith(status: ChatStatus.loading));
    }

    try {
      final conversationsData = await _apiClient.getConversations();

      final conversations = <String, User>{};
      final lastMessages = <String, Message>{};

      for (final conv in conversationsData) {
        final userData = conv['user'] as Map<String, dynamic>;
        final user = User.fromJson(userData);
        conversations[user.id] = user;

        // Get last message if available
        if (conv['last_message'] != null) {
          final lastMsg = Message.fromJson(conv['last_message'] as Map<String, dynamic>);
          lastMessages[user.id] = lastMsg;
        }
      }

      emit(state.copyWith(
        status: ChatStatus.loaded,
        conversations: conversations,
        lastMessages: lastMessages,
      ));
    } catch (e) {
      // Only set error if we don't have existing conversations
      if (state.conversations.isEmpty) {
        emit(state.copyWith(
          status: ChatStatus.error,
          errorMessage: e.toString(),
        ));
      }
    }
  }

  Future<void> _onSearchUsers(
    ChatSearchUsers event,
    Emitter<ChatState> emit,
  ) async {
    if (event.query.isEmpty) {
      emit(state.copyWith(searchResults: [], isSearching: false));
      return;
    }

    emit(state.copyWith(isSearching: true));

    try {
      final results = await _apiClient.searchUsers(event.query);
      final users = results.map((json) => User.fromJson(json as Map<String, dynamic>)).toList();

      emit(state.copyWith(
        searchResults: users,
        isSearching: false,
      ));
    } catch (e) {
      emit(state.copyWith(
        isSearching: false,
        errorMessage: e.toString(),
      ));
    }
  }

  @override
  Future<void> close() {
    _messageSubscription?.cancel();
    _typingSubscription?.cancel();
    _statusSubscription?.cancel();
    return super.close();
  }
}