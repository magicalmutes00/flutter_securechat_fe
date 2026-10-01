import 'dart:async';
import 'dart:io';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/models/message_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/services/api_client.dart';
import '../../../data/services/in_app_notification_service.dart';
import '../../../data/services/local_storage_service.dart';
import '../../../data/services/media_preparation_service.dart';
import '../../../data/services/websocket_service.dart';
import 'chat_event.dart';
import 'chat_state.dart';

/// Internal: performs the network dispatch for a text message whose
/// optimistic bubble was already rendered. Never dispatched by UI directly —
/// [_onSendTextMessage] renders first, then either adds this immediately or
/// holds it until a quoted `temp_…` bubble resolves to a server id.
class _DispatchHeldText extends ChatEvent {
  final String receiverId;
  final String content;

  /// Resolved server id of the quoted message, or null (plain send, or the
  /// quoted bubble never acked and the hold expired).
  final String? replyToId;
  final String tempId;

  const _DispatchHeldText({
    required this.receiverId,
    required this.content,
    this.replyToId,
    required this.tempId,
  });

  @override
  List<Object?> get props => [receiverId, content, replyToId, tempId];
}

/// Internal: WS dispatch for a file message whose media is already uploaded
/// and rendered optimistically (same hold semantics as text).
class _DispatchHeldFile extends ChatEvent {
  final String receiverId;
  final String messageType;
  final String fileUrl;
  final String? fileName;
  final int? fileSize;
  final String? mediaType;

  final String? replyToId;
  final String tempId;

  const _DispatchHeldFile({
    required this.receiverId,
    required this.messageType,
    required this.fileUrl,
    this.fileName,
    this.fileSize,
    this.mediaType,
    this.replyToId,
    required this.tempId,
  });

  @override
  List<Object?> get props => [
        receiverId,
        messageType,
        fileUrl,
        fileName,
        fileSize,
        mediaType,
        replyToId,
        tempId,
      ];
}

/// Human-readable reason for a send-pipeline failure. The raw exception is
/// deliberately not shown: Dio's generic "status code of 500" text sent users
/// down the wrong path. Machine-readable server codes arrive separately and
/// will plug into this same mapping.
String sendFailureReason(Object e) {
  if (e is MediaValidationException) return e.message;
  // Coded server failures: the backend names the exact problem, so the
  // bubble can too (e.g. "too large" instead of "status code of 413").
  if (e is ApiException) return _apiErrorReason(e);
  final text = e.toString().toLowerCase();
  if (text.contains('413') ||
      text.contains('too large') ||
      text.contains('exceeds maximum')) {
    return 'That file is too large to send.';
  }
  if (text.contains('socketexception') ||
      text.contains('connection') ||
      text.contains('network is unreachable') ||
      text.contains('host lookup') ||
      text.contains('timed out') ||
      text.contains('timeout')) {
    return 'No connection — the message was not sent. Try again when you are back online.';
  }
  return 'Could not send that attachment. Tap it to retry.';
}

/// Maps a coded backend failure to bubble wording. Unknown codes fall back
/// to the server's own message — it names the problem better than a generic
/// retry line, and the request id in the logs ties it to the exact failure.
String _apiErrorReason(ApiException e) {
  switch (e.code) {
    case 'file_too_large':
      return 'That file is too large to send.';
    case 'extension_not_allowed':
      return "That file type can't be sent.";
    case 'content_mismatch':
      return 'That file looks corrupt — try picking it again.';
    case 'no_file':
    case 'missing_boundary':
    case 'invalid_content_type':
      return 'The upload was malformed. Tap to retry.';
    case 'unauthorized':
      return 'Your session expired — please log in again.';
    case 'upload_failed':
    case 'internal_error':
      return 'The server failed to handle that file. Tap to retry.';
  }
  if (e.statusCode == 413) return 'That file is too large to send.';
  if (e.statusCode == 401) {
    return 'Your session expired — please log in again.';
  }
  return e.message;
}

