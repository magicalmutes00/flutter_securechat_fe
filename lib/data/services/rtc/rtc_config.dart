import 'package:flutter/foundation.dart';

import '../api_client.dart';

/// Resolves the WebRTC STUN/TURN (coturn) configuration.
///
/// The full iceServers list is fetched from the backend (`GET /api/rtc/config`)
/// so STUN/TURN endpoints and credentials are configured server-side and never
/// ship in the app binary. Until the fetch succeeds, public STUN defaults are
/// used so calls still work on open networks.
class RtcConfig {
  RtcConfig._();

  static final RtcConfig instance = RtcConfig._();

  List<Map<String, dynamic>> _iceServers = [
    {'urls': 'stun:stun.l.google.com:19302'},
    {'urls': 'stun:stun1.l.google.com:19302'},
  ];

  List<Map<String, dynamic>> get iceServers => List.unmodifiable(_iceServers);

  @visibleForTesting
  set iceServersForTesting(List<Map<String, dynamic>> servers) {
    _iceServers = servers;
  }

  Future<void> loadFromServer() async {
    try {
      final data = await ApiClient().getRtcConfig();
      final servers = data['ice_servers'] as List<dynamic>?;
      if (servers == null || servers.isEmpty) return;

      _iceServers = servers
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      // Keep STUN defaults on failure — calls still work on open networks.
    }
  }
}
