import 'package:hive_flutter/hive_flutter.dart';

import '../at_rest_key.dart';

/// A simple string key/value backend used to persist Signal protocol state
/// (sessions, prekeys, trusted identities).
///
/// Kept behind an interface so tests can run against an in-memory backend
/// without requiring a device or Hive initialization.
abstract class E2eeKeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// In-memory implementation used by tests.
class InMemoryE2eeStore implements E2eeKeyValueStore {
  final Map<String, String> _data = {};

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, String value) async => _data[key] = value;

  @override
  Future<void> delete(String key) async => _data.remove(key);
}

/// Persistent implementation backed by a dedicated Hive box so Signal state
/// survives app restarts and is scoped per user.
class HiveE2eeStore implements E2eeKeyValueStore {
  HiveE2eeStore(this._userId);

  final String _userId;
  Box<String>? _box;

  Future<void> init() async {
    // Each signed-in user gets its own box so switching accounts does not leak
    // key material or session state between users. The box is encrypted at
    // rest with a device key kept in the platform keychain.
    final cipher = await AtRestKey().getOrCreateCipher();
    _box = await Hive.openBox<String>(
      'securechat_e2ee_$_userId',
      encryptionCipher: cipher,
    );
  }

  Box<String> get _db {
    final box = _box;
    if (box == null) {
      throw StateError('HiveE2eeStore.open() must be called first');
    }
    return box;
  }

  @override
  Future<String?> read(String key) async => _db.get(key);

  @override
  Future<void> write(String key, String value) async => _db.put(key, value);

  @override
  Future<void> delete(String key) async => _db.delete(key);

  Future<void> clear() async {
    await _db.clear();
  }
}
