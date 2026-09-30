import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Provides a per-installation AES-256 key used to encrypt Hive boxes at rest.
///
/// The key itself is never stored on disk in plaintext: it is generated once
/// with a CSPRNG and kept inside the platform keychain/keystore via
/// [FlutterSecureStorage]. Without the key the cached messages, Signal session
/// state and prekeys on disk are unreadable.
class AtRestKey {
  static const String _keyStorageName = 'securechat_at_rest_key';

  static final AtRestKey _instance = AtRestKey._internal();
  factory AtRestKey() => _instance;

  AtRestKey._internal();

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  HiveAesCipher? _cipher;
  List<int>? _keyBytes;

  /// Resolves (and lazily creates) the raw AES-256 key bytes. Used to encrypt
  /// cached media files (see [MediaCacheService]) with the same key that
  /// protects the Hive boxes.
  Future<List<int>> getOrCreateKeyBytes() async {
    final existing = _keyBytes;
    if (existing != null) return existing;

    final storedKey = await _secureStorage.read(key: _keyStorageName);
    List<int> keyBytes;
    if (storedKey != null && storedKey.isNotEmpty) {
      keyBytes = base64Decode(storedKey);
    } else {
      keyBytes = _generateKey();
      await _secureStorage.write(
        key: _keyStorageName,
        value: base64Encode(keyBytes),
      );
    }

    _keyBytes = keyBytes;
    return keyBytes;
  }

  /// Resolves (and lazily creates) the AES-256 key, wrapped in the cipher Hive
  /// boxes must be opened with.
  Future<HiveAesCipher> getOrCreateCipher() async {
    final existing = _cipher;
    if (existing != null) return existing;

    final keyBytes = await getOrCreateKeyBytes();
    final cipher = HiveAesCipher(keyBytes);
    _cipher = cipher;
    return cipher;
  }

  List<int> _generateKey() {
    final random = Random.secure();
    return List<int>.generate(32, (_) => random.nextInt(256));
  }
}
