import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';

import '../../models/message_model.dart';
import 'e2ee_key_value_store.dart';
import 'e2ee_manager.dart';
import 'key_bundle_transport.dart';
import 'media_crypto.dart';

/// Result of encrypting a media file for upload.
class EncryptedMedia {
  const EncryptedMedia({
    required this.cipherPath,
    required this.keyB64,
    required this.nonceB64,
  });

  /// Path to the encrypted bytes, ready for upload.
  final String cipherPath;
  final String keyB64;
  final String nonceB64;
}

/// Thrown when a message cannot be encrypted. Callers must treat this as
/// "message not sent" — silently falling back to plaintext would break the
/// app's end-to-end encryption guarantee.
class E2eeEncryptionException implements Exception {
  const E2eeEncryptionException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// High-level E2EE facade used by the chat layer.
///
/// Owns one [E2eeManager] per signed-in user (key material and sessions are
/// scoped per account) and exposes message-level encrypt/decrypt helpers.
class E2eeService {
  E2eeService._();

  static final E2eeService instance = E2eeService._();

  final Map<String, E2eeManager> _managers = {};
  final Random _random = Random.secure();

  // A Signal ciphertext can be decrypted exactly once — the Double Ratchet
  // consumes the message key on first use. The same message arrives via the
  // live WebSocket and again in every REST history fetch, so the plaintext
  // of the first successful decryption is memoized by message id.
  static const _maxCachedPlaintexts = 1000;
  final Map<String, String> _plaintextCache = {};

  String? _plaintextFor(String cacheKey) => _plaintextCache[cacheKey];

  void _cachePlaintext(String cacheKey, String plaintext) {
    _plaintextCache[cacheKey] = plaintext;
    while (_plaintextCache.length > _maxCachedPlaintexts) {
      _plaintextCache.remove(_plaintextCache.keys.first);
    }
  }

  // Plaintext the local user sent. The server only stores the ciphertext
  // addressed to the peer, so our own messages can never be Signal-decrypted
  // on history fetch (there is no session with ourselves). The plaintext is
  // therefore remembered here, keyed by server message id.
  //
  // WebSocket sends don't return the server id synchronously, so the
  // plaintext is staged per receiver in send order (the socket preserves
  // order) and committed when the server's `message_sent` ack arrives.
  final Map<String, List<String>> _pendingOwnPlaintext = {};

  /// Remembers [plaintext] (or a media-envelope JSON string) for the message
  /// the server stored under [serverMessageId].
  void cacheOwnPlaintext(String serverMessageId, String plaintext) {
    _cachePlaintext(serverMessageId, plaintext);
  }

  /// Stages an outgoing plaintext whose server id is not known yet (WS path).
  void stageOwnPlaintext(String receiverId, String plaintext) {
    _pendingOwnPlaintext.putIfAbsent(receiverId, () => []).add(plaintext);
  }

  /// Commits the oldest staged plaintext for [receiverId] under
  /// [serverMessageId]. Returns the committed plaintext, or null when nothing
  /// was staged (e.g. the message was sent from another device).
  String? commitOwnPlaintext(String serverMessageId, String receiverId) {
    final pending = _pendingOwnPlaintext[receiverId];
    if (pending == null || pending.isEmpty) return _plaintextFor(serverMessageId);
    final plaintext = pending.removeAt(0);
    if (pending.isEmpty) _pendingOwnPlaintext.remove(receiverId);
    _cachePlaintext(serverMessageId, plaintext);
    return plaintext;
  }

  /// Returns the manager for [userId], lazily creating and initializing its
  /// key bundle on the server on first use.
  Future<E2eeManager> forUser(String userId) async {
    final existing = _managers[userId];
    if (existing != null) return existing;

    final store = HiveE2eeStore(userId);
    await store.init();
    final manager = E2eeManager(
      store: store,
      transport: ApiKeyBundleTransport(),
    );
    await manager.initialize();
    _managers[userId] = manager;
    return manager;
  }

