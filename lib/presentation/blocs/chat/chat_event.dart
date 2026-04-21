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

  const ChatSendTextMessage({required this.receiverId, required this.content});

  @override
  List<Object?> get props => [receiverId, content];
}

class ChatSendFileMessage extends ChatEvent {
  final String receiverId;
  final String filePath;
  final String messageType;

  const ChatSendFileMessage({
    required this.receiverId,
    required this.filePath,
    required this.messageType,
  });

  @override
  List<Object?> get props => [receiverId, filePath, messageType];
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

  const ChatUpdateMessageStatus({required this.messageId, required this.status});

  @override
  List<Object?> get props => [messageId, status];
}

class ChatSendTypingStatus extends ChatEvent {
  final String receiverId;
  final bool isTyping;

  const ChatSendTypingStatus({required this.receiverId, required this.isTyping});

  @override
  List<Object?> get props => [receiverId, isTyping];
}

class ChatLoadConversations extends ChatEvent {}

class ChatSearchUsers extends ChatEvent {
  final String query;

  const ChatSearchUsers(this.query);

  @override
  List<Object?> get props => [query];
}
