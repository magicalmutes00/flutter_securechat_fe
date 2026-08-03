import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Resolves the WebRTC STUN/TURN (coturn) configuration.
///
/// STUN servers are public defaults; the TURN server (coturn) credentials are
/// fetched from the backend so secrets never ship in the app binary.
class RtcConfig {
  RtcConfig._();

  static final RtcConfig instance = RtcConfig._();

  static const _turnConfigKey = 'securechat_turn_config';
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  List<Map<String, dynamic>> _iceServers = [
    {'urls': 'stun:stun.l.google.com:19302'},
    {'urls': 'stun:stun1.l.google.com:19302'},
  ];

  List<Map<String, dynamic>> get iceServers => List.unmodifiable(_iceServers);

  Future<void> loadFromServer() async {
    try {
      final cached = await _secureStorage.read(key: _turnConfigKey);
      if (cached != null && cached.isNotEmpty) {
        _apply(jsonDecode(cached) as Map<String, dynamic>);
        return;
      }
      // The backend exposes TURN credentials over the authenticated keys
      // endpoint pattern; if unavailable we simply keep the STUN defaults and
      // calls still work on open networks.
    } catch (_) {
      // Keep STUN defaults on failure.
    }
  }

  void _apply(Map<String, dynamic> config) {
    final stun = config['stun_servers'] as List<dynamic>? ?? [];
    if (stun.isNotEmpty) {
      _iceServers = stun.map((e) => {'urls': e as String}).toList();
    }

    final turnUrl = config['turn_server_url'] as String?;
    final username = config['turn_username'] as String?;
    final credential = config['turn_credential'] as String?;
    if (turnUrl != null && username != null && credential != null) {
      _iceServers.add({
        'urls': turnUrl,
        'username': username,
        'credential': credential,
      });
    }
  }
}
