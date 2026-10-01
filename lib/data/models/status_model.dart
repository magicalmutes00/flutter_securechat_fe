import 'package:equatable/equatable.dart';
import 'user_model.dart';

/// A single ephemeral status ("story"). Expires [expiresAt] seconds after
/// creation.
class Status extends Equatable {
  final String id;
  final String userId;
  final String? text;
  final String? mediaPath;
  final String? mediaType;
  final DateTime createdAt;
  final DateTime expiresAt;
  final List<String> viewers;
  final User? author;

  const Status({
    required this.id,
    required this.userId,
    this.text,
    this.mediaPath,
    this.mediaType,
    required this.createdAt,
    required this.expiresAt,
    this.viewers = const [],
    this.author,
  });

  factory Status.fromJson(Map<String, dynamic> json) {
    return Status(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      text: json['text'] as String?,
      mediaPath: json['media_path'] as String?,
      mediaType: json['media_type'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      expiresAt: DateTime.parse(json['expires_at'] as String).toLocal(),
      viewers: (json['viewers'] as List<dynamic>? ?? [])
          .map((e) => e as String)
          .toList(),
    );
  }

  /// Whether the status carries image media (vs. plain text).
  bool get isImage =>
      mediaPath != null && (mediaType?.startsWith('image') ?? false);

  bool isExpired([DateTime? now]) => (now ?? DateTime.now()).isAfter(expiresAt);

  bool hasBeenViewedBy(String viewerId) => viewers.contains(viewerId);

  @override
  List<Object?> get props => [
        id,
        userId,
        text,
        mediaPath,
        mediaType,
        createdAt,
        expiresAt,
        viewers,
        author
      ];
}
