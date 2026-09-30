import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/models/message_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/services/api_client.dart';
import '../../../data/services/in_app_notification_service.dart';
import '../../../data/services/local_storage_service.dart';
import '../../../data/services/websocket_service.dart';
import '../../../data/services/e2ee/e2ee_service.dart';
import 'chat_event.dart';
import 'chat_state.dart';

class ChatBloc extends Bloc<ChatEvent, ChatState> {
  final ApiClient _apiClient = ApiClient();
  final WebSocketService _wsService = WebSocketService();
  final LocalStorageService _localStorage = LocalStorageService();

  StreamSubscription? _messageSubscription;
  StreamSubscription? _typingSubscription;
  StreamSubscription? _statusSubscription;
  Timer? _typingClearTimer;

  ChatBloc() : super(const ChatState()) {
    on<ChatLoadMessages>(_onLoadMessages);
    on<ChatSendTextMessage>(_onSendTextMessage);
    on<ChatSendFileMessage>(_onSendFileMessage);
    on<ChatReceiveMessage>(_onReceiveMessage);
    on<ChatUpdateMessageStatus>(_onUpdateMessageStatus);
    on<ChatSendTypingStatus>(_onSendTypingStatus);
    on<ChatReceiveTypingStatus>(_onReceiveTypingStatus);
    on<ChatReceiveReceipt>(_onReceiveReceipt);
    on<ChatLoadConversations>(_onLoadConversations);
    on<ChatSearchUsers>(_onSearchUsers);
    on<ChatDeleteMessage>(_onDeleteMessage);
    on<ChatReset>(_onChatReset);

    _subscribeToWebSocket();
  }

  void _subscribeToWebSocket() {
    // Messages arrive pre-decrypted: InAppNotificationService decrypts each
    // ciphertext exactly once before re-broadcasting (a Double-Ratchet
    // message cannot be decrypted twice).
    _messageSubscription = InAppNotificationService
        .instance.decryptedMessageStream
        .listen((message) {
      add(ChatReceiveMessage(message));
    });
    _typingSubscription = _wsService.typingStream.listen((data) {
      final senderId = data['sender_id'] as String?;
      final isTyping = data['is_typing'] as bool? ?? false;
      if (senderId == null) return;

      add(ChatReceiveTypingStatus(senderId: senderId, isTyping: isTyping));
    });

    _statusSubscription = _wsService.statusStream.listen((data) {
      final type = data['type'] as String?;
      final me = _wsService.currentUserId;

      if (type == 'message_sent' && data['data'] != null) {
        add(ChatUpdateMessageStatus(
          messageId: data['data']['id'],
          status: 'sent',
        ));
        return;
      }

      if (me == null) return;

      final peerId = data['receiver_id'] as String?;
      if (peerId == null) return;

      if (type == 'delivery_receipt') {
        add(ChatReceiveReceipt(peerUserId: peerId, status: 'delivered'));
      } else if (type == 'read_receipt') {
        add(ChatReceiveReceipt(peerUserId: peerId, status: 'read'));
      }
    });

    // Flush any offline-queued messages as soon as the socket (re)connects.
    _wsService.connectionStream.listen((connected) {
      if (connected) {
        unawaited(_flushOutbox());
      }
    });
  }

  Future<void> _flushOutbox() async {
    final currentUserId = _wsService.currentUserId;
    if (currentUserId == null || currentUserId.isEmpty) return;

    final pending = _localStorage.getOutbox(currentUserId);
    if (pending.isEmpty) return;

    for (final message in pending) {
      try {
        final encrypted = await E2eeService.instance.prepareOutgoingText(
          currentUserId: currentUserId,
          receiverId: message.receiverId,
          plaintext: message.content,
        );
        final usesSignal = encrypted['encryption'] == 'signal';

        await _apiClient.sendMessage({
          'receiver_id': message.receiverId,
          'message_type': message.messageType,
          'content': usesSignal ? '' : message.content,
          'encryption': encrypted['encryption'] as String? ?? 'none',
          'cipher_type': encrypted['cipher_type'],
          'cipher_body': encrypted['cipher_body'],
        });
        await _localStorage.removeFromOutbox(currentUserId, message.id);
      } catch (_) {
        // Keep the message queued; a later reconnect will retry it.
      }
    }
  }

