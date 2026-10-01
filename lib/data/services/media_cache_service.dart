import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import 'at_rest_key.dart';
import 'e2ee/media_crypto.dart';

/// Two-tier cache for media blobs (avatars, status images, decrypted chat
/// attachments).
///
/// - Tier 1: in-memory map for the current session.
/// - Tier 2: files in the app's **cache** directory, encrypted at rest with
///   the per-installation [AtRestKey] (AES-256-GCM, `nonce || ciphertext`
///   layout). Cached plaintext never touches disk unencrypted.
///
/// Keys are caller-defined (message file path, avatar URL, ...); they are
/// hashed to stable file names. The OS may reclaim the cache directory at any
/// time — every read must have a network fallback.
class MediaCacheService {
  static final MediaCacheService _instance = MediaCacheService._internal();
  factory MediaCacheService() => _instance;

  MediaCacheService._internal();

  static const int _maxEntries = 500;

  final Map<String, Uint8List> _memory = {};
  final Random _random = Random.secure();
  Directory? _dir;
  List<int>? _keyBytes;

  /// Cache generation: bumped when the meaning of a cached entry changes.
  /// v1 entries may hold UNDECRYPTED ciphertext (cached by the broken
  /// sender path that skipped decryption without a media key) — serving
  /// them renders nothing, forever, since cache hits bypass decrypt. v2
  /// entries predate fail-closed media loading and can have the same flaw.
  static const _generation = 'v3';

  Future<Directory> _cacheDir() async {
    final existing = _dir;
    if (existing != null) return existing;
    final base = await getApplicationCacheDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}media');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    } else {
      // One-time migration: this directory is ours alone, so any entry
      // predating the current generation is dropped rather than served.
      final marker = File('${dir.path}${Platform.pathSeparator}.$_generation');
      if (!await marker.exists()) {
        for (final entry in dir.listSync()) {
          try {
            await entry.delete(recursive: true);
          } catch (_) {}
        }
        try {
          await marker.writeAsString(_generation);
        } catch (_) {}
      }
    }
    _dir = dir;
    return dir;
  }

  Future<List<int>> _key() async {
    return _keyBytes ??= await AtRestKey().getOrCreateKeyBytes();
  }

  String _fileName(String key) => sha256.convert(utf8.encode(key)).toString();

  /// Returns the cached bytes for [key], or null on a miss.
  Future<Uint8List?> read(String key) async {
    final hot = _memory[key];
    if (hot != null) return hot;

    try {
      final file = File(
          '${(await _cacheDir()).path}${Platform.pathSeparator}${_fileName(key)}');
      if (!await file.exists()) return null;

      final blob = await file.readAsBytes();
      if (blob.length <= MediaCrypto.nonceLength) return null;

      final keyBytes = await _key();
      final nonce = Uint8List.sublistView(blob, 0, MediaCrypto.nonceLength);
      final ciphertext = Uint8List.sublistView(blob, MediaCrypto.nonceLength);
      final plain = MediaCrypto.decrypt(
        Uint8List.fromList(keyBytes),
        Uint8List.fromList(nonce),
        ciphertext,
      );

      // LRU-ish eviction on the in-memory tier.
      if (_memory.length >= _maxEntries) _memory.remove(_memory.keys.first);
      _memory[key] = plain;
      return plain;
    } catch (_) {
      // Corrupt/incompatible entry — treat as a cache miss.
      return null;
    }
  }

  /// Stores [bytes] under [key], overwriting any previous entry.
  Future<void> write(String key, Uint8List bytes) async {
    try {
      final keyBytes = await _key();
      final nonce = Uint8List(MediaCrypto.nonceLength);
      for (var i = 0; i < nonce.length; i++) {
        nonce[i] = _random.nextInt(256);
      }
      final cipher = MediaCrypto.encrypt(
        Uint8List.fromList(keyBytes),
        nonce,
        bytes,
      );

      final file = File(
          '${(await _cacheDir()).path}${Platform.pathSeparator}${_fileName(key)}');
      final blob = BytesBuilder()
        ..add(nonce)
        ..add(cipher);
      await file.writeAsBytes(blob.toBytes(), flush: true);

      if (_memory.length >= _maxEntries) _memory.remove(_memory.keys.first);
      _memory[key] = bytes;
    } catch (_) {
      // Caching is best-effort; never fail the caller because of it.
    }
  }

  /// Deletes every cached media file (called on logout).
  Future<void> clear() async {
    _memory.clear();
    try {
      final dir = _dir;
      if (dir != null && await dir.exists()) {
        await dir.delete(recursive: true);
      }
      _dir = null;
    } catch (_) {
      // Best-effort.
    }
  }
}
