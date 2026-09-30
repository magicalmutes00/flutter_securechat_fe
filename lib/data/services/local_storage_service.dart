import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import '../models/message_model.dart';
import '../models/user_model.dart';
import 'at_rest_key.dart';

/// A record of cached conversations for a user, returned by
/// [LocalStorageService.getConversations].
class LocalConversationData {
  final Map<String, User> conversations;
  final Map<String, Message> lastMessages;

  LocalConversationData({
    required this.conversations,
    required this.lastMessages,
  });
}

/// Local on-device cache used for offline support and fast initial renders.
///
/// Data is scoped per signed-in user and stored as JSON strings in a single
/// Hive box. Each field name embeds the current user id so switching accounts
/// does not leak conversations between users.
class LocalStorageService {
  static const String _boxName = 'securechat_local_cache';
  static final LocalStorageService _instance = LocalStorageService._internal();
  factory LocalStorageService() => _instance;

  LocalStorageService._internal();

  Box<String>? _box;

  Future<void> init() async {
    final cipher = await AtRestKey().getOrCreateCipher();
    _box = await Hive.openBox<String>(_boxName, encryptionCipher: cipher);
  }

  Box<String> get _db {
    final box = _box;
    if (box == null) {
      throw StateError('LocalStorageService.init() must be called first');
    }
    return box;
  }

  String _messagesKey(String userId, String peerUserId) =>
      '$userId:messages:$peerUserId';

  String _conversationsKey(String userId) => '$userId:conversations';

  String _lastMessagesKey(String userId) => '$userId:last_messages';

  String _lastSyncKey(String userId) => '$userId:last_sync';

  String _outboxKey(String userId) => '$userId:outbox';

  /// Returns the messages cached for a single 1:1 conversation (old->new).
  List<Message> getMessages(String userId, String peerUserId) {
    final raw = _db.get(_messagesKey(userId, peerUserId));
    if (raw == null || raw.isEmpty) return [];

    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => Message.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Overwrites the cached messages for a conversation.
  Future<void> saveMessages(
    String userId,
    String peerUserId,
    List<Message> messages,
  ) async {
    final encoded = jsonEncode(messages.map((m) => m.toJson()).toList());
    await _db.put(_messagesKey(userId, peerUserId), encoded);
  }

  /// Appends a single message to the cached conversation, de-duplicating by id.
  Future<void> addMessage(
    String userId,
    String peerUserId,
    Message message,
  ) async {
    final existing = getMessages(userId, peerUserId);
    if (existing.any((m) => m.id == message.id)) return;
    existing.add(message);
    await saveMessages(userId, peerUserId, existing);
  }

  /// Replaces the cached message [oldId] with [replacement] (used to swap an
  /// optimistic temp bubble for the server-acknowledged message carrying the
  /// real plaintext). Falls back to append when [oldId] is not cached.
  Future<void> replaceMessage(
    String userId,
    String peerUserId,
    String oldId,
    Message replacement,
  ) async {
    final existing = getMessages(userId, peerUserId);
    final idx = existing.indexWhere((m) => m.id == oldId);
    if (idx == -1) {
      await addMessage(userId, peerUserId, replacement);
      return;
    }
    existing[idx] = replacement;
    await saveMessages(userId, peerUserId, existing);
  }

  /// Persists the conversation list and per-conversation last messages.
  Future<void> saveConversations(
    String userId,
    Map<String, User> conversations,
    Map<String, Message> lastMessages,
  ) async {
    final convJson = conversations.map((k, v) => MapEntry(k, v.toJson()));
    final lastJson = lastMessages.map((k, v) => MapEntry(k, v.toJson()));

    await _db.put(_conversationsKey(userId), jsonEncode(convJson));
    await _db.put(_lastMessagesKey(userId), jsonEncode(lastJson));
  }

  /// Returns cached conversations and last messages for the user, or null if
  /// nothing has been cached yet.
  LocalConversationData? getConversations(String userId) {
    final convRaw = _db.get(_conversationsKey(userId));
    final lastRaw = _db.get(_lastMessagesKey(userId));
    if (convRaw == null) return null;

    try {
      final convMap = jsonDecode(convRaw) as Map<String, dynamic>;
      final conversations = <String, User>{};
      convMap.forEach((id, value) {
        conversations[id] = User.fromJson(value as Map<String, dynamic>);
      });

      var lastMessages = <String, Message>{};
      if (lastRaw != null) {
        final lastJson = jsonDecode(lastRaw) as Map<String, dynamic>;
        lastMessages = lastJson.map(
          (id, value) =>
              MapEntry(id, Message.fromJson(value as Map<String, dynamic>)),
        );
      }

      return LocalConversationData(
        conversations: conversations,
        lastMessages: lastMessages,
      );
    } catch (_) {
      return null;
    }
  }

  /// Records the last time conversations were synced from the server.
  Future<void> setLastSyncTime(String userId) async {
    await _db.put(_lastSyncKey(userId), DateTime.now().toIso8601String());
  }

  /// Returns the messages queued for offline delivery (oldest first).
  List<Message> getOutbox(String userId) {
    final raw = _db.get(_outboxKey(userId));
    if (raw == null || raw.isEmpty) return [];

    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => Message.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Queues a message for delivery once the connection is back.
  Future<void> enqueueOutbox(String userId, Message message) async {
    final pending = getOutbox(userId);
    if (pending.any((m) => m.id == message.id)) return;
    pending.add(message);
    await _db.put(_outboxKey(userId),
        jsonEncode(pending.map((m) => m.toJson()).toList()));
  }

  /// Removes a successfully delivered message from the queue.
  Future<void> removeFromOutbox(String userId, String messageId) async {
    final pending = getOutbox(userId).where((m) => m.id != messageId).toList();
    await _db.put(_outboxKey(userId),
        jsonEncode(pending.map((m) => m.toJson()).toList()));
  }

  /// Clears the whole outbox (used when the account logs out).
  Future<void> clearOutbox(String userId) async {
    await _db.delete(_outboxKey(userId));
  }

  /// Clears all cached data belonging to a user (used on logout).
  Future<void> clearUserData(String userId) async {
    final keysToRemove = <String>[];
    final prefix1 = '$userId:';
    for (final key in _db.keys) {
      if (key.startsWith(prefix1)) {
        keysToRemove.add(key);
      }
    }
    if (keysToRemove.isNotEmpty) {
      await _db.deleteAll(keysToRemove);
    }
  }
}