/// History-load merge rule for one message id: an incoming row with content
/// heals a cached row that has none; otherwise the cached row wins so a page
/// re-fetch never wipes known-good local state (including optimistic temp
/// bubbles, which resolve via the ack swap, never here).
Message mergeHistoryMessage(Message existing, Message incoming) {
  if (existing.content.isEmpty && incoming.content.isNotEmpty) {
    return incoming;
  }
  return existing;
}

/// Merges a newly fetched history page into the locally cached conversation.
///
/// Server fetches are pages, not replacements: rows already cached (for
/// example older messages outside this page or optimistic bubbles) are
/// retained, and per-id conflicts use [mergeHistoryMessage]. The result is
/// chronological so it can be persisted and rendered directly.
List<Message> mergeHistoryMessages(
  List<Message> existing,
  List<Message> incoming,
) {
  final merged = List<Message>.of(existing);
  final indexById = <String, int>{};
  for (var i = 0; i < merged.length; i++) {
    indexById.putIfAbsent(merged[i].id, () => i);
  }
  for (final message in incoming) {
    final index = indexById[message.id];
    if (index == null) {
      indexById[message.id] = merged.length;
      merged.add(message);
    } else {
      merged[index] = mergeHistoryMessage(merged[index], message);
    }
  }
  merged.sort((a, b) => a.createdAt.compareTo(b.createdAt));
  return merged;
}

/// Extracts the hosted file id from a server file URL (`/api/files/<id>`).
/// Returns null for local paths and anything else — only server URLs are
/// ever passed to the file-delete endpoint.
String? fileIdOfUrl(String? url) {
  const prefix = '/api/files/';
  if (url == null || !url.startsWith(prefix)) return null;
  final id = url.substring(prefix.length);
  if (id.isEmpty || id.contains('/')) return null;
  return id;
}

class ChatBloc extends Bloc<ChatEvent, ChatState> {
  final ApiClient _apiClient = ApiClient();
  final WebSocketService _wsService = WebSocketService();
  final LocalStorageService _localStorage = LocalStorageService();

  StreamSubscription? _messageSubscription;
  StreamSubscription? _typingSubscription;
  StreamSubscription? _statusSubscription;
  Timer? _typingClearTimer;

  /// Sends held until a quoted optimistic bubble is acked: the server can
  /// only link real message ids. Keyed by the quoted `temp_…` id; flushed
  /// with the real server id by [_swapTempWithServer], or without the link
  /// when the hold expires (quoted bubble never acked — e.g. its own send
  /// failed and was rolled back).
  final Map<String, List<ChatEvent Function(String?)>> _heldSends = {};

  /// Server file URL (`/api/files/…`) → optimistic temp id, registered when a
  /// file dispatch goes out and consumed by the ack. Lets the ack swap the
  /// exact bubble instead of guessing the oldest temp when several uploads
  /// are in flight at once.
  final Map<String, String> _pendingFileAck = {};

  static bool _isTempId(String? id) => id != null && id.startsWith('temp_');

  /// Temp ids have no server meaning (the server rejects them via UUID
  /// validation), so never put them on the wire.
  static String? _serverReplyId(String? replyToId) =>
      _isTempId(replyToId) ? null : replyToId;

  void _holdUntilQuotedAcked(
      String tempQuoteId, ChatEvent Function(String?) build) {
    _heldSends.putIfAbsent(tempQuoteId, () => []).add(build);
    Timer(const Duration(seconds: 30), () {
      if (isClosed) return;
      final waiting = _heldSends.remove(tempQuoteId);
      if (waiting == null) return;
      for (final buildEvent in waiting) {
        add(buildEvent(null));
      }
    });
  }

  ChatBloc() : super(const ChatState()) {
    on<ChatLoadMessages>(_onLoadMessages);
    on<ChatSendTextMessage>(_onSendTextMessage);
    on<ChatSendFileMessage>(_onSendFileMessage);
    on<_DispatchHeldText>(_onDispatchHeldText);
    on<_DispatchHeldFile>(_onDispatchHeldFile);
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
    on<ChatClearError>(_onChatClearError);
    on<ChatRetrySend>(_onChatRetrySend);

    _subscribeToWebSocket();
  }