  /// Encrypts [plaintext] for [receiverId] and returns the message fields to
  /// send.
  ///
  /// Throws [E2eeEncryptionException] when encryption is impossible (e.g. the
  /// recipient has not published a key bundle yet) so callers can surface the
  /// failure instead of silently sending plaintext.
  Future<Map<String, dynamic>> prepareOutgoingText({
    required String currentUserId,
    required String receiverId,
    required String plaintext,
  }) async {
    try {
      final manager = await forUser(currentUserId);
      if (!await manager.hasSession(receiverId)) {
        await manager.establishSession(receiverId);
      }
      final encrypted = await manager.encrypt(receiverId, plaintext);
      return {
        'encryption': 'signal',
        'cipher_type': encrypted.type,
        'cipher_body': encrypted.body,
      };
    } catch (e) {
      throw E2eeEncryptionException(
        'Message not sent: could not encrypt (recipient has no key bundle or '
        'session establishment failed)',
      );
    }
  }

  /// Encrypts [plaintext] for [groupId] using the sender-key chain. Returns the
  /// group ciphertext fields to send.
  ///
  /// Throws [E2eeEncryptionException] when no sender key can be established so
  /// callers can surface the failure instead of silently sending plaintext.
  Future<Map<String, dynamic>> prepareOutgoingGroupText({
    required String currentUserId,
    required String groupId,
    required String plaintext,
  }) async {
    final manager = await forUser(currentUserId);
    final encrypted =
        await manager.encryptGroup(groupId, currentUserId, plaintext);
    if (encrypted == null) {
      throw const E2eeEncryptionException(
        'Message not sent: group encryption failed',
      );
    }
    return {
      'encryption': 'sgkey',
      'distribution': encrypted.distributionB64,
      'cipher_type': 0,
      'cipher_body': encrypted.body,
    };
  }

  /// Decrypts a group message from [senderId], applying the sender-key
  /// distribution message when present.
  Future<String> decryptGroupText({
    required String currentUserId,
    required String groupId,
    required String senderId,
    required String cipherBody,
    String? distributionB64,
  }) async {
    final manager = await forUser(currentUserId);
    return manager.decryptGroup(groupId, senderId, cipherBody, distributionB64);
  }

  /// Encrypts a media file at [filePath] with a fresh AES-256-GCM key/nonce,
  /// writing the ciphertext to a temp file. The key + nonce must be delivered
  /// to the recipient inside the Signal-encrypted message.
  Future<EncryptedMedia> encryptMediaFile(String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    final key = _randomBytes(MediaCrypto.keyLength);
    final nonce = _randomBytes(MediaCrypto.nonceLength);
    final cipher = MediaCrypto.encrypt(key, nonce, bytes);

    final tempPath =
        '${Directory.systemTemp.path}/sc_media_${DateTime.now().microsecondsSinceEpoch}.enc';
    await File(tempPath).writeAsBytes(cipher);

    return EncryptedMedia(
      cipherPath: tempPath,
      keyB64: base64Encode(key),
      nonceB64: base64Encode(nonce),
    );
  }

  /// Encrypts the media [envelope] (which contains the AES key/nonce) inside a
  /// Signal message for [receiverId].
  ///
  /// Throws [E2eeEncryptionException] when no session can be established —
  /// the attachment must never be uploaded with an unencrypted key envelope.
  Future<Map<String, dynamic>> encryptEnvelopeForPeer({
    required String currentUserId,
    required String receiverId,
    required Map<String, dynamic> envelope,
  }) async {
    try {
      final manager = await forUser(currentUserId);
      if (!await manager.hasSession(receiverId)) {
        await manager.establishSession(receiverId);
      }
      final encrypted = await manager.encrypt(receiverId, jsonEncode(envelope));
      return {
        'encryption': 'signal',
        'cipher_type': encrypted.type,
        'cipher_body': encrypted.body,
      };
    } catch (e) {
      throw const E2eeEncryptionException(
        'Attachment not sent: could not encrypt the media key envelope',
      );
    }
  }

