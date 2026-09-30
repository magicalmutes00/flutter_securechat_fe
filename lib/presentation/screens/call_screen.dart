import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../data/services/rtc/call_manager.dart';

class CallScreen extends StatefulWidget {
  final String peerId;
  final String peerName;
  final bool isVideoCall;

  const CallScreen({
    super.key,
    required this.peerId,
    required this.peerName,
    required this.isVideoCall,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final CallManager _callManager = CallManager.instance;
  bool _isConnected = false;
  bool _isMuted = false;
  bool _cameraEnabled = true;
  bool _isFrontCamera = true;

  @override
  void initState() {
    super.initState();
    _callManager.onCallConnected = () {
      if (mounted) setState(() => _isConnected = true);
    };
    _callManager.onRemoteVideoAdded = () {
      if (mounted && widget.isVideoCall) setState(() {});
    };
    _callManager.onCallEnded = () {
      if (mounted) Navigator.of(context).pop();
    };
    _callManager.startCall(
      peerId: widget.peerId,
      isVideo: widget.isVideoCall,
    );
  }

  @override
  void dispose() {
    _callManager.onCallConnected = null;
    _callManager.onRemoteVideoAdded = null;
    _callManager.onCallEnded = null;
    super.dispose();
  }

  String get _title => widget.peerName;

  Future<void> _endCall() async {
    await _callManager.endCall();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: widget.isVideoCall
                    ? Stack(
                        children: [
                          Positioned.fill(
                            child: RTCVideoView(
                              _callManager.remoteRenderer,
                              mirror: false,
                              objectFit: RTCVideoViewObjectFit
                                  .RTCVideoViewObjectFitCover,
                            ),
                          ),
                          Positioned(
                            bottom: 16,
                            right: 16,
                            width: 110,
                            height: 160,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: RTCVideoView(
                                _callManager.localRenderer,
                                mirror: true,
                                objectFit: RTCVideoViewObjectFit
                                    .RTCVideoViewObjectFitCover,
                              ),
                            ),
                          ),
                        ],
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircleAvatar(
                            radius: 60,
                            backgroundColor: AppPalette.blue600,
                            child: Text(
                              _title.isEmpty ? '?' : _title[0].toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 48,
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            _title,
                            style: context.text.headlineLarge?.copyWith(
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _isConnected ? 'Call connected' : 'Ringing...',
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ],
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 32),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _CallControlButton(
                    icon: _isMuted ? Icons.mic_off : Icons.mic,
                    label: _isMuted ? 'Unmute' : 'Mute',
                    onTap: () async {
                      await _callManager.toggleMute();
                      if (mounted) setState(() => _isMuted = !_isMuted);
                    },
                  ),
                  if (widget.isVideoCall)
                    _CallControlButton(
                      icon:
                          _cameraEnabled ? Icons.videocam : Icons.videocam_off,
                      label: _cameraEnabled ? 'Camera off' : 'Camera on',
                      onTap: () async {
                        await _callManager.toggleCamera();
                        if (mounted) {
                          setState(() => _cameraEnabled = !_cameraEnabled);
                        }
                      },
                    ),
                  if (widget.isVideoCall)
                    _CallControlButton(
                      icon: _isFrontCamera
                          ? Icons.camera_rear
                          : Icons.camera_front,
                      label: 'Switch',
                      onTap: () async {
                        await _callManager.switchCamera();
                        if (mounted) {
                          setState(() => _isFrontCamera = !_isFrontCamera);
                        }
                      },
                    ),
                  _CallControlButton(
                    icon: Icons.call_end,
                    label: 'End',
                    isEndCall: true,
                    onTap: _endCall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CallControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isEndCall;

  const _CallControlButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isEndCall = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        CircleAvatar(
          radius: 28,
          backgroundColor:
              isEndCall ? context.colors.error : Colors.white24,
          child: IconButton(
            icon: Icon(icon, color: Colors.white),
            onPressed: onTap,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }
}
