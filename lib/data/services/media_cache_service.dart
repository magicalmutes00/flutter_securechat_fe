import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

/// Two-tier cache for media blobs (avatars, status images, chat attachments).
///
/// - Tier 1: in-memory map for the current session.
/// - Tier 2: raw files in the app's **cache** directory (`media_v2`, so
///   entries written by the old encrypted layout are never misread).
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
  Directory? _dir;

  Future<Directory> _cacheDir() async {
    final existing = _dir;
    if (existing != null) return existing;
    final base = await getApplicationCacheDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}media_v2');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _dir = dir;
    return dir;
  }

  String _fileName(String key) =>
      sha256.convert(utf8.encode(key)).toString();

  /// Returns the cached bytes for [key], or null on a miss.
  Future<Uint8List?> read(String key) async {
    final hot = _memory[key];
    if (hot != null) return hot;

    try {
      final file = File('${(await _cacheDir()).path}${Platform.pathSeparator}${_fileName(key)}');
      if (!await file.exists()) return null;

      final plain = await file.readAsBytes();
      if (plain.isEmpty) return null;

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
      final file = File('${(await _cacheDir()).path}${Platform.pathSeparator}${_fileName(key)}');
      await file.writeAsBytes(bytes, flush: true);

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
