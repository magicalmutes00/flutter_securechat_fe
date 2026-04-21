import 'package:equatable/equatable.dart';

class User extends Equatable {
  final String id;
  final String? phone; // Nullable - may not be available for all login methods
  final String? email; // Nullable - email/password and Google login
  final String? firebaseUid; // Firebase UID for cross-referencing users
  final String? username;
  final String? displayName;
  final String? avatarUrl;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final bool isOnline;
  final DateTime? lastSeen;

  const User({
    required this.id,
    this.phone,
    this.email,
    this.firebaseUid,
    this.username,
    this.displayName,
    this.avatarUrl,
    this.createdAt,
    this.updatedAt,
    this.isOnline = false,
    this.lastSeen,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    // Handle various response formats
    final id = json['id'] as String? ?? json['_id'] as String? ?? '';
    final displayName = json['display_name'] as String? ?? json['name'] as String?;

    return User(
      id: id,
      phone: json['phone'] as String?,
      email: json['email'] as String?,
      firebaseUid: json['firebase_uid'] as String?,
      username: json['username'] as String?,
      displayName: displayName,
      avatarUrl: json['avatar_url'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
      isOnline: json['is_online'] as bool? ?? false,
      lastSeen: json['last_seen'] != null
          ? DateTime.parse(json['last_seen'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'phone': phone,
      'email': email,
      'firebase_uid': firebaseUid,
      'username': username,
      'display_name': displayName,
      'avatar_url': avatarUrl,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'is_online': isOnline,
      'last_seen': lastSeen?.toIso8601String(),
    };
  }

  User copyWith({
    String? id,
    String? phone,
    String? email,
    String? firebaseUid,
    String? username,
    String? displayName,
    String? avatarUrl,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isOnline,
    DateTime? lastSeen,
  }) {
    return User(
      id: id ?? this.id,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      firebaseUid: firebaseUid ?? this.firebaseUid,
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isOnline: isOnline ?? this.isOnline,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }

  @override
  List<Object?> get props => [
        id,
        phone,
        email,
        firebaseUid,
        username,
        displayName,
        avatarUrl,
        createdAt,
        updatedAt,
        isOnline,
        lastSeen,
      ];
}
