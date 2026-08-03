import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

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

/// High-level E2EE facade used by the chat layer.
///
/// Owns one [E2eeManager] per signed-in user (key material and sessions are
/// scoped per account) and exposes message-level encrypt/decrypt helpers.
class E2eeService {
  E2eeService._();

  static final E2eeService instance = E2eeService._();

  final Map<String, E2eeManager> _managers = {};
  final Random _random = Random.secure();

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
  /// send. Falls back to plaintext (encryption: 'none') when the recipient has
  /// not yet published a key bundle, so messaging still works during rollout.
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
      // No key bundle available for the recipient yet: send plaintext.
      return {'encryption': 'none'};
    }
  }

  /// Encrypts [plaintext] for [groupId] using the sender-key chain. Returns the
  /// group ciphertext fields to send, or null when no sender-key exists yet
  /// (fallback to plaintext).
  Future<Map<String, dynamic>> prepareOutgoingGroupText({
    required String currentUserId,
    required String groupId,
    required String plaintext,
  }) async {
    try {
      final manager = await forUser(currentUserId);
      final encrypted =
          await manager.encryptGroup(groupId, currentUserId, plaintext);
      if (encrypted == null) return {'encryption': 'none'};
      return {
        'encryption': 'sgkey',
        'distribution': encrypted.distributionB64,
        'cipher_type': 0,
        'cipher_body': encrypted.body,
      };
    } catch (e) {
      return {'encryption': 'none'};
    }
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
  /// Signal message for [receiverId]. Returns the message crypto fields, or
  /// null when no session can be established (fallback to plaintext media).
  Future<Map<String, dynamic>?> encryptEnvelopeForPeer({
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
      return null;
    }
  }

  /// Decrypts [message] if it was sent with Signal encryption. Returns a copy
  /// with the plaintext in [Message.content] and encryption reset. For media
  /// messages the decrypted envelope populates the transient [Message.mediaKey]
  /// / [Message.mediaNonce] fields used to decrypt the attachment.
  Future<Message> decryptMessage(
    Message message, {
    required String currentUserId,
  }) async {
    if (message.encryption != 'signal' ||
        message.cipherBody == null ||
        message.cipherType == null) {
      return message;
    }
    try {
      final manager = await forUser(currentUserId);
      final plaintext = await manager.decrypt(
        message.senderId,
        message.cipherType!,
        message.cipherBody!,
      );

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
    } catch (e) {
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