  /// Decrypts [message] if it was sent with Signal encryption. Returns a copy
  /// with the plaintext in [Message.content] and encryption reset. For media
  /// messages the decrypted envelope populates the transient [Message.mediaKey]
  /// / [Message.mediaNonce] fields used to decrypt the attachment.
  ///
  /// Safe to call repeatedly for the same message: the first successful
  /// decryption is memoized, so later history fetches reuse the plaintext
  /// instead of re-consuming Double Ratchet message keys (which would fail).
  Future<Message> decryptMessage(
    Message message, {
    required String currentUserId,
  }) async {
    if (message.encryption != 'signal' ||
        message.cipherBody == null ||
        message.cipherType == null) {
      return message;
    }

    final cached = _plaintextFor(message.id);
    if (cached != null) {
      return _applyDecryptedPlaintext(message, cached);
    }

    // Our own messages are encrypted for the peer, so there is no session
    // with ourselves to decrypt them with. Serve the remembered plaintext;
    // never attempt a self-decrypt (it always fails and must not wipe state).
    if (message.senderId == currentUserId) {
      return message.copyWith(
        encryption: 'none',
        cipherBody: null,
        cipherType: null,
      );
    }

    try {
      final manager = await forUser(currentUserId);
      final plaintext = await manager.decrypt(
        message.senderId,
        message.cipherType!,
        message.cipherBody!,
      );
      _cachePlaintext(message.id, plaintext);
      return _applyDecryptedPlaintext(message, plaintext);
    } catch (e) {
      // Never log content or ciphertext — only the failure class and the
      // sender, which is enough to distinguish a stale session (recoverable)
      // from transport/format corruption (not recoverable).
      debugPrint(
        '[E2EE] decrypt failed msg=${message.id} '
        'from=${message.senderId} type=${message.cipherType} '
        'error=${e.runtimeType}',
      );
      // Self-heal a stale session (e.g. the peer re-registered their
      // identity after a reinstall): trust their current published identity
      // and drop the broken session so the next exchange re-establishes.
      // Only for crypto-state errors — wiping the session on duplicate,
      // format or transport errors would brick all future messages.
      if (_isSessionStateError(e)) {
        debugPrint('[E2EE] resetting stale session with ${message.senderId}');
        try {
          await (await forUser(currentUserId))
              .resetSession(message.senderId);
        } catch (_) {
          // Best-effort recovery; the placeholder below is returned regardless.
        }
      }
      return message.copyWith(
        content: '🔒 Unable to decrypt message',
        encryption: 'none',
      );
    }
  }

  /// Whether [e] signals stale Signal session state (safe to drop the
  /// session) as opposed to a duplicate, malformed or out-of-order payload
  /// (where dropping the session would destroy future messages too).
  bool _isSessionStateError(Object e) {
    if (e is FormatException || e is RangeError || e is ArgumentError) {
      return false;
    }
    final name = e.runtimeType.toString();
    return name.contains('UntrustedIdentity') ||
        name.contains('NoSession') ||
        name.contains('InvalidMessage') ||
        name.contains('InvalidMac') ||
        name.contains('InvalidKey') ||
        name.contains('LegacyMessage');
  }

  Message _applyDecryptedPlaintext(Message message, String plaintext) {
    if (message.isTextMessage) {
      return message.copyWith(
        content: plaintext,
        encryption: 'none',
        cipherBody: null,
        cipherType: null,
      );
    }

    // Media message: plaintext is the key envelope JSON.
    try {
      final envelope = jsonDecode(plaintext) as Map<String, dynamic>;
      return message.copyWith(
        content: envelope['text'] as String? ?? '',
        mediaKey: envelope['k'] as String?,
        mediaNonce: envelope['iv'] as String?,
        encryption: 'none',
        cipherBody: null,
        cipherType: null,
      );
    } catch (e) {
      return message.copyWith(
        content: '🔒 Unable to decrypt media',
        encryption: 'none',
        cipherBody: null,
        cipherType: null,
      );
    }
  }

