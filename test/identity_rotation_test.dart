import 'package:flutter_test/flutter_test.dart';
import 'package:secure_chat/data/services/e2ee/e2ee_key_value_store.dart';
import 'package:secure_chat/data/services/e2ee/e2ee_manager.dart';
import 'package:secure_chat/data/services/e2ee/key_bundle_transport.dart';

/// Test transport keyed by stable user id, like the real key server: each
/// user's latest upload wins, and every fetch pops one one-time prekey.
class _StableTransport implements KeyBundleTransport {
  final _byDevice = <String, Map<String, dynamic>>{};
  final _userOfDevice = <String, String>{};

  void bindUser(String userId, String deviceId) {
    _userOfDevice[deviceId] = userId;
  }

  Map<String, dynamic>? _latestFor(String userId) {
    Map<String, dynamic>? found;
    for (final entry in _byDevice.entries) {
      if (_userOfDevice[entry.key] == userId) found = entry.value;
    }
    return found;
  }

  @override
  Future<void> uploadBundle({
    required String deviceId,
    required int registrationId,
    required String identityKeyPublic,
    required int signedPrekeyId,
    required String signedPrekeyPublic,
    required String signedPrekeySignature,
    required List<String> oneTimePrekeys,
  }) async {
    // Like the real server, ids are assigned positionally (the uploader
    // generated them 1..N in order), so the reported id always matches the
    // private half the recipient holds.
    var nextId = 0;
    _byDevice[deviceId] = {
      'registration_id': registrationId,
      'identity_key_public': identityKeyPublic,
      'signed_prekey_id': signedPrekeyId,
      'signed_prekey_public': signedPrekeyPublic,
      'signed_prekey_signature': signedPrekeySignature,
      'prekeys': [
        for (final public in oneTimePrekeys) (id: ++nextId, public: public),
      ],
    };
  }

  @override
  Future<void> replenishOneTimePrekeys({
    required String deviceId,
    required List<String> oneTimePrekeys,
  }) async {
    final existing =
        _byDevice[deviceId]?['prekeys'] as List<({int id, String public})>;
    var nextId =
        existing.fold(0, (max, e) => e.id > max ? e.id : max);
    for (final public in oneTimePrekeys) {
      existing.add((id: ++nextId, public: public));
    }
  }

  @override
  Future<RemoteKeyBundle?> fetchBundle(String userId) async {
    final b = _latestFor(userId);
    if (b == null) return null;
    final prekeys = b['prekeys'] as List<({int id, String public})>;
    final otp = prekeys.isEmpty ? null : prekeys.removeAt(0);
    return RemoteKeyBundle(
      registrationId: b['registration_id'] as int,
      deviceId: 1,
      identityKeyPublic: b['identity_key_public'] as String,
      signedPrekeyId: b['signed_prekey_id'] as int,
      signedPrekeyPublic: b['signed_prekey_public'] as String,
      signedPrekeySignature: b['signed_prekey_signature'] as String,
      oneTimePrekeyId: otp?.id,
      oneTimePrekeyPublic: otp?.public,
    );
  }

  @override
  Future<bool> hasBundle(String deviceId) async =>
      _byDevice.containsKey(deviceId);

  @override
  Future<int> remainingOneTimePrekeys(String deviceId) async =>
      (_byDevice[deviceId]?['prekeys'] as List?)?.length ?? 0;
}

Future<E2eeManager> _freshUser(_StableTransport t, String userId) async {
  final manager = E2eeManager(store: InMemoryE2eeStore(), transport: t);
  await manager.initialize();
  t.bindUser(userId, await manager.getOrCreateDeviceId());
  return manager;
}

bool _isUntrustedIdentity(Object e) =>
    e.runtimeType.toString().contains('UntrustedIdentity');

void main() {
  group('identity rotation after peer reinstall', () {
    test('baseline exchange works before any reinstall', () async {
      final t = _StableTransport();
      final alice = await _freshUser(t, 'alice');
      final bob = await _freshUser(t, 'bob');

      await alice.establishSession('bob');
      final enc = await alice.encrypt('bob', 'hello');
      expect(await bob.decrypt('alice', enc.type, enc.body), 'hello');
    });

    test('stale trust blocks re-establishment; rotation heals it', () async {
      final t = _StableTransport();
      final alice = await _freshUser(t, 'alice');
      var bob = await _freshUser(t, 'bob');

      await alice.establishSession('bob');
      final before = await alice.encrypt('bob', 'before');
      expect(await bob.decrypt('alice', before.type, before.body), 'before');

      // Bob reinstalls: brand-new store/identity, fresh upload under the
      // same stable user id. Alice still trusts the old identity.
      bob = await _freshUser(t, 'bob');
      await alice.resetSession('bob');

      // Re-establishing now fails: the served bundle carries Bob's NEW
      // identity, which Alice's store does not trust.
      await expectLater(
        alice.establishSession('bob'),
        throwsA(predicate(_isUntrustedIdentity)),
      );

      // Rotate trust to the published bundle and rebuild: messaging resumes
      // and the reinstalled Bob decrypts.
      expect(await alice.rotatePeerIdentity('bob'), isTrue);
      await alice.establishSession('bob');
      final after = await alice.encrypt('bob', 'after reinstall');
      expect(await bob.decrypt('alice', after.type, after.body),
          'after reinstall');
    });

    test('rotation refuses unknown users and inconsistent bundles', () async {
      final t = _StableTransport();
      final alice = await _freshUser(t, 'alice');
      await _freshUser(t, 'bob');

      // Nobody published for carol: nothing to rotate to.
      expect(await alice.rotatePeerIdentity('carol'), isFalse);

      // Tamper with Bob's published signature: rotation must refuse rather
      // than trust attacker-shaped material.
      final deviceId = await () async {
        // Find Bob's device entry and corrupt its signature.
        for (final entry in t._byDevice.entries) {
          if (t._userOfDevice[entry.key] == 'bob') return entry.key;
        }
        throw StateError('no bob device');
      }();
      final fields = t._byDevice[deviceId]!;
      final good = fields['signed_prekey_signature'] as String;
      // Flip a middle character to another valid base64 char: still
      // decodable, but the signature no longer verifies.
      const idx = 10;
      final tampered = good.substring(0, idx) +
          (good[idx] == 'A' ? 'B' : 'A') +
          good.substring(idx + 1);
      fields['signed_prekey_signature'] = tampered;
      expect(await alice.rotatePeerIdentity('bob'), isFalse);
    });
  });
}
