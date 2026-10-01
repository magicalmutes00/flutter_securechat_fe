import 'dart:collection';

/// A successfully decrypted message payload, including the media-envelope
/// key material needed to render an attachment after an app restart.
///
/// The record itself contains plaintext, so it must only be persisted in
/// storage that is encrypted at rest. Callers are responsible for choosing a
/// backend with that property; the production backend is the encrypted Hive
/// box owned by [LocalStorageService].
class DecryptedMessageRecord {
  DecryptedMessageRecord({
    required this.plaintext,
    this.mediaKey,
    this.mediaNonce,
    DateTime? savedAt,
  }) : savedAt = savedAt ?? DateTime.now();

  /// For text messages, the decrypted text. For 1:1 media messages, the
  /// decrypted key-envelope JSON. For group messages, decrypted text.
  final String plaintext;

  /// Base64 AES-256-GCM key from a decrypted media envelope, when applicable.
  final String? mediaKey;

  /// Base64 AES-256-GCM nonce from a decrypted media envelope, when applicable.
  final String? mediaNonce;

  /// When this record was written. Used only for diagnostics and debugging;
  /// eviction is insertion-ordered, not time-ordered.
  final DateTime savedAt;

  Map<String, dynamic> toJson() {
    return {
      'plaintext': plaintext,
      if (mediaKey != null) 'media_key': mediaKey,
      if (mediaNonce != null) 'media_nonce': mediaNonce,
      'saved_at': savedAt.toIso8601String(),
    };
  }

  static DecryptedMessageRecord? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final plaintext = json['plaintext'];
    if (plaintext is! String) return null;

    final mediaKey = json['media_key'];
    if (mediaKey != null && mediaKey is! String) return null;
    final mediaNonce = json['media_nonce'];
    if (mediaNonce != null && mediaNonce is! String) return null;

    DateTime? savedAt;
    final rawSavedAt = json['saved_at'];
    if (rawSavedAt != null) {
      if (rawSavedAt is! String) return null;
      try {
        savedAt = DateTime.parse(rawSavedAt);
      } catch (_) {
        return null;
      }
    }

    return DecryptedMessageRecord(
      plaintext: plaintext,
      mediaKey: mediaKey as String?,
      mediaNonce: mediaNonce as String?,
      savedAt: savedAt,
    );
  }

  bool sameContent(DecryptedMessageRecord other) {
    return plaintext == other.plaintext &&
        mediaKey == other.mediaKey &&
        mediaNonce == other.mediaNonce;
  }
}

/// Loads every durable decrypted-message record for one local user.
typedef DecryptedMessageLoader = Future<Map<String, DecryptedMessageRecord>>
    Function(String userId);

/// Replaces every durable decrypted-message record for one local user.
typedef DecryptedMessageSaver = Future<void> Function(
  String userId,
  Map<String, DecryptedMessageRecord> records,
);

/// A bounded, insertion-ordered cache of decrypted messages with a pluggable
/// persistence backend.
///
/// Signal ciphertexts can only be decrypted once: the Double Ratchet consumes
/// the message key. The same server row is delivered repeatedly by live
/// sockets, history fetches, and app restarts, so the first successful
/// result is retained here. Reads consult memory first, then hydrate once
/// from the backend; writes update memory and then replace the backend's
/// whole per-user map.
class DecryptedMessageStore {
  DecryptedMessageStore({
    required DecryptedMessageLoader loadAll,
    required DecryptedMessageSaver saveAll,
    int maxEntries = 5000,
  })  : assert(maxEntries > 0, 'maxEntries must be positive'),
        _loadAll = loadAll,
        _saveAll = saveAll,
        _maxEntries = maxEntries;

  final DecryptedMessageLoader _loadAll;
  final DecryptedMessageSaver _saveAll;
  final int _maxEntries;
  final Map<String, Map<String, DecryptedMessageRecord>> _records = {};

  Future<DecryptedMessageRecord?> read(String userId, String messageId) async {
    if (userId.isEmpty || messageId.isEmpty) return null;
    await _ensureLoaded(userId);
    return _records[userId]?[messageId];
  }

  Future<void> write(
    String userId,
    String messageId,
    DecryptedMessageRecord record,
  ) async {
    if (userId.isEmpty || messageId.isEmpty) return;
    await _ensureLoaded(userId);

    final userRecords = _records.putIfAbsent(userId, LinkedHashMap.new);
    if (userRecords[messageId]?.sameContent(record) ?? false) return;

    userRecords[messageId] = record;
    while (userRecords.length > _maxEntries) {
      userRecords.remove(userRecords.keys.first);
    }
    await _saveAll(userId, Map<String, DecryptedMessageRecord>.of(userRecords));
  }

  Future<void> _ensureLoaded(String userId) async {
    if (_records.containsKey(userId)) return;
    final loaded = <String, DecryptedMessageRecord>{};
    try {
      final persisted = await _loadAll(userId);
      for (final entry in persisted.entries) {
        if (entry.key.isNotEmpty) loaded[entry.key] = entry.value;
      }
      while (loaded.length > _maxEntries) {
        loaded.remove(loaded.keys.first);
      }
    } catch (_) {
      // A corrupt or unavailable backend must never break decryption.
      // Callers fall back to attempting a live Signal decrypt.
    }
    _records[userId] = loaded;
  }
}
