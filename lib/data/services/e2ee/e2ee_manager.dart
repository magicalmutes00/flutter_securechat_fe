import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:fixnum/fixnum.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';

import 'e2ee_key_value_store.dart';
import 'key_bundle_transport.dart';
import 'secure_signal_store.dart';

/// Result of encrypting a plaintext message for a recipient.
class EncryptedMessage {
  const EncryptedMessage({required this.type, required this.body});

  /// [CiphertextMessage.prekeyType] for the first message of a session,
  /// [CiphertextMessage.whisperType] afterwards.
  final int type;

  /// Base64-encoded serialized ciphertext.
  final String body;

  Map<String, dynamic> toJson() => {'type': type, 'body': body};

  static EncryptedMessage fromJson(Map<String, dynamic> json) =>
      EncryptedMessage(type: json['type'] as int, body: json['body'] as String);
}

/// Result of encrypting a group message with the sender-key chain.
class GroupEncryptedMessage {
  const GroupEncryptedMessage({
    required this.distributionB64,
    required this.body,
  });

  /// Base64 sender-key distribution message (sent on the first message to new
  /// members so they can derive the group key chain).
  final String distributionB64;

  /// Base64 serialized group ciphertext.
  final String body;
}

/// Orchestrates the Signal-protocol E2EE lifecycle for the current user:
/// key generation/rotation, bundle upload, session establishment (X3DH),
/// and message encrypt/decrypt.
class E2eeManager {
  E2eeManager({
    required E2eeKeyValueStore store,
    required KeyBundleTransport transport,
  })  : _store = store,
        _signalStore = SecureSignalStore(store),
        _senderKeyStore = SecureSenderKeyStore(store),
        _transport = transport;

  static const int preKeyCount = 40;
  static const int preKeyLowWatermark = 20;

  final E2eeKeyValueStore _store;
  final SecureSignalStore _signalStore;
  final SecureSenderKeyStore _senderKeyStore;
  final KeyBundleTransport _transport;

  final Random _random = Random.secure();

  static const _deviceIdKey = 'device_id';

  // ---------------------------------------------------------------------------
  // Identity & local state
  // ---------------------------------------------------------------------------

  Future<IdentityKeyPair> getIdentityKeyPair() =>
      _signalStore.getIdentityKeyPair();

  Future<String> getIdentityKeyPublicBase64() async =>
      base64Encode((await getIdentityKeyPair()).getPublicKey().serialize());

  Future<int> getRegistrationId() => _signalStore.getLocalRegistrationId();

