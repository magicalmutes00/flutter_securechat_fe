import 'package:equatable/equatable.dart';

class Group extends Equatable {
  final String id;
  final String name;
  final String? avatarUrl;
  final String creatorId;
  final List<String> memberIds;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Group({
    required this.id,
    required this.name,
    this.avatarUrl,
    required this.creatorId,
    required this.memberIds,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Group.fromJson(Map<String, dynamic> json) {
    return Group(
      id: json['id'] as String,
      name: json['name'] as String,
      avatarUrl: json['avatar_url'] as String?,
      creatorId: json['creator_id'] as String,
      memberIds: (json['member_ids'] as List<dynamic>? ?? [])
          .map((e) => e as String)
          .toList(),
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      updatedAt: DateTime.parse(json['updated_at'] as String).toLocal(),
    );
  }

  bool get isGroup => true;

  @override
  List<Object?> get props =>
      [id, name, avatarUrl, creatorId, memberIds, createdAt, updatedAt];
}
