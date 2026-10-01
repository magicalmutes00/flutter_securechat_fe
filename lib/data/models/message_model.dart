import 'package:equatable/equatable.dart';

class Message extends Equatable {
  final String id;
  final String senderId;
  final String receiverId;
  final String? groupId;

  // Reply target: id of the quoted message in the same conversation.
  // Resolved client-side from already-decrypted messages; the server stores
  // only this id (never a quoted-text snapshot) so it learns nothing about
  // encrypted content.
  final String? replyToId;
  final String messageType;
  final String content;
  final String? filePath;
  final String? fileName;
  final int? fileSize;
  final String? mediaType;
  final String status;
  final DateTime createdAt;
  final DateTime? updatedAt;

  // E2EE: for encrypted messages `content` is empty and the ciphertext travels
  // in these opaque fields. Local copies store the decrypted text.
  final String encryption;
  final int? cipherType;
  final String? cipherBody;

  // Group sender-key distribution message (first message to a member).
  final String? distribution;

  // Transient AES-256-GCM media keys, populated in-memory after decrypting the
  // media envelope. Never serialized to the server or local cache.
  final String? mediaKey;
  final String? mediaNonce;

  const Message({
    required this.id,
    required this.senderId,
    required this.receiverId,
    this.groupId,
    this.replyToId,
    required this.messageType,
    required this.content,
    this.filePath,
    this.fileName,
    this.fileSize,
    this.mediaType,
    required this.status,
    required this.createdAt,
    this.updatedAt,
    this.encryption = 'none',
    this.cipherType,
    this.cipherBody,
    this.distribution,
    this.mediaKey,
    this.mediaNonce,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'] as String? ?? json['_id'] as String? ?? '',
      senderId: json['sender_id'] as String? ?? '',
      receiverId: json['receiver_id'] as String? ?? '',
      groupId: json['group_id'] as String?,
      replyToId: json['reply_to_id'] as String?,
      messageType: json['message_type'] as String? ?? 'text',
      content: json['content'] as String? ?? '',
      filePath: json['file_path'] as String?,
      fileName: json['file_name'] as String?,
      fileSize: json['file_size'] as int?,
      mediaType: json['media_type'] as String?,
      status: json['status'] as String? ?? 'sent',
      // Server timestamps are UTC — normalize to device-local on parse so
      // every display path (bubbles, tiles, day dividers) renders correctly.
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String).toLocal()
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String).toLocal()
          : null,
      encryption: json['encryption'] as String? ?? 'none',
      cipherType: json['cipher_type'] as int?,
      cipherBody: json['cipher_body'] as String?,
      distribution: json['distribution'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sender_id': senderId,
      'receiver_id': receiverId,
      'group_id': groupId,
      'reply_to_id': replyToId,
      'message_type': messageType,
      'content': content,
      'file_path': filePath,
      'file_name': fileName,
      'file_size': fileSize,
      'media_type': mediaType,
      'status': status,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'encryption': encryption,
      'cipher_type': cipherType,
      'cipher_body': cipherBody,
      'distribution': distribution,
    };
  }

  Message copyWith({
    String? id,
    String? senderId,
    String? receiverId,
    String? groupId,
    String? replyToId,
    String? messageType,
    String? content,
    String? filePath,
    String? fileName,
    int? fileSize,
    String? mediaType,
    String? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? encryption,
    int? cipherType,
    String? cipherBody,
    String? distribution,
    String? mediaKey,
    String? mediaNonce,
  }) {
    return Message(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      receiverId: receiverId ?? this.receiverId,
      groupId: groupId ?? this.groupId,
      replyToId: replyToId ?? this.replyToId,
      messageType: messageType ?? this.messageType,
      content: content ?? this.content,
      filePath: filePath ?? this.filePath,
      fileName: fileName ?? this.fileName,
      fileSize: fileSize ?? this.fileSize,
      mediaType: mediaType ?? this.mediaType,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      encryption: encryption ?? this.encryption,
      cipherType: cipherType ?? this.cipherType,
      cipherBody: cipherBody ?? this.cipherBody,
      distribution: distribution ?? this.distribution,
      mediaKey: mediaKey ?? this.mediaKey,
      mediaNonce: mediaNonce ?? this.mediaNonce,
    );
  }

  bool get isTextMessage => messageType == 'text';
  bool get isImageMessage => messageType == 'image';
  bool get isVideoMessage => messageType == 'video';
  bool get isAudioMessage => messageType == 'audio';
  bool get isDocumentMessage => messageType == 'document';
  bool get isSent => status == 'sent';
  bool get isDelivered => status == 'delivered';
  bool get isRead => status == 'read';

  /// Local-only send states for optimistic bubbles: 'sending' while
  /// encryption/upload is in flight, 'failed' when the send died. A failure
  /// marks only this bubble — never the whole conversation.
  bool get isSending => status == 'sending';
  bool get isFailed => status == 'failed';
  bool get isGroupMessage => groupId != null;

  @override
  List<Object?> get props => [
        id,
        senderId,
        receiverId,
        groupId,
        replyToId,
        messageType,
        content,
        filePath,
        fileName,
        fileSize,
        mediaType,
        status,
        createdAt,
        updatedAt,
        encryption,
        cipherType,
        cipherBody,
        distribution,
        mediaKey,
        mediaNonce,
      ];
}