  /// Memoized group-message decrypt. A sender-key ciphertext can only be
  /// decrypted once, and group history is re-fetched on every screen open —
  /// so the first successful plaintext is remembered per message id, exactly
  /// like [decryptMessage].
  Future<Message> decryptGroupMessage(
    Message message, {
    required String currentUserId,
  }) async {
    if (message.encryption != 'sgkey' ||
        message.cipherBody == null ||
        message.groupId == null) {
      return message;
    }

    final cached = _plaintextFor(message.id);
    if (cached != null) {
      return message.copyWith(
        content: cached,
        encryption: 'none',
        cipherBody: null,
        cipherType: null,
      );
    }

    try {
      final plaintext = await decryptGroupText(
        currentUserId: currentUserId,
        groupId: message.groupId!,
        senderId: message.senderId,
        cipherBody: message.cipherBody!,
        distributionB64: message.distribution,
      );
      _cachePlaintext(message.id, plaintext);
      return message.copyWith(
        content: plaintext,
        encryption: 'none',
        cipherBody: null,
        cipherType: null,
      );
    } catch (e) {
      debugPrint(
        '[E2EE] group decrypt failed msg=${message.id} '
        'from=${message.senderId} error=${e.runtimeType}',
      );
      return message.copyWith(
        content: '🔒 Unable to decrypt message',
        encryption: 'none',
      );
    }
  }

  /// Decrypts an encrypted media blob with the key/nonce from a decrypted
  /// message. Returns plaintext bytes.
  Future<Uint8List> decryptMediaBytes(
    Message message,
    List<int> cipherBytes,
  ) async {
    final key = base64Decode(message.mediaKey ?? '');
    final nonce = base64Decode(message.mediaNonce ?? '');
    if (key.length != MediaCrypto.keyLength ||
        nonce.length != MediaCrypto.nonceLength) {
      throw const FormatException('Invalid media key material');
    }
    return MediaCrypto.decrypt(
      Uint8List.fromList(key),
      Uint8List.fromList(nonce),
      Uint8List.fromList(cipherBytes),
    );
  }

  /// Permanently deletes all E2EE state for [userId] — identity keys, signed
  /// prekey, sessions and sender keys. Called on logout so a user's Signal
  /// identity does not survive their account on the device.
  Future<void> destroyUserState(String userId) async {
    _managers.remove(userId);
    try {
      await Hive.deleteBoxFromDisk('securechat_e2ee_$userId');
    } catch (_) {
      // The box may not exist (user never initialized E2EE) — nothing to do.
    }
  }

  /// Whether an encrypted session is established with [peerUserId].
  Future<bool> hasSession(String currentUserId, String peerUserId) async {
    final manager = _managers[currentUserId];
    if (manager == null) return false;
    return manager.hasSession(peerUserId);
  }

  /// Base64 public identity key for the user, used to display security codes.
  Future<String?> identityKeyBase64(String userId) async {
    try {
      final manager = await forUser(userId);
      return manager.getIdentityKeyPublicBase64();
    } catch (e) {
      return null;
    }
  }

  /// Computes the 60-digit safety number for a conversation by combining both
  /// users' identity keys. Returns null if the peer has no published bundle.
  Future<String?> computeSecurityNumber({
    required String currentUserId,
    required String peerUserId,
  }) async {
    try {
      final manager = await forUser(currentUserId);
      final localPair = await manager.getIdentityKeyPair();

      final bundle = await ApiKeyBundleTransport().fetchBundle(peerUserId);
      if (bundle == null) return null;
      final remoteIdentity =
          IdentityKey.fromBytes(base64Decode(bundle.identityKeyPublic), 0);

      final generator = NumericFingerprintGenerator(5200);
      final fingerprint = generator.createFor(
        0,
        utf8.encode(currentUserId),
        localPair.getPublicKey(),
        utf8.encode(peerUserId),
        remoteIdentity,
      );
      return fingerprint.displayableFingerprint.getDisplayText();
    } catch (e) {
      return null;
    }
  }

  Uint8List _randomBytes(int length) {
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i++) {
      bytes[i] = _random.nextInt(256);
    }
    return bytes;
  }
}