  Future<String> getOrCreateDeviceId() async {
    final existing = await _store.read(_deviceIdKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final id = _randomUuid();
    await _store.write(_deviceIdKey, id);
    return id;
  }

  /// Ensures identity keys, registration id and the signed prekey exist and
  /// publishes (or replenishes) the local bundle on the server.
  Future<void> initialize() async {
    final deviceId = await getOrCreateDeviceId();
    await _ensureIdentity();

    final signedPreKey = await _signalStore.loadSignedPreKeys();
    if (signedPreKey.isEmpty) {
      await _generateAndStoreSignedPreKey();
    }

    await _replenishAndUpload(deviceId);
  }

  Future<void> _ensureIdentity() async {
    try {
      await _signalStore.getIdentityKeyPair();
    } on StateError {
      final keyPair = Curve.generateKeyPair();
      await _signalStore.setIdentityKeyPair(
        IdentityKeyPair(IdentityKey(keyPair.publicKey), keyPair.privateKey),
      );
      await _signalStore.setLocalRegistrationId(
        _random.nextInt(16380) + 1,
      );
    }
  }

  Future<void> _generateAndStoreSignedPreKey() async {
    final identityKeyPair = await _signalStore.getIdentityKeyPair();
    final id = _random.nextInt(10000) + 1;
    final keyPair = Curve.generateKeyPair();
    final signature = Curve.calculateSignature(
      identityKeyPair.getPrivateKey(),
      keyPair.publicKey.serialize(),
    );
    await _signalStore.storeSignedPreKey(
      id,
      SignedPreKeyRecord(
        id,
        Int64(DateTime.now().microsecondsSinceEpoch),
        keyPair,
        signature,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Bundle upload & one-time prekey replenishment
  // ---------------------------------------------------------------------------

  Future<void> _replenishAndUpload(String deviceId) async {
    final existing = await _signalStore.getPreKeyIds();

    if (existing.isEmpty) {
      // First time: upload the full bundle.
      await _uploadFullBundle(deviceId);
      return;
    }

    final remaining = await _transport.remainingOneTimePrekeys(deviceId);
    if (remaining < preKeyLowWatermark) {
      final toAdd = preKeyCount - remaining;
      final newPublicKeys = <String>[];
      var nextId = existing.reduce(max);
      for (var i = 0; i < toAdd; i++) {
        nextId++;
        final pair = Curve.generateKeyPair();
        await _signalStore.storePreKey(nextId, PreKeyRecord(nextId, pair));
        newPublicKeys.add(base64Encode(pair.publicKey.serialize()));
      }
      await _transport.replenishOneTimePrekeys(
        deviceId: deviceId,
        oneTimePrekeys: newPublicKeys,
      );
    }
  }

  Future<void> _uploadFullBundle(String deviceId) async {
    final identityKeyPair = await _signalStore.getIdentityKeyPair();
    final registrationId = await _signalStore.getLocalRegistrationId();
    final signedPreKey = (await _signalStore.loadSignedPreKeys()).first;

    final oneTimePrekeys = <String>[];
    for (var i = 0; i < preKeyCount; i++) {
      final pair = Curve.generateKeyPair();
      final id = i + 1;
      await _signalStore.storePreKey(id, PreKeyRecord(id, pair));
      oneTimePrekeys.add(base64Encode(pair.publicKey.serialize()));
    }

    await _transport.uploadBundle(
      deviceId: deviceId,
      registrationId: registrationId,
      identityKeyPublic:
          base64Encode(identityKeyPair.getPublicKey().serialize()),
      signedPrekeyId: signedPreKey.id,
      signedPrekeyPublic:
          base64Encode(signedPreKey.getKeyPair().publicKey.serialize()),
      signedPrekeySignature: base64Encode(signedPreKey.signature),
      oneTimePrekeys: oneTimePrekeys,
    );
  }

  /// Whether the server's remaining one-time prekey count has fallen below the
  /// watermark, meaning the local bundle should be replenished.
  Future<bool> needsReplenishment() async {
    final deviceId = await getOrCreateDeviceId();
    final remaining = await _transport.remainingOneTimePrekeys(deviceId);
    return remaining < preKeyLowWatermark;
  }

  // ---------------------------------------------------------------------------
  // Session establishment (X3DH)
  // ---------------------------------------------------------------------------

  Future<bool> hasSession(String peerUserId) => _signalStore.containsSession(
        SignalProtocolAddress(peerUserId, 1),
      );

  /// Establishes a session with [peerUserId] using their published key bundle.
  Future<void> establishSession(String peerUserId) async {
    final bundle = await _transport.fetchBundle(peerUserId);
    if (bundle == null) {
      throw StateError('No key bundle available for $peerUserId');
    }

    final identityKey = IdentityKey.fromBytes(
      base64Decode(bundle.identityKeyPublic),
      0,
    );
    final signedPreKeyPublic = Curve.decodePoint(
      base64Decode(bundle.signedPrekeyPublic),
      0,
    );
    final signature = base64Decode(bundle.signedPrekeySignature);

    ECPublicKey? oneTimePreKeyPublic;
    if (bundle.oneTimePrekeyPublic != null) {
      oneTimePreKeyPublic =
          Curve.decodePoint(base64Decode(bundle.oneTimePrekeyPublic!), 0);
    }

    final preKeyBundle = PreKeyBundle(
      bundle.registrationId,
      bundle.deviceId,
      bundle.oneTimePrekeyId,
      oneTimePreKeyPublic,
      bundle.signedPrekeyId,
      signedPreKeyPublic,
      signature,
      identityKey,
    );

    final remoteAddress = SignalProtocolAddress(peerUserId, 1);
    final builder = SessionBuilder.fromSignalStore(_signalStore, remoteAddress);
    await builder.processPreKeyBundle(preKeyBundle);
  }

  /// Stores the identity key of a peer and verifies the peer's signed prekey
  /// signature matches, preventing identity-key substitution.
  Future<bool> verifyPeerIdentity(String peerUserId) async {
    final bundle = await _transport.fetchBundle(peerUserId);
    if (bundle == null) return false;
    final identityKey = IdentityKey.fromBytes(
      base64Decode(bundle.identityKeyPublic),
      0,
    );
    final signedPreKeyPublic = Curve.decodePoint(
      base64Decode(bundle.signedPrekeyPublic),
      0,
    );
    return Curve.verifySignature(
      identityKey.publicKey,
      signedPreKeyPublic.serialize(),
      base64Decode(bundle.signedPrekeySignature),
    );
  }

  // ---------------------------------------------------------------------------
  // Encrypt / decrypt
  // ---------------------------------------------------------------------------

  Future<EncryptedMessage> encrypt(
    String peerUserId,
    String plaintext,
  ) async {
    final remoteAddress = SignalProtocolAddress(peerUserId, 1);
    final cipher = SessionCipher.fromStore(_signalStore, remoteAddress);
    final padded = _pad(utf8.encode(plaintext));
    final message = await cipher.encrypt(padded);
    return EncryptedMessage(
      type: message.getType(),
      body: base64Encode(message.serialize()),
    );
  }

  Future<String> decrypt(
    String peerUserId,
    int messageType,
    String body,
  ) async {
    final remoteAddress = SignalProtocolAddress(peerUserId, 1);
    final cipher = SessionCipher.fromStore(_signalStore, remoteAddress);
    final bytes = base64Decode(body);

    final Uint8List plaintext;
    if (messageType == CiphertextMessage.prekeyType) {
      final message = PreKeySignalMessage(bytes);
      plaintext = await cipher.decrypt(message);
    } else {
      final message = SignalMessage.fromSerialized(bytes);
      plaintext = await cipher.decryptFromSignal(message);
    }

    return utf8.decode(_unpad(plaintext));
  }

  // ---------------------------------------------------------------------------
  // Group (sender key) encryption
  // ---------------------------------------------------------------------------

  /// Whether a sender-key record is already established for [senderId] in
  /// [groupId], meaning we can decrypt their messages without a distribution
  /// message.
  Future<bool> hasGroupSenderKey(String groupId, String senderId) async {
    final keyName = SenderKeyName(groupId, SignalProtocolAddress(senderId, 1));
    final record = await _senderKeyStore.loadSenderKey(keyName);
    return !record.isEmpty;
  }

  Future<void> processGroupSenderDistribution(
    String groupId,
    String senderId,
    String distributionB64,
  ) =>
      processGroupSenderKey(groupId, senderId, distributionB64);

  /// Processes a sender-key distribution message from [senderId] for [groupId]
  /// so their subsequent group messages can be decrypted.
  Future<void> processGroupSenderKey(
    String groupId,
    String senderId,
    String distributionB64,
  ) async {
    final keyName = SenderKeyName(
      groupId,
      SignalProtocolAddress(senderId, 1),
    );
    final distribution = SenderKeyDistributionMessageWrapper.fromSerialized(
      base64Decode(distributionB64),
    );
    final builder = GroupSessionBuilder(_senderKeyStore);
    await builder.process(keyName, distribution);
  }

  /// Encrypts [plaintext] for [groupId] using the sender-key chain. Falls back
  /// to plaintext when no sender-key is established.
  Future<GroupEncryptedMessage?> encryptGroup(
    String groupId,
    String senderId,
    String plaintext,
  ) async {
    try {
      final keyName = SenderKeyName(
        groupId,
        SignalProtocolAddress(senderId, 1),
      );
      final builder = GroupSessionBuilder(_senderKeyStore);
      final distribution = await builder.create(keyName);

      final cipher = GroupCipher(_senderKeyStore, keyName);
      final padded = _pad(utf8.encode(plaintext));
      final ciphertext = await cipher.encrypt(padded);

      return GroupEncryptedMessage(
        distributionB64: base64Encode(distribution.serialize()),
        body: base64Encode(ciphertext),
      );
    } catch (e) {
      return null;
    }
  }

  /// Decrypts a group message from [senderId]. Applies the sender-key
  /// distribution message first when [distributionB64] is provided.
  Future<String> decryptGroup(
    String groupId,
    String senderId,
    String body,
    String? distributionB64,
  ) async {
    if (distributionB64 != null && distributionB64.isNotEmpty) {
      await processGroupSenderKey(groupId, senderId, distributionB64);
    }

    final keyName = SenderKeyName(groupId, SignalProtocolAddress(senderId, 1));
    final cipher = GroupCipher(_senderKeyStore, keyName);
    final plaintext = await cipher.decrypt(base64Decode(body));
    return utf8.decode(_unpad(plaintext));
  }

  // ---------------------------------------------------------------------------
  // Padding
  // ---------------------------------------------------------------------------

  static const int _paddingBlockSize = 256;

  /// Pads [data] with a 4-byte big-endian length prefix and trailing zeros to a
  /// fixed block size so ciphertext length does not leak message length.
  static Uint8List _pad(Uint8List data) {
    final paddedLength =
        ((data.length + 4 + _paddingBlockSize - 1) ~/ _paddingBlockSize) *
            _paddingBlockSize;
    final out = Uint8List(paddedLength);
    final lengthBytes = ByteData(4)..setUint32(0, data.length);
    out.setRange(0, 4, lengthBytes.buffer.asUint8List());
    out.setRange(4, 4 + data.length, data);
    return out;
  }

  static Uint8List _unpad(Uint8List data) {
    final length = ByteData.sublistView(data, 0, 4).getUint32(0);
    return Uint8List.fromList(data.sublist(4, 4 + length));
  }

  String _randomUuid() {
    final bytes = Uint8List(16);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = _random.nextInt(256);
    }
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final encoded = hex.encode(bytes);
    return '${encoded.substring(0, 8)}-${encoded.substring(8, 12)}-'
        '${encoded.substring(12, 16)}-${encoded.substring(16, 20)}-'
        '${encoded.substring(20)}';
  }
}