  void _subscribeToWebSocket() {
    // Incoming plaintext messages, forwarded by InAppNotificationService.
    _messageSubscription =
        InAppNotificationService.instance.messageStream.listen((message) {
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
      // Only text is ever queued: attachments use failed-bubble + manual
      // retry. Anything else is dropped from the queue so it can never send
      // as a broken message.
      if (message.messageType != AppConstants.messageTypeText) {
        await _localStorage.removeFromOutbox(currentUserId, message.id);
        continue;
      }
      try {
        final sent = await _apiClient.sendMessage({
          'receiver_id': message.receiverId,
          'message_type': message.messageType,
          'content': message.content,
          'reply_to_id': _serverReplyId(message.replyToId),
        });
        await _localStorage.removeFromOutbox(currentUserId, message.id);
        // Swap the queued temp bubble for the server row when it is on
        // screen, so the outbox flush is visible without a reload.
        final serverId = sent['id'] as String? ?? sent['_id'] as String?;
        if (serverId != null && serverId.isNotEmpty) {
          await _swapTempWithServer(
            tempId: message.id,
            serverJson: sent,
            currentUserId: currentUserId,
            // _swapTempWithServer needs an emitter; when flushing outside an
            // event handler there is none, so update state directly.
            emit: null,
          );
        }
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
      emit(state.copyWith(
        status: ChatStatus.loaded,
        messages: localMessages,
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

      // Merge with the latest local cache instead of replacing it: the
      // server returns one page, and replacing the conversation would discard
      // older rows that the next page can no longer recover.
      final displayable = newMessages;
      final latestLocalMessages =
          _localStorage.getMessages(currentUserId, event.userId);
      await _localStorage.saveMessages(
        currentUserId,
        event.userId,
        mergeHistoryMessages(latestLocalMessages, displayable),
      );

      final allMessages = [...state.messages];
      for (final msg in displayable) {
        final idx = allMessages.indexWhere((m) => m.id == msg.id);
        if (idx == -1) {
          allMessages.add(msg);
        } else {
          allMessages[idx] = mergeHistoryMessage(allMessages[idx], msg);
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
      replyToId: event.replyToId,
      status: 'sent',
      createdAt: DateTime.now(),
    );

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

    if (_isTempId(event.replyToId)) {
      // The quoted bubble hasn't been acked yet and temp ids are meaningless
      // to the server: hold the network dispatch until `_swapTempWithServer`
      // resolves it (or the 30s hold expires). The optimistic bubble above
      // already renders the quote, so this is invisible in the UI.
      _holdUntilQuotedAcked(
        event.replyToId!,
        (resolved) => _DispatchHeldText(
          receiverId: event.receiverId,
          content: event.content,
          replyToId: resolved,
          tempId: tempMessage.id,
        ),
      );
      return;
    }
    add(_DispatchHeldText(
      receiverId: event.receiverId,
      content: event.content,
      replyToId: _serverReplyId(event.replyToId),
      tempId: tempMessage.id,
    ));
  }

  Future<void> _onDispatchHeldText(
    _DispatchHeldText event,
    Emitter<ChatState> emit,
  ) async {
    final currentUserId = _wsService.currentUserId ?? '';

    // Prefer the socket; any transport failure (not connected, or the
    // socket died mid-send) falls through to REST, then to the outbox.
    var sentLive = false;
    if (_wsService.isConnected) {
      try {
        _wsService.sendMessage(
          receiverId: event.receiverId,
          messageType: AppConstants.messageTypeText,
          content: event.content,
          replyToId: event.replyToId,
        );
        sentLive = true;
      } catch (_) {
        sentLive = false;
      }
    }
    if (!sentLive) {
      // Try the REST fallback; if the device is fully offline, queue the
      // message for delivery once the socket to the server reconnects.
      try {
        final sent = await _apiClient.sendMessage({
          'receiver_id': event.receiverId,
          'message_type': AppConstants.messageTypeText,
          'content': event.content,
          'reply_to_id': event.replyToId,
        });
        await _swapTempWithServer(
          tempId: event.tempId,
          serverJson: sent,
          currentUserId: currentUserId,
          emit: emit,
        );
      } catch (_) {
        if (currentUserId.isNotEmpty) {
          final temp = state.messages.where((m) => m.id == event.tempId);
          if (temp.isNotEmpty) {
            await _localStorage.enqueueOutbox(currentUserId, temp.first);
          }
        }
      }
    }
  }

  Future<void> _onSendFileMessage(
    ChatSendFileMessage event,
    Emitter<ChatState> emit,
  ) async {
    // Shrink photos first: a 12 MP original becomes a bounded JPEG, so the
    // upload moves a fraction of the bytes. Returns the original when
    // conversion is pointless or impossible; the gate below rules on
    // whatever actually uploads. A rejected file gets a snackbar, not a
    // bubble (there is nothing to retry).
    String sendPath = event.filePath;
    try {
      sendPath = await MediaPreparationService.prepareImage(
        filePath: event.filePath,
        messageType: event.messageType,
      );
      await MediaPreparationService.validate(
        filePath: sendPath,
        messageType: event.messageType,
      );
    } on MediaValidationException catch (e) {
      await MediaPreparationService.deleteTemp(sendPath, event.filePath);
      emit(state.copyWith(
        status: ChatStatus.loaded,
        errorMessage: e.message,
      ));
      return;
    }

    emit(state.copyWith(
      status: ChatStatus.sending,
      pendingUploads: state.pendingUploads + 1,
    ));

    final currentUserId = _wsService.currentUserId ?? '';

    // Render the optimistic bubble FIRST from the local file so the sender
    // sees instant feedback while the upload runs. A failure later
    // marks this same bubble failed (with a retry affordance) instead of
    // replacing the whole conversation with a full-screen error.
    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    final tempMessage = Message(
      id: tempId,
      senderId: currentUserId,
      receiverId: event.receiverId,
      messageType: event.messageType,
      content: '',
      replyToId: event.replyToId,
      filePath: event.filePath,
      fileName: event.filePath.split('/').last.split('\\').last,
      status: 'sending',
      createdAt: DateTime.now(),
    );

    final newLastMessages = Map<String, Message>.from(state.lastMessages);
    newLastMessages[event.receiverId] = tempMessage;
    final updatedConversations = Map<String, User>.from(state.conversations);
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

    try {
      // Upload the prepared bytes directly.
      // The compressor's copy has served its purpose once uploaded.
      var lastEmittedProgress = 0.0;
      Map<String, dynamic> uploadResult;
      try {
        uploadResult = await _apiClient.uploadFile(
          sendPath,
          event.messageType,
          // A converted photo takes the original stem with a .jpg extension
          // so the server's extension allow-list sees what the bytes are.
          filename:
              MediaPreparationService.uploadFilename(event.filePath, sendPath),
          onSendProgress: (sent, total) {
            if (isClosed || total <= 0) return;
            final progress = (sent / total).clamp(0.0, 1.0);
            if (progress - lastEmittedProgress < 0.05 && progress < 1.0) {
              return;
            }
            lastEmittedProgress = progress;
            final ticked = state.messages
                .map((m) =>
                    m.id == tempId ? m.copyWith(uploadProgress: progress) : m)
                .toList();
            emit(state.copyWith(messages: ticked));
          },
        );
      } finally {
        // The server has the bytes — or the upload died trying. Either way
        // our transient compressed copy goes; a retry re-runs the pipeline
        // from the original local file.
        await MediaPreparationService.deleteTemp(sendPath, event.filePath);
      }

      if (uploadResult['success'] != true) {
        throw Exception(uploadResult['message'] ?? 'Upload failed');
      }
      final fileUrl = uploadResult['url'] as String?;
      if (fileUrl == null || fileUrl.isEmpty) {
        throw Exception('Upload failed');
      }

      // The upload succeeded: enrich the optimistic bubble with the hosted
      // file metadata and drop the progress ring. It keeps its temp id
      // until the ack swap.
      await _updateTempBubble(
        emit,
        currentUserId: currentUserId,
        receiverId: event.receiverId,
        tempId: tempId,
        update: (m) => m.copyWith(
          fileName: uploadResult['file_name'] as String?,
          fileSize: (uploadResult['file_size'] as num?)?.toInt(),
          mediaType: uploadResult['media_type'] as String?,
          clearUploadProgress: true,
        ),
      );

      _DispatchHeldFile buildDispatch(String? resolvedReplyId) {
        return _DispatchHeldFile(
          receiverId: event.receiverId,
          messageType: event.messageType,
          fileUrl: fileUrl,
          fileName: uploadResult['file_name'] as String?,
          fileSize: (uploadResult['file_size'] as num?)?.toInt(),
          mediaType: uploadResult['media_type'] as String?,
          replyToId: resolvedReplyId,
          tempId: tempId,
        );
      }

      if (_isTempId(event.replyToId)) {
        // Same hold semantics as text: the quoted bubble has no server id yet.
        _holdUntilQuotedAcked(event.replyToId!, buildDispatch);
      } else {
        add(buildDispatch(_serverReplyId(event.replyToId)));
      }

      _finishUploadSlot(emit);
    } catch (e) {
      _finishUploadSlot(emit);
      await MediaPreparationService.deleteTemp(sendPath, event.filePath);
      // Mark only this bubble failed and surface the reason via snackbar —
      // the conversation stays visible with a retry affordance.
      await _markSendFailed(
        emit,
        currentUserId: currentUserId,
        receiverId: event.receiverId,
        tempId: tempId,
        reason: sendFailureReason(e),
      );
    }
  }

  /// Applies [update] to the optimistic bubble [tempId] in state, in the
  /// conversation preview when it points at it, and in the local cache copy
  /// (so a reopened chat never shows a stale pre-update version).
  Future<void> _updateTempBubble(
    Emitter<ChatState> emit, {
    required String currentUserId,
    required String receiverId,
    required String tempId,
    required Message Function(Message) update,
  }) async {
    final existing = state.messages.where((m) => m.id == tempId);
    if (existing.isEmpty) return;
    final updated = update(existing.first);

    final messages =
        state.messages.map((m) => m.id == tempId ? updated : m).toList();
    final newLastMessages = Map<String, Message>.from(state.lastMessages);
    if (newLastMessages[receiverId]?.id == tempId) {
      newLastMessages[receiverId] = updated;
    }

    emit(state.copyWith(
      status: ChatStatus.loaded,
      messages: messages,
      lastMessages: newLastMessages,
    ));

    if (currentUserId.isNotEmpty) {
      await _localStorage.replaceMessage(
          currentUserId, receiverId, tempId, updated);
      await _localStorage.saveConversations(
          currentUserId, state.conversations, newLastMessages);
    }
  }

  /// Releases one upload slot. Always paired with the increment at the top
  /// of [_onSendFileMessage], on success and on failure alike.
  void _finishUploadSlot(Emitter<ChatState> emit) {
    emit(state.copyWith(
      status: ChatStatus.loaded,
      pendingUploads: state.pendingUploads > 0 ? state.pendingUploads - 1 : 0,
    ));
  }

  /// Marks one optimistic bubble failed without disturbing the rest of the
  /// conversation. The bubble keeps its local preview and gains a retry
  /// affordance; [reason] is shown once via snackbar.
  Future<void> _markSendFailed(
    Emitter<ChatState> emit, {
    required String currentUserId,
    required String receiverId,
    required String tempId,
    required String reason,
  }) async {
    await _updateTempBubble(
      emit,
      currentUserId: currentUserId,
      receiverId: receiverId,
      tempId: tempId,
      // A frozen progress ring on a dead bubble would imply it is still
      // moving — clear it along with the failure marking.
      update: (m) => m.copyWith(
        status: 'failed',
        clearUploadProgress: true,
      ),
    );
    emit(state.copyWith(errorMessage: reason));
  }

  Future<void> _onChatClearError(
    ChatClearError event,
    Emitter<ChatState> emit,
  ) async {
    if (state.errorMessage == null) return;
    emit(state.copyWith(clearErrorMessage: true));
  }

  Future<void> _onChatRetrySend(
    ChatRetrySend event,
    Emitter<ChatState> emit,
  ) async {
    final matches = state.messages.where((m) => m.id == event.tempId);
    if (matches.isEmpty) return;
    final failed = matches.first;
    final currentUserId = _wsService.currentUserId ?? '';
    if (!failed.isFailed || failed.senderId != currentUserId) return;

    if (!failed.isTextMessage) {
      // Attachments re-run the whole pipeline from the original local file.
      final path = failed.filePath;
      if (path == null || !(await File(path).exists())) {
        emit(state.copyWith(
          status: ChatStatus.loaded,
          errorMessage: 'The original file is gone — please pick it again.',
        ));
        return;
      }
    }

    // Drop the failed bubble; the re-send renders a fresh optimistic one.
    final messages = state.messages.where((m) => m.id != event.tempId).toList();
    final newLastMessages = Map<String, Message>.from(state.lastMessages);
    newLastMessages.removeWhere((_, m) => m.id == event.tempId);
    emit(state.copyWith(
      status: ChatStatus.loaded,
      messages: messages,
      lastMessages: newLastMessages,
    ));

    if (failed.isTextMessage) {
      add(ChatSendTextMessage(
        receiverId: failed.receiverId,
        content: failed.content,
        replyToId: failed.replyToId,
      ));
    } else {
      add(ChatSendFileMessage(
        receiverId: failed.receiverId,
        filePath: failed.filePath!,
        messageType: failed.messageType,
        replyToId: failed.replyToId,
      ));
    }
  }

  Future<void> _onDispatchHeldFile(
    _DispatchHeldFile event,
    Emitter<ChatState> emit,
  ) async {
    final currentUserId = _wsService.currentUserId ?? '';

    // Prefer the socket; fall through to REST on any transport failure (not
    // connected, or the socket died between upload and dispatch). A dispatch
    // that never reaches the server must never leave a phantom 'sending'
    // bubble behind.
    if (currentUserId.isNotEmpty && _wsService.isConnected) {
      // Remember which bubble this dispatch belongs to so the ack swaps the
      // exact one (not merely the oldest temp) when uploads overlap.
      _pendingFileAck[event.fileUrl] = event.tempId;

      try {
        _wsService.sendMessage(
          receiverId: event.receiverId,
          messageType: event.messageType,
          content: '',
          fileUrl: event.fileUrl,
          fileName: event.fileName,
          fileSize: event.fileSize,
          mediaType: event.mediaType,
          replyToId: event.replyToId,
        );
        return;
      } catch (_) {
        // Lost the race: drop the registration and try REST below.
        _pendingFileAck.remove(event.fileUrl);
      }
    }

    // Single REST delivery carrying the already-uploaded file.
    // Files are never queued: a failed file send becomes a failed bubble
    // with manual retry from the original local file.
    try {
      final sent = await _apiClient.sendMessage({
        'receiver_id': event.receiverId,
        'message_type': event.messageType,
        'content': '',
        'file_url': event.fileUrl,
        'file_name': event.fileName,
        'file_size': event.fileSize,
        'media_type': event.mediaType,
        'reply_to_id': event.replyToId,
      });
      await _swapTempWithServer(
        tempId: event.tempId,
        serverJson: sent,
        currentUserId: currentUserId,
        emit: emit,
      );
    } catch (e) {
      // Fully offline (or the server refused): the bytes are already hosted,
      // but nothing was sent. Failed bubble with retry — never auto-queued.
      await _markSendFailed(
        emit,
        currentUserId: currentUserId,
        receiverId: event.receiverId,
        tempId: event.tempId,
        reason: sendFailureReason(e),
      );
      // Best-effort orphan cleanup: the hosted bytes belong to no message,
      // and a retry uploads fresh bytes anyway. Offline this throws —
      // the orphan then waits for a server-side sweep.
      final orphanId = fileIdOfUrl(event.fileUrl);
      if (orphanId != null) {
        try {
          await _apiClient.deleteFile(orphanId);
        } catch (_) {}
      }
    }
  }

  /// Swaps the optimistic temp bubble for the server-acknowledged message.
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

    // Prefer the exact bubble this ack belongs to (registered at dispatch);
    // fall back to the oldest-temp scan for sends that predate the map.
    final ackTempId = server.filePath == null
        ? null
        : _pendingFileAck.remove(server.filePath);
    await _swapTempWithServer(
      tempId: ackTempId,
      serverJson: event.serverMessage,
      currentUserId: currentUserId,
      emit: emit,
    );
  }

  /// Replaces the optimistic temp bubble ([tempId], or the oldest temp bubble
  /// for the receiver when null) with the server-acknowledged message, in
  /// state and in the local cache.
  Future<void> _swapTempWithServer({
    required String? tempId,
    required Map<String, dynamic> serverJson,
    required String currentUserId,
    required Emitter<ChatState>? emit,
  }) async {
    late final Message server;
    try {
      server = Message.fromJson(serverJson);
    } catch (_) {
      return;
    }
    if (server.id.isEmpty) return;

    final resolved = server;

    final messages = [...state.messages];
    var swappedId = tempId;
    if (swappedId == null) {
      for (final m in messages) {
        // Failed bubbles keep their temp ids but were never sent — an ack
        // must never swap one of those for an unrelated server message.
        if (m.id.startsWith('temp_') &&
            m.receiverId == server.receiverId &&
            !m.isFailed) {
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

    if (emit != null) {
      emit(state.copyWith(messages: messages, lastMessages: newLastMessages));
    }

    await _localStorage.replaceMessage(
      currentUserId,
      server.receiverId,
      swappedId,
      resolved,
    );
    await _localStorage.saveConversations(
        currentUserId, state.conversations, newLastMessages);

    // Replies composed against this still-sending bubble were held back; the
    // quoted message finally has a real id, so release the held dispatches.
    // Any other message still pointing at the temp id gets remapped too, so
    // the quote never dangles.
    final held = _heldSends.remove(swappedId);
    if (held != null) {
      for (final build in held) {
        add(build(server.id));
      }
    }
    var remapped = false;
    final remappedMessages = messages.map((m) {
      if (m.replyToId == swappedId) {
        remapped = true;
        return m.copyWith(replyToId: server.id);
      }
      return m;
    }).toList();
    if (remapped) {
      if (emit != null) {
        emit(state.copyWith(messages: remappedMessages));
      }
      await _localStorage.saveMessages(
          currentUserId, server.receiverId, remappedMessages);
    }
  }

  Future<void> _onReceiveMessage(
    ChatReceiveMessage event,
    Emitter<ChatState> emit,
  ) async {
    var message = event.message;
    final currentUserId = _wsService.currentUserId ?? '';

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
          unreadCounts[user.id] = (conv['unread_count'] as num?)?.toInt() ?? 0;
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
    // Capture the hosted URL before the row disappears: the server deletes
    // the row's own reference, and we then ask it to drop the asset too
    // when nothing else references it.
    final doomed = state.messages.where((m) => m.id == event.messageId);
    final doomedFileId =
        doomed.isEmpty ? null : fileIdOfUrl(doomed.first.filePath);
    try {
      await _apiClient.deleteMessage(event.messageId);
      if (doomedFileId != null) {
        try {
          await _apiClient.deleteFile(doomedFileId);
        } catch (_) {
          // Cleanup is best-effort; the message itself is already gone.
        }
      }

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
    _heldSends.clear();
    _pendingFileAck.clear();
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
