import 'dart:convert';

import 'package:convert/convert.dart';

import 'key_bundle_transport.dart';

/// Stable identifier for a user derived from their identity key public bytes.
///
/// Mirrors how the key server ties a bundle to an authenticated account; the
/// identity key uniquely identifies a client.
String inMemoryUserKey(String identityKeyPublic) {
  final bytes = base64Decode(identityKeyPublic);
  return hex.encode(bytes).substring(0, 16);
}

/// In-memory [KeyBundleTransport] used to validate the E2EE round trip without
/// a network. Stores each user's published bundle and consumes one-time
/// prekeys exactly like the key server would.
class InMemoryKeyBundleTransport implements KeyBundleTransport {
  final Map<String, Map<String, dynamic>> _bundles = {};

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
    final name = inMemoryUserKey(identityKeyPublic);
    _bundles[name] = {
      'device_id': deviceId,
      'registration_id': registrationId,
      'identity_key_public': identityKeyPublic,
      'signed_prekey_id': signedPrekeyId,
      'signed_prekey_public': signedPrekeyPublic,
      'signed_prekey_signature': signedPrekeySignature,
      '_one_time_prekeys': List<String>.from(oneTimePrekeys),
    };
  }

  @override
  Future<void> replenishOneTimePrekeys({
    required String deviceId,
    required List<String> oneTimePrekeys,
  }) async {
    for (final user in _bundles.values) {
      (user['_one_time_prekeys'] as List).addAll(oneTimePrekeys);
    }
  }

  @override
  Future<RemoteKeyBundle?> fetchBundle(String userId) async {
    // In tests the "user id" is matched by the identity key name.
    final bundle = _bundles[userId];
    if (bundle == null) return null;

    final prekeys = (bundle['_one_time_prekeys'] as List).cast<String>();
    final oneTimePrekey = prekeys.isEmpty ? null : prekeys.removeAt(0);

    return RemoteKeyBundle(
      registrationId: bundle['registration_id'] as int? ?? 1,
      deviceId: 1,
      identityKeyPublic: bundle['identity_key_public'] as String,
      signedPrekeyId: bundle['signed_prekey_id'] as int,
      signedPrekeyPublic: bundle['signed_prekey_public'] as String,
      signedPrekeySignature: bundle['signed_prekey_signature'] as String,
      oneTimePrekeyId: oneTimePrekey == null ? null : 1,
      oneTimePrekeyPublic: oneTimePrekey,
    );
  }

  @override
  Future<bool> hasBundle(String deviceId) async =>
      _bundles.values.any((b) => b['device_id'] == deviceId);

  @override
  Future<int> remainingOneTimePrekeys(String deviceId) async {
    for (final bundle in _bundles.values) {
      if (bundle['device_id'] == deviceId) {
        return (bundle['_one_time_prekeys'] as List).length;
      }
    }
    return 0;
  }
}
