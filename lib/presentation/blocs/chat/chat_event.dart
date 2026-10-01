import 'package:equatable/equatable.dart';
import '../../../data/models/message_model.dart';

abstract class ChatEvent extends Equatable {
  const ChatEvent();

  @override
  List<Object?> get props => [];
}

class ChatLoadMessages extends ChatEvent {
  final String userId;
  final bool refresh;

  const ChatLoadMessages({required this.userId, this.refresh = false});

  @override
  List<Object?> get props => [userId, refresh];
}

class ChatSendTextMessage extends ChatEvent {
  final String receiverId;
  final String content;

  /// Id of the quoted message. Null for a plain send. May point at a still-
  /// sending optimistic bubble (`temp_…`); the bloc holds the network dispatch
  /// until the quoted message resolves to a server id.
  final String? replyToId;

  const ChatSendTextMessage({
    required this.receiverId,
    required this.content,
    this.replyToId,
  });

  @override
  List<Object?> get props => [receiverId, content, replyToId];
}

class ChatSendFileMessage extends ChatEvent {
  final String receiverId;
  final String filePath;
  final String messageType;

  /// Id of the quoted message (see [ChatSendTextMessage.replyToId]).
  final String? replyToId;

  const ChatSendFileMessage({
    required this.receiverId,
    required this.filePath,
    required this.messageType,
    this.replyToId,
  });

  @override
  List<Object?> get props => [receiverId, filePath, messageType, replyToId];
}

class ChatReceiveMessage extends ChatEvent {
  final Message message;

  const ChatReceiveMessage(this.message);

  @override
  List<Object?> get props => [message];
}

class ChatUpdateMessageStatus extends ChatEvent {
  final String messageId;
  final String status;

  const ChatUpdateMessageStatus(
      {required this.messageId, required this.status});

  @override
  List<Object?> get props => [messageId, status];
}

/// The server acknowledged one of our WebSocket sends (`message_sent` carries
/// the full stored message). Commits the staged outgoing plaintext under the
/// server id and swaps the optimistic temp bubble for the real message.
class ChatServerMessageAcked extends ChatEvent {
  final Map<String, dynamic> serverMessage;

  const ChatServerMessageAcked(this.serverMessage);

  @override
  List<Object?> get props => [serverMessage];
}

class ChatSendTypingStatus extends ChatEvent {
  final String receiverId;
  final bool isTyping;

  const ChatSendTypingStatus(
      {required this.receiverId, required this.isTyping});

  @override
  List<Object?> get props => [receiverId, isTyping];
}

class ChatReceiveTypingStatus extends ChatEvent {
  final String senderId;
  final bool isTyping;

  const ChatReceiveTypingStatus({
    required this.senderId,
    required this.isTyping,
  });

  @override
  List<Object?> get props => [senderId, isTyping];
}

class ChatReceiveReceipt extends ChatEvent {
  final String peerUserId;
  final String status;

  const ChatReceiveReceipt({
    required this.peerUserId,
    required this.status,
  });

  @override
  List<Object?> get props => [peerUserId, status];
}

class ChatLoadConversations extends ChatEvent {}

/// Marks a 1:1 conversation as read: clears the local unread badge
/// optimistically and notifies the server (which zeroes `unread_count`).
class ChatMarkConversationRead extends ChatEvent {
  final String peerId;

  const ChatMarkConversationRead(this.peerId);

  @override
  List<Object?> get props => [peerId];
}

class ChatSearchUsers extends ChatEvent {
  final String query;

  const ChatSearchUsers(this.query);

  @override
  List<Object?> get props => [query];
}

class ChatDeleteMessage extends ChatEvent {
  final String messageId;
  final String otherUserId;

  const ChatDeleteMessage({
    required this.messageId,
    required this.otherUserId,
  });

  @override
  List<Object?> get props => [messageId, otherUserId];
}

class ChatReset extends ChatEvent {}

/// Clears a shown [ChatState.errorMessage]. Dispatched by the UI right after
/// displaying the snackbar so an identical follow-up error still triggers
/// the listener's change guard and is never silently swallowed.
class ChatClearError extends ChatEvent {
  const ChatClearError();
}

/// Re-runs the send pipeline for a failed optimistic bubble ([Message.isFailed]).
/// The bubble is dropped and a fresh optimistic send starts from the stored
/// local file/content — the failed attempt is never replayed on the wire.
class ChatRetrySend extends ChatEvent {
  final String tempId;

  const ChatRetrySend({required this.tempId});

  @override
  List<Object?> get props => [tempId];
}
