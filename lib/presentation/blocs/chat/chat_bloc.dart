import 'dart:async';
import 'dart:convert';
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
    on<ChatServerMessageAcked>(_onServerMessageAcked);
    on<ChatUpdateMessageStatus>(_onUpdateMessageStatus);
    on<ChatSendTypingStatus>(_onSendTypingStatus);
    on<ChatReceiveTypingStatus>(_onReceiveTypingStatus);
    on<ChatReceiveReceipt>(_onReceiveReceipt);
    on<ChatLoadConversations>(_onLoadConversations);
    on<ChatMarkConversationRead>(_onMarkConversationRead);
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
        // Commit the staged outgoing plaintext under the server id so our
        // own message resolves from history instead of failing to decrypt.
        final payload = data['data'];
        if (payload is Map<String, dynamic>) {
          add(ChatServerMessageAcked(payload));
        }
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

        final sent = await _apiClient.sendMessage({
          'receiver_id': message.receiverId,
          'message_type': message.messageType,
          'content': usesSignal ? '' : message.content,
          'encryption': encrypted['encryption'] as String? ?? 'none',
          'cipher_type': encrypted['cipher_type'],
          'cipher_body': encrypted['cipher_body'],
        });
        // Remember our plaintext under the server id: history fetch can
        // never Signal-decrypt our own messages (no session with ourselves).
        final serverId = sent['id'] as String? ?? sent['_id'] as String?;
        if (usesSignal && serverId != null && serverId.isNotEmpty) {
          E2eeService.instance.cacheOwnPlaintext(serverId, message.content);
        }
        await _localStorage.removeFromOutbox(currentUserId, message.id);
      } catch (_) {
        // Keep the message queued; a later reconnect will retry it.
      }
    }
  }

  /// Legacy E2EE-era messages carry ciphertext instead of content. Without
  /// the encryption stack they can never be decrypted, so render an honest
  /// notice bubble instead of an empty one.
  Message _asDisplayable(Message m) {
    if (m.content.isEmpty &&
        (m.encryption == 'signal' || m.encryption == 'sgkey')) {
      return m.copyWith(
        content: '🔒 Encrypted message from before encryption was removed',
        encryption: 'none',
        cipherBody: null,
        cipherType: null,
      );
    }
    return m;
  }

  Future<void> _onLoadMessages(
    ChatLoadMessages event,
    Emitter<ChatState> emit,
  ) async {
    final currentUserId = _wsService.currentUserId;

    if (currentUserId == null) return;

    // Opening a chat marks it read: clear the badge optimistically and
    // notify the server so `unread_count` zeroes (covers messages that
    // arrived before the chat was opened).
    final openedUnread = Map<String, int>.from(state.unreadCounts);
    openedUnread[event.userId] = 0;
    if (_wsService.isConnected) {
      _wsService.sendReadReceipt(event.userId, currentUserId);
    }

    emit(state.copyWith(
      status: ChatStatus.loading,
      currentChatUserId: event.userId,
      unreadCounts: openedUnread,
    ));

    final localMessages =
        _localStorage.getMessages(currentUserId, event.userId);

    if (localMessages.isNotEmpty && !event.refresh) {
      // Locally cached messages are stored decrypted, but re-decrypt defensively
      // in case a previous session persisted ciphertext.
      final decryptedLocal = <Message>[];
      for (final m in localMessages) {
        decryptedLocal.add(_asDisplayable(await E2eeService.instance
            .decryptMessage(m, currentUserId: currentUserId)));
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
      final localById = {for (final m in localMessages) m.id: m};
      final decryptedMessages = <Message>[];
      for (final m in newMessages) {
        var decrypted = _asDisplayable(await E2eeService.instance
            .decryptMessage(m, currentUserId: currentUserId));
        // Belt-and-braces: never let a server re-fetch wipe a known-good
        // local plaintext (e.g. our own message sent from another device
        // whose staged plaintext is gone) with an empty/placeholder bubble.
        if (decrypted.senderId == currentUserId &&
            (decrypted.content.isEmpty ||
                decrypted.content.startsWith('🔒'))) {
          final local = localById[decrypted.id];
          if (local != null &&
              local.content.isNotEmpty &&
              !local.content.startsWith('🔒')) {
            decrypted = local;
          }
        }
        decryptedMessages.add(decrypted);
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
        // Stage now; the server id arrives via `message_sent` and the ack
        // handler commits it (socket delivery preserves send order).
        if (usesSignal) {
          E2eeService.instance
              .stageOwnPlaintext(event.receiverId, event.content);
        }
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
          final sent = await _apiClient.sendMessage({
            'receiver_id': event.receiverId,
            'message_type': tempMessage.messageType,
            'content': usesSignal ? '' : event.content,
            'encryption': encrypted['encryption'] as String? ?? 'none',
            'cipher_type': encrypted['cipher_type'],
            'cipher_body': encrypted['cipher_body'],
          });
          final serverId = sent['id'] as String? ?? sent['_id'] as String?;
          if (usesSignal && serverId != null && serverId.isNotEmpty) {
            E2eeService.instance.cacheOwnPlaintext(serverId, event.content);
            await _swapTempWithServer(
              tempId: tempMessage.id,
              serverJson: sent,
              plaintext: event.content,
              currentUserId: currentUserId,
              emit: emit,
            );
          }
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

      if (uploadResult['success'] != true) {
        throw Exception(uploadResult['message'] ?? 'Upload failed');
      }
      final fileUrl = uploadResult['url'] as String?;
      if (fileUrl == null || fileUrl.isEmpty) {
        throw Exception('Upload failed');
      }

      // Deliver the media key inside a Signal-encrypted envelope so the
      // server only ever sees the ciphertext blob.
      final envelope = {
        'k': encryptedMedia.keyB64,
        'iv': encryptedMedia.nonceB64,
        'text': '',
      };
      final crypto = await E2eeService.instance.encryptEnvelopeForPeer(
        currentUserId: currentUserId,
        receiverId: event.receiverId,
        envelope: envelope,
      );

      // Optimistic bubble rendering the LOCAL file so the sender sees it
      // instantly; the server echo later swaps in the hosted version.
      final tempMessage = Message(
        id: 'temp_${DateTime.now().millisecondsSinceEpoch}',
        senderId: currentUserId,
        receiverId: event.receiverId,
        messageType: event.messageType,
        content: '',
        filePath: event.filePath,
        fileName: uploadResult['file_name'] as String?,
        fileSize: (uploadResult['file_size'] as num?)?.toInt(),
        mediaType: uploadResult['media_type'] as String?,
        status: 'sent',
        createdAt: DateTime.now(),
      );

      final newLastMessages =
          Map<String, Message>.from(state.lastMessages);
      newLastMessages[event.receiverId] = tempMessage;
      final updatedConversations =
          Map<String, User>.from(state.conversations);
      if (!updatedConversations.containsKey(event.receiverId)) {
        updatedConversations[event.receiverId] = User(
          id: event.receiverId,
          displayName: null,
          email: null,
          phone: null,
          avatarUrl: null,
          isOnline: false,
          lastSeen: null,
        );
      }

      emit(state.copyWith(
        status: ChatStatus.loaded,
        messages: [...state.messages, tempMessage],
        lastMessages: newLastMessages,
        conversations: updatedConversations,
      ));

      if (currentUserId.isNotEmpty) {
        await _localStorage.addMessage(
            currentUserId, event.receiverId, tempMessage);
        await _localStorage.saveConversations(
            currentUserId, updatedConversations, newLastMessages);
      }

      if (_wsService.isConnected) {
        // Stage the envelope so our own history fetch resolves instead of
        // showing "Unable to decrypt media" (committed on message_sent).
        E2eeService.instance.stageOwnPlaintext(
            event.receiverId, jsonEncode(envelope));
        _wsService.sendMessage(
          receiverId: event.receiverId,
          messageType: event.messageType,
          content: '',
          fileUrl: fileUrl,
          fileName: tempMessage.fileName,
          fileSize: tempMessage.fileSize,
          mediaType: tempMessage.mediaType,
          encryption: crypto['encryption'] as String? ?? 'none',
          cipherType: crypto['cipher_type'] as int?,
          cipherBody: crypto['cipher_body'] as String?,
        );
      }

      emit(state.copyWith(status: ChatStatus.loaded));
    } catch (e) {
      emit(state.copyWith(
        status: ChatStatus.error,
        errorMessage: e.toString(),
      ));
    }
  }

  /// Commits the staged outgoing plaintext under the server id from a
  /// `message_sent` ack and swaps the optimistic temp bubble for the real
  /// server message (carrying our plaintext, crypto stripped).
  Future<void> _onServerMessageAcked(
    ChatServerMessageAcked event,
    Emitter<ChatState> emit,
  ) async {
    final currentUserId = _wsService.currentUserId;
    if (currentUserId == null || currentUserId.isEmpty) return;

    late final Message server;
    try {
      server = Message.fromJson(event.serverMessage);
    } catch (_) {
      return;
    }
    if (server.senderId != currentUserId) return;

    final plaintext = E2eeService.instance
        .commitOwnPlaintext(server.id, server.receiverId);
    await _swapTempWithServer(
      tempId: null,
      serverJson: event.serverMessage,
      plaintext: plaintext ?? '',
      currentUserId: currentUserId,
      emit: emit,
    );
  }

  /// Replaces the optimistic temp bubble ([tempId], or the oldest temp bubble
  /// for the receiver when null) with the server-acknowledged message showing
  /// [plaintext], in state and in the local cache.
  Future<void> _swapTempWithServer({
    required String? tempId,
    required Map<String, dynamic> serverJson,
    required String plaintext,
    required String currentUserId,
    required Emitter<ChatState> emit,
  }) async {
    late final Message server;
    try {
      server = Message.fromJson(serverJson);
    } catch (_) {
      return;
    }
    if (server.id.isEmpty) return;

    final resolved = _asDisplayable(server.copyWith(
      content: plaintext.isNotEmpty ? plaintext : server.content,
      encryption: 'none',
      cipherBody: null,
      cipherType: null,
    ));

    final messages = [...state.messages];
    var swappedId = tempId;
    if (swappedId == null) {
      for (final m in messages) {
        if (m.id.startsWith('temp_') && m.receiverId == server.receiverId) {
          swappedId = m.id;
          break;
        }
      }
    }
    if (swappedId == null) return;

    final idx = messages.indexWhere((m) => m.id == swappedId);
    if (idx == -1) return;
    messages[idx] = resolved;

    final newLastMessages = Map<String, Message>.from(state.lastMessages);
    if (newLastMessages[server.receiverId]?.id == swappedId) {
      newLastMessages[server.receiverId] = resolved;
    }

    emit(state.copyWith(messages: messages, lastMessages: newLastMessages));

    await _localStorage.replaceMessage(
      currentUserId,
      server.receiverId,
      swappedId,
      resolved,
    );
    await _localStorage.saveConversations(
        currentUserId, state.conversations, newLastMessages);
  }

  Future<void> _onReceiveMessage(
    ChatReceiveMessage event,
    Emitter<ChatState> emit,
  ) async {
    var message = event.message;
    final currentUserId = _wsService.currentUserId ?? '';

    // Decrypt Signal-encrypted messages before display/storage. The legacy
    // notice mapping runs after, as a safety net for undecryptable history.
    message = _asDisplayable(await E2eeService.instance
        .decryptMessage(message, currentUserId: currentUserId));

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

    // Badge accounting: only messages arriving while their chat is closed
    // increment the count (a receipt was already sent for the open chat).
    final counts = Map<String, int>.from(state.unreadCounts);
    if (isViewingThisChat) {
      counts[message.senderId] = 0;
    } else {
      counts[message.senderId] = (counts[message.senderId] ?? 0) + 1;
    }

    emit(state.copyWith(
      lastMessages: newLastMessages,
      conversations: updatedConversations,
      unreadCounts: counts,
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
      final unreadCounts = <String, int>{};

      for (final conv in conversationsData) {
        final userData = conv['user'] as Map<String, dynamic>;
        final user = User.fromJson(userData);
        conversations[user.id] = user;

        if (conv['last_message'] != null) {
          final lastMsg =
              Message.fromJson(conv['last_message'] as Map<String, dynamic>);
          lastMessages[user.id] = lastMsg;
        }

        // The server is the source of truth — except for the chat currently
        // on screen, whose optimistic zero must survive a refresh racing
        // the read receipt.
        if (state.currentChatUserId == user.id) {
          unreadCounts[user.id] = 0;
        } else {
          unreadCounts[user.id] =
              (conv['unread_count'] as num?)?.toInt() ?? 0;
        }
      }

      await _localStorage.saveConversations(
          currentUserId, conversations, lastMessages);
      await _localStorage.setLastSyncTime(currentUserId);

      emit(state.copyWith(
        status: ChatStatus.loaded,
        conversations: conversations,
        lastMessages: lastMessages,
        unreadCounts: unreadCounts,
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

  void _onMarkConversationRead(
    ChatMarkConversationRead event,
    Emitter<ChatState> emit,
  ) {
    final unread = Map<String, int>.from(state.unreadCounts);
    unread[event.peerId] = 0;
    emit(state.copyWith(unreadCounts: unread));

    final me = _wsService.currentUserId;
    if (me != null && _wsService.isConnected) {
      _wsService.sendReadReceipt(event.peerId, me);
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
