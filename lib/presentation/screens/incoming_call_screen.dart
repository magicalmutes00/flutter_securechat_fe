import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../data/services/rtc/call_manager.dart';
import 'call_screen.dart';

/// Full-screen incoming call notification with accept/decline actions.
class IncomingCallScreen extends StatefulWidget {
  final String peerId;
  final String peerName;
  final bool isVideoCall;

  const IncomingCallScreen({
    super.key,
    required this.peerId,
    required this.peerName,
    required this.isVideoCall,
  });

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen> {
  final CallManager _callManager = CallManager.instance;

  Future<void> _accept() async {
    _callManager.acceptIncomingCall();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => CallScreen(
          peerId: widget.peerId,
          peerName: widget.peerName,
          isVideoCall: widget.isVideoCall,
        ),
      ),
    );
  }

  Future<void> _decline() async {
    await _callManager.declineIncomingCall();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.phone_in_talk, color: Colors.white, size: 56),
            const SizedBox(height: 24),
            CircleAvatar(
              radius: 48,
              backgroundColor: AppTheme.primaryColor,
              child: Text(
                widget.peerName.isEmpty
                    ? '?'
                    : widget.peerName[0].toUpperCase(),
                style: const TextStyle(color: Colors.white, fontSize: 40),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              widget.peerName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.isVideoCall
                  ? 'Incoming video call...'
                  : 'Incoming voice call...',
              style: TextStyle(color: Colors.grey[400]),
            ),
            const SizedBox(height: 64),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Column(
                  children: [
                    CircleAvatar(
                      radius: 32,
                      backgroundColor: Colors.red,
                      child: IconButton(
                        icon: const Icon(Icons.call_end, color: Colors.white),
                        onPressed: _decline,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Decline',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
                Column(
                  children: [
                    CircleAvatar(
                      radius: 32,
                      backgroundColor: Colors.green,
                      child: IconButton(
                        icon: const Icon(Icons.call, color: Colors.white),
                        onPressed: _accept,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Accept',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
