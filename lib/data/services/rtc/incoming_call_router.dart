import 'package:flutter/material.dart';

import '../../../presentation/screens/incoming_call_screen.dart';
import 'call_manager.dart';

/// Global navigator key used to surface cross-cutting UI such as incoming
/// calls without threading a BuildContext through the signaling layer.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// Bridges [CallManager]'s signaling callbacks into the widget tree.
///
/// When a `call_ring` signal arrives, it pushes the [IncomingCallScreen] on top
/// of whatever route is currently visible (unless the user is already in a
/// call).
class IncomingCallRouter {
  IncomingCallRouter._();

  static bool _initialized = false;

  static void init(BuildContext context) {
    if (_initialized) return;
    _initialized = true;

    CallManager.instance.onIncomingCall = (peerId, isVideo) {
      final navigator = appNavigatorKey.currentState;
      if (navigator == null) return;

      if (CallManager.instance.isInCall) {
        // Already on a call: auto-decline the new one.
        CallManager.instance.declineIncomingCall();
        return;
      }

      // The signaling layer has the peer id; the UI needs a display name.
      final name = CallManager.instance.displayNameFor(peerId) ?? 'Caller';

      navigator.push(
        MaterialPageRoute(
          builder: (_) => IncomingCallScreen(
            peerId: peerId,
            peerName: name,
            isVideoCall: isVideo,
          ),
        ),
      );
    };
  }
}
