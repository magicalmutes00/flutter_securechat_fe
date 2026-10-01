import 'package:equatable/equatable.dart';

class Message extends Equatable {
  /// Bubble copy rendered when a received ciphertext cannot be decrypted.
  /// Single source of truth: the decrypt path writes it, the receive path
  /// reads it back to detect live decryption failures.
  static const String decryptionFailedContent = '🔒 Unable to decrypt message';

  /// Same, for a media key envelope that cannot be decrypted.
  static const String decryptionFailedMediaContent = '🔒 Unable to decrypt media';

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

  // Transient 0..1 upload progress for an in-flight optimistic send. Never
  // serialized: a reopened chat re-derives send state from the server, and
  // the value changes dozens of times per upload.
  final double? uploadProgress;

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
    this.uploadProgress,
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
    double? uploadProgress,

    /// copyWith can't distinguish "no change" from "set to null", so
    /// progress is cleared explicitly (e.g. once the upload finishes and the
    /// bubble stops showing the ring).
    bool clearUploadProgress = false,
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
      uploadProgress: clearUploadProgress
          ? null
          : (uploadProgress ?? this.uploadProgress),
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

  /// Whether this bubble is a decryption-failure placeholder. Such rows must
  /// never be treated as ground truth by the cache: persisting one cements a
  /// transient failure forever (later loads serve it without retrying the
  /// still-good server ciphertext), and merges must let a fresh good decrypt
  /// replace it. The legacy pre-encryption notice is NOT a failure — it is
  /// stable truth and caches normally.
  bool get isDecryptionFailure =>
      content == decryptionFailedContent ||
      content == decryptionFailedMediaContent;
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
        // Transient by design: progress ticks rebuild the bubble but are
        // never persisted (toJson omits the field; fromJson yields null).
        uploadProgress,
      ];
}
