import '../../services/api_client.dart';

/// A recipient's public key bundle as returned by the key server, along with a
/// single consumable one-time prekey.
class RemoteKeyBundle {
  const RemoteKeyBundle({
    required this.registrationId,
    required this.deviceId,
    required this.identityKeyPublic,
    required this.signedPrekeyId,
    required this.signedPrekeyPublic,
    required this.signedPrekeySignature,
    this.oneTimePrekeyId,
    this.oneTimePrekeyPublic,
  });

  final int registrationId;
  final int deviceId;
  final String identityKeyPublic;
  final int signedPrekeyId;
  final String signedPrekeyPublic;
  final String signedPrekeySignature;
  final int? oneTimePrekeyId;
  final String? oneTimePrekeyPublic;
}

/// Transport responsible for uploading/fetching key bundles from the server.
///
/// An interface so the E2EE manager can be exercised in tests against an
/// in-memory transport instead of the real [ApiClient].
abstract class KeyBundleTransport {
  Future<void> uploadBundle({
    required String deviceId,
    required int registrationId,
    required String identityKeyPublic,
    required int signedPrekeyId,
    required String signedPrekeyPublic,
    required String signedPrekeySignature,
    required List<String> oneTimePrekeys,
  });

  Future<void> replenishOneTimePrekeys({
    required String deviceId,
    required List<String> oneTimePrekeys,
  });

  Future<RemoteKeyBundle?> fetchBundle(String userId);

  Future<bool> hasBundle(String deviceId);

  /// Number of one-time prekeys the key server still holds for the local
  /// user/device. Used to decide when to replenish.
  Future<int> remainingOneTimePrekeys(String deviceId);
}

/// [KeyBundleTransport] backed by the REST API.
class ApiKeyBundleTransport implements KeyBundleTransport {
  final ApiClient _api = ApiClient();

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
    await _api.uploadKeyBundle(
      deviceId: deviceId,
      registrationId: registrationId,
      identityKeyPublic: identityKeyPublic,
      signedPrekeyId: signedPrekeyId,
      signedPrekeyPublic: signedPrekeyPublic,
      signedPrekeySignature: signedPrekeySignature,
      oneTimePrekeys: oneTimePrekeys,
    );
  }

  @override
  Future<void> replenishOneTimePrekeys({
    required String deviceId,
    required List<String> oneTimePrekeys,
  }) async {
    await _api.addOneTimePrekeys(
      deviceId: deviceId,
      oneTimePrekeys: oneTimePrekeys,
    );
  }

  @override
  Future<RemoteKeyBundle?> fetchBundle(String userId) async {
    final data = await _api.getKeyBundle(userId);
    if (data == null) return null;
    return RemoteKeyBundle(
      registrationId: data['registration_id'] as int? ?? 0,
      deviceId: data['device_id'] as int? ?? 1,
      identityKeyPublic: data['identity_key_public'] as String,
      signedPrekeyId: data['signed_prekey_id'] as int,
      signedPrekeyPublic: data['signed_prekey_public'] as String,
      signedPrekeySignature: data['signed_prekey_signature'] as String,
      oneTimePrekeyId: data['one_time_prekey_id'] as int?,
      oneTimePrekeyPublic: data['one_time_prekey_public'] as String?,
    );
  }

  @override
  Future<bool> hasBundle(String deviceId) async {
    return (await _api.getKeyBundleStatus(deviceId))['has_bundle'] as bool? ??
        false;
  }

  @override
  Future<int> remainingOneTimePrekeys(String deviceId) async {
    return (await _api.getKeyBundleStatus(deviceId))['one_time_prekey_count']
            as int? ??
        0;
  }
}