  Future<void> _onLoadMessages(
    ChatLoadMessages event,
    Emitter<ChatState> emit,
  ) async {
    final currentUserId = _wsService.currentUserId;

    if (currentUserId == null) return;

    emit(state.copyWith(
      status: ChatStatus.loading,
      currentChatUserId: event.userId,
    ));

    final localMessages =
        _localStorage.getMessages(currentUserId, event.userId);

    if (localMessages.isNotEmpty && !event.refresh) {
      // Locally cached messages are stored decrypted, but re-decrypt defensively
      // in case a previous session persisted ciphertext.
      final decryptedLocal = <Message>[];
      for (final m in localMessages) {
        decryptedLocal.add(await E2eeService.instance
            .decryptMessage(m, currentUserId: currentUserId));
      }
      emit(state.copyWith(
        status: ChatStatus.loaded,
        messages: decryptedLocal,
        hasMoreMessages: true,
      ));
    }

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

      // Decrypt Signal-encrypted messages fetched from the server.
      final decryptedMessages = <Message>[];
      for (final m in newMessages) {
        decryptedMessages.add(await E2eeService.instance
            .decryptMessage(m, currentUserId: currentUserId));
      }

      await _localStorage.saveMessages(
          currentUserId, event.userId, decryptedMessages);

      final existingIds = state.messages.map((m) => m.id).toSet();
      final uniqueNewMessages =
          decryptedMessages.where((m) => !existingIds.contains(m.id)).toList();

      final allMessages = [...state.messages];
      for (final msg in uniqueNewMessages) {
        if (!allMessages.any((m) => m.id == msg.id)) {
          allMessages.add(msg);
        }
      }
      allMessages.sort((a, b) => a.createdAt.compareTo(b.createdAt));

      emit(state.copyWith(
        status: ChatStatus.loaded,
        messages: allMessages,
        hasMoreMessages: newMessages.length >= AppConstants.messagesPageSize,
      ));

      // Mark the peer's messages as read now that the chat is open.
      if (_wsService.isConnected && currentUserId.isNotEmpty) {
        _wsService.sendReadReceipt(event.userId, currentUserId);
      }
    } catch (e) {
      if (state.messages.isEmpty) {
        emit(state.copyWith(
          status: ChatStatus.error,
          errorMessage: e.toString(),
        ));
      }
    }
  }

  Future<void> _onSendTextMessage(
    ChatSendTextMessage event,
    Emitter<ChatState> emit,
  ) async {
    final currentUserId = _wsService.currentUserId ?? '';

    final tempMessage = Message(
      id: 'temp_${DateTime.now().millisecondsSinceEpoch}',
      senderId: currentUserId,
      receiverId: event.receiverId,
      messageType: AppConstants.messageTypeText,
      content: event.content,
      status: 'sent',
      createdAt: DateTime.now(),
    );

    final previousLastMessages = Map<String, Message>.from(state.lastMessages);
    final newLastMessages = Map<String, Message>.from(state.lastMessages);
    newLastMessages[event.receiverId] = tempMessage;

    List<Message> updatedMessages = [...state.messages, tempMessage];

    Map<String, User> updatedConversations =
        Map<String, User>.from(state.conversations);
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

    if (currentUserId.isNotEmpty) {
      await _localStorage.addMessage(
          currentUserId, event.receiverId, tempMessage);
      await _localStorage.saveConversations(
          currentUserId, updatedConversations, newLastMessages);
    }

    try {
      final encrypted = await E2eeService.instance.prepareOutgoingText(
        currentUserId: currentUserId,
        receiverId: event.receiverId,
        plaintext: event.content,
      );
      final usesSignal = encrypted['encryption'] == 'signal';

      if (_wsService.isConnected) {
        _wsService.sendMessage(
          receiverId: event.receiverId,
          messageType: AppConstants.messageTypeText,
          content: usesSignal ? '' : event.content,
          encryption: encrypted['encryption'] as String? ?? 'none',
          cipherType: encrypted['cipher_type'] as int?,
          cipherBody: encrypted['cipher_body'] as String?,
        );
      } else {
        // Try the REST fallback; if the device is fully offline, queue the
        // message for delivery once the socket to the server reconnects.
        try {
          await _apiClient.sendMessage({
            'receiver_id': event.receiverId,
            'message_type': AppConstants.messageTypeText,
            'content': usesSignal ? '' : event.content,
            'encryption': encrypted['encryption'] as String? ?? 'none',
            'cipher_type': encrypted['cipher_type'],
            'cipher_body': encrypted['cipher_body'],
          });
        } catch (_) {
          if (currentUserId.isNotEmpty) {
            await _localStorage.enqueueOutbox(currentUserId, tempMessage);
          }
        }
      }
    } on E2eeEncryptionException catch (e) {
      // Encryption failed: nothing was sent. Roll back the optimistic bubble
      // so the UI never shows a message that will never arrive, and surface
      // the reason instead of silently downgrading to plaintext.
      emit(state.copyWith(
        status: ChatStatus.loaded,
        messages: state.messages.where((m) => m.id != tempMessage.id).toList(),
        lastMessages: previousLastMessages,
        errorMessage: e.message,
      ));
    } catch (e) {
      // Delivery failed after successful encryption (e.g. offline) — the REST
      // fallback above already queued the message in the outbox.
    }
  }

  Future<void> _onSendFileMessage(
    ChatSendFileMessage event,
    Emitter<ChatState> emit,
  ) async {
    emit(state.copyWith(status: ChatStatus.sending));

    final currentUserId = _wsService.currentUserId ?? '';

    try {
      // Encrypt the media bytes end-to-end before they leave the device.
      final encryptedMedia =
          await E2eeService.instance.encryptMediaFile(event.filePath);

      final uploadResult = await _apiClient.uploadFile(
        encryptedMedia.cipherPath,
        event.messageType,
        // Keep the original file's name so the server's extension allow-list
        // sees e.g. ".jpg" — the ciphertext content itself is opaque.
        filename: event.filePath.split('/').last.split('\\').last,
      );

      if (uploadResult['success'] == true) {
        // Deliver the media key inside a Signal-encrypted envelope so the
        // server only ever sees the ciphertext blob.
        final crypto = await E2eeService.instance.encryptEnvelopeForPeer(
          currentUserId: currentUserId,
          receiverId: event.receiverId,
          envelope: {
            'k': encryptedMedia.keyB64,
            'iv': encryptedMedia.nonceB64,
            'text': '',
          },
        );

        if (_wsService.isConnected) {
          _wsService.sendMessage(
            receiverId: event.receiverId,
            messageType: event.messageType,
            content: '',
            fileUrl: uploadResult['url'],
            fileName: uploadResult['file_name'],
            fileSize: uploadResult['file_size'],
            mediaType: uploadResult['media_type'],
            encryption: crypto['encryption'] as String? ?? 'none',
            cipherType: crypto['cipher_type'] as int?,
            cipherBody: crypto['cipher_body'] as String?,
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

  Future<void> _onReceiveMessage(
    ChatReceiveMessage event,
    Emitter<ChatState> emit,
  ) async {
    var message = event.message;
    final currentUserId = _wsService.currentUserId ?? '';

    // Decrypt Signal-encrypted messages before display/storage.
    message = await E2eeService.instance
        .decryptMessage(message, currentUserId: currentUserId);

    if (currentUserId.isNotEmpty && message.senderId == currentUserId) {
      return;
    }

    final existingIds = state.messages.map((m) => m.id).toSet();
    if (existingIds.contains(message.id)) {
      return;
    }

    final isViewingThisChat = state.currentChatUserId != null &&
        (message.senderId == state.currentChatUserId ||
            message.receiverId == state.currentChatUserId);

    // Auto-send a read receipt when the chat is open so the sender sees
    // their messages flip to "read".
    if (isViewingThisChat &&
        message.senderId != currentUserId &&
        _wsService.isConnected) {
      _wsService.sendReadReceipt(message.senderId, currentUserId);
    }

    if (state.currentChatUserId != null &&
        (message.senderId == state.currentChatUserId ||
            message.receiverId == state.currentChatUserId)) {
      emit(state.copyWith(
        messages: [...state.messages, message],
      ));
    }

    final newLastMessages = Map<String, Message>.from(state.lastMessages);
    newLastMessages[message.senderId] = message;

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

    if (currentUserId.isNotEmpty) {
      _localStorage.addMessage(currentUserId, message.senderId, message);
      _localStorage.saveConversations(
          currentUserId, updatedConversations, newLastMessages);
    }
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

  void _onReceiveTypingStatus(
    ChatReceiveTypingStatus event,
    Emitter<ChatState> emit,
  ) {
    // Only reflect typing for the currently open chat.
    if (state.currentChatUserId == null ||
        event.senderId != state.currentChatUserId) {
      return;
    }

    emit(state.copyWith(
      isTyping: event.isTyping,
      typingUserId: event.isTyping ? event.senderId : null,
    ));

    if (event.isTyping) {
      _typingClearTimer?.cancel();
      _typingClearTimer = Timer(const Duration(seconds: 4), () {
        if (state.isTyping) {
          emit(state.copyWith(isTyping: false, typingUserId: null));
        }
      });
    } else {
      _typingClearTimer?.cancel();
    }
  }

  void _onReceiveReceipt(
    ChatReceiveReceipt event,
    Emitter<ChatState> emit,
  ) {
    final me = _wsService.currentUserId;
    if (me == null) return;

    final updated = state.messages
        .map((m) => m.senderId == me && m.receiverId == event.peerUserId
            ? m.copyWith(status: event.status)
            : m)
        .toList();
    emit(state.copyWith(messages: updated));
  }

  Future<void> _onLoadConversations(
    ChatLoadConversations event,
    Emitter<ChatState> emit,
  ) async {
    final currentUserId = _wsService.currentUserId;

    if (currentUserId == null) return;

    final localData = _localStorage.getConversations(currentUserId);
    if (localData != null && localData.conversations.isNotEmpty) {
      emit(state.copyWith(
        status: ChatStatus.loaded,
        conversations: localData.conversations,
        lastMessages: localData.lastMessages,
      ));
    } else if (state.conversations.isEmpty) {
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

        if (conv['last_message'] != null) {
          final lastMsg =
              Message.fromJson(conv['last_message'] as Map<String, dynamic>);
          lastMessages[user.id] = lastMsg;
        }
      }

      await _localStorage.saveConversations(
          currentUserId, conversations, lastMessages);
      await _localStorage.setLastSyncTime(currentUserId);

      emit(state.copyWith(
        status: ChatStatus.loaded,
        conversations: conversations,
        lastMessages: lastMessages,
      ));
    } catch (e) {
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
      final users = results
          .map((json) => User.fromJson(json as Map<String, dynamic>))
          .toList();

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

  Future<void> _onDeleteMessage(
    ChatDeleteMessage event,
    Emitter<ChatState> emit,
  ) async {
    try {
      await _apiClient.deleteMessage(event.messageId);

      final updatedMessages =
          state.messages.where((m) => m.id != event.messageId).toList();

      final updatedLastMessages = Map<String, Message>.from(state.lastMessages);
      if (state.lastMessages[event.otherUserId]?.id == event.messageId) {
        final remaining = updatedMessages
            .where((m) =>
                m.senderId == event.otherUserId ||
                m.receiverId == event.otherUserId)
            .toList();
        if (remaining.isNotEmpty) {
          updatedLastMessages[event.otherUserId] = remaining.last;
        } else {
          updatedLastMessages.remove(event.otherUserId);
        }
      }

      emit(state.copyWith(
        messages: updatedMessages,
        lastMessages: updatedLastMessages,
      ));
    } catch (e) {
      emit(state.copyWith(
        errorMessage: 'Failed to delete message: $e',
      ));
    }
  }

  void _onChatReset(
    ChatReset event,
    Emitter<ChatState> emit,
  ) {
    emit(const ChatState());
  }

  @override
  Future<void> close() {
    _messageSubscription?.cancel();
    _typingSubscription?.cancel();
    _statusSubscription?.cancel();
    return super.close();
  }
}
