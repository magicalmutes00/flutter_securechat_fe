import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';

import 'package:secure_chat/data/services/e2ee/e2ee_key_value_store.dart';
import 'package:secure_chat/data/services/e2ee/e2ee_manager.dart';
import 'package:secure_chat/data/services/e2ee/in_memory_key_bundle_transport.dart';
import 'package:secure_chat/data/services/e2ee/media_crypto.dart';

void main() {
  test('full E2EE round trip: initialize, X3DH session, encrypt/decrypt',
      () async {
    final transport = InMemoryKeyBundleTransport();

    final aliceStore = InMemoryE2eeStore();
    final bobStore = InMemoryE2eeStore();

    final alice = E2eeManager(store: aliceStore, transport: transport);
    final bob = E2eeManager(store: bobStore, transport: transport);

    // Both users publish their key bundles.
    await alice.initialize();
    await bob.initialize();

    // Identify each other by their identity-key-derived user id.
    final aliceId = inMemoryUserKey(await alice.getIdentityKeyPublicBase64());
    final bobId = inMemoryUserKey(await bob.getIdentityKeyPublicBase64());

    // Bob's one-time prekey is consumed from the server when Alice fetches.
    expect(
        await transport.hasBundle(await alice.getOrCreateDeviceId()), isTrue);
    expect(await transport.hasBundle(await bob.getOrCreateDeviceId()), isTrue);

    // Alice establishes a session with Bob (X3DH) and sends the first message.
    await alice.establishSession(bobId);
    expect(await alice.hasSession(bobId), isTrue);

    final first = await alice.encrypt(bobId, 'hello bob, this is e2e');
    // First message of a session is a PreKeySignalMessage.
    expect(first.type, CiphertextMessage.prekeyType);

    // Bob decrypts the prekey message without having had a prior session.
    expect(await bob.decrypt(aliceId, first.type, first.body),
        'hello bob, this is e2e');

    // Bob replies; subsequent messages are plain SignalMessages.
    final reply = await bob.encrypt(aliceId, 'hi alice');
    expect(reply.type, CiphertextMessage.whisperType);
    expect(await alice.decrypt(bobId, reply.type, reply.body), 'hi alice');

    // Further messages in the established session (ratchet steps forward).
    final third = await alice.encrypt(bobId, 'third message');
    expect(third.type, CiphertextMessage.whisperType);
    expect(
      await bob.decrypt(aliceId, third.type, third.body),
      'third message',
    );
  });

  test('one-time prekeys are replenished when below watermark', () async {
    final transport = InMemoryKeyBundleTransport();
    final alice = E2eeManager(
      store: InMemoryE2eeStore(),
      transport: transport,
    );
    await alice.initialize();

    // Consume enough one-time prekeys to drop below the watermark.
    for (var i = 0; i < 30; i++) {
      final id = inMemoryUserKey(await alice.getIdentityKeyPublicBase64());
      await transport.fetchBundle(id);
    }

    expect(await alice.needsReplenishment(), isTrue);
    await alice.initialize();
    expect(await alice.needsReplenishment(), isFalse);
  });

  test('identity persists across restarts (same store)', () async {
    final transport = InMemoryKeyBundleTransport();
    final store = InMemoryE2eeStore();

    final first = E2eeManager(store: store, transport: transport);
    await first.initialize();
    final idBefore = await first.getIdentityKeyPublicBase64();

    // Simulate app restart: same store, new manager instance.
    final second = E2eeManager(store: store, transport: transport);
    await second.initialize();
    expect(await second.getIdentityKeyPublicBase64(), idBefore);
  });

  test('media E2EE: AES-GCM file + key delivered via Signal envelope',
      () async {
    final transport = InMemoryKeyBundleTransport();
    final alice = E2eeManager(store: InMemoryE2eeStore(), transport: transport);
    final bob = E2eeManager(store: InMemoryE2eeStore(), transport: transport);
    await alice.initialize();
    await bob.initialize();

    final aliceId = inMemoryUserKey(await alice.getIdentityKeyPublicBase64());
    final bobId = inMemoryUserKey(await bob.getIdentityKeyPublicBase64());

    // "File" to send, encrypted with a fresh AES-256-GCM key + nonce.
    final fileBytes = Uint8List.fromList(List.generate(5000, (i) => i % 256));
    final key = Uint8List.fromList(List.generate(32, (i) => i + 1));
    final nonce = Uint8List.fromList(List.generate(12, (i) => i + 100));
    final cipherFile = MediaCrypto.encrypt(key, nonce, fileBytes);

    // Key envelope delivered inside a Signal-encrypted message.
    await alice.establishSession(bobId);
    final enc = await alice.encrypt(
      bobId,
      jsonEncode({'k': base64Encode(key), 'iv': base64Encode(nonce)}),
    );
    final decrypted = await bob.decrypt(aliceId, enc.type, enc.body);
    final envelope = jsonDecode(decrypted) as Map<String, dynamic>;

    // Recipient decrypts the file using the envelope key.
    final decKey = base64Decode(envelope['k'] as String);
    final decNonce = base64Decode(envelope['iv'] as String);
    final decFile = MediaCrypto.decrypt(
      Uint8List.fromList(decKey),
      Uint8List.fromList(decNonce),
      cipherFile,
    );

    expect(decFile, orderedEquals(fileBytes));

    // Tampered ciphertext must not decrypt.
    cipherFile[0] ^= 1;
    expect(
      () => MediaCrypto.decrypt(
        Uint8List.fromList(decKey),
        Uint8List.fromList(decNonce),
        cipherFile,
      ),
      throwsA(isA<Object>()),
    );
  });

  test('security number is 60 digits and symmetric for both parties', () async {
    final transport = InMemoryKeyBundleTransport();
    final alice = E2eeManager(store: InMemoryE2eeStore(), transport: transport);
    final bob = E2eeManager(store: InMemoryE2eeStore(), transport: transport);
    await alice.initialize();
    await bob.initialize();

    final aliceId = inMemoryUserKey(await alice.getIdentityKeyPublicBase64());
    final bobId = inMemoryUserKey(await bob.getIdentityKeyPublicBase64());

    final localA = await alice.getIdentityKeyPair();
    final localB = await bob.getIdentityKeyPair();

    final gen = NumericFingerprintGenerator(5200);
    final fpAB = gen.createFor(
      0,
      utf8.encode(aliceId),
      localA.getPublicKey(),
      utf8.encode(bobId),
      localB.getPublicKey(),
    );
    final fpBA = gen.createFor(
      0,
      utf8.encode(bobId),
      localB.getPublicKey(),
      utf8.encode(aliceId),
      localA.getPublicKey(),
    );

    final numberA = fpAB.displayableFingerprint.getDisplayText();
    final numberB = fpBA.displayableFingerprint.getDisplayText();

    expect(numberA.length, 60);
    expect(numberA, numberB);
  });

  test('group sender-key round trip: distribute, encrypt, decrypt', () async {
    final alice = E2eeManager(
      store: InMemoryE2eeStore(),
      transport: InMemoryKeyBundleTransport(),
    );
    final bob = E2eeManager(
      store: InMemoryE2eeStore(),
      transport: InMemoryKeyBundleTransport(),
    );

    const groupId = 'group_abc';
    const aliceId = 'user_alice';
    const bobId = 'user_bob';

    // Alice sends the first message; Bob decrypts it using the sender-key
    // distribution message delivered in-band.
    final encrypted = await alice.encryptGroup(groupId, aliceId, 'Hello group');
    expect(encrypted, isNotNull);
    expect(encrypted!.distributionB64, isNotEmpty);

    final plaintextAtBob = await bob.decryptGroup(
      groupId,
      aliceId,
      encrypted.body,
      encrypted.distributionB64,
    );
    expect(plaintextAtBob, 'Hello group');

    // Bob's subsequent messages use his own sender-key chain.
    final bobMsg = await bob.encryptGroup(groupId, bobId, 'Hi Alice');
    expect(bobMsg, isNotNull);

    final plaintextAtAlice = await alice.decryptGroup(
      groupId,
      bobId,
      bobMsg!.body,
      bobMsg.distributionB64,
    );
    expect(plaintextAtAlice, 'Hi Alice');

    // A later message from Alice (no new distribution message) still decrypts.
    final second = await alice.encryptGroup(groupId, aliceId, 'Second msg');
    final secondPlaintext = await bob.decryptGroup(
      groupId,
      aliceId,
      second!.body,
      null,
    );
    expect(secondPlaintext, 'Second msg');
  });
}
