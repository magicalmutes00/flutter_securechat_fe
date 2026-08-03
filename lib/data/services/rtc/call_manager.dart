import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../websocket_service.dart';
import 'rtc_config.dart';

/// Manages a single WebRTC voice/video call: acquiring local media,
/// negotiating SDP/ICE over the existing authenticated WebSocket, and rendering
/// remote tracks.
///
/// Media never transits the server — signaling is relayed via WebSocket while
/// audio/video flows peer-to-peer (or through TURN when a direct path is
/// blocked).
class CallManager {
  CallManager._internal();

  static final CallManager instance = CallManager._internal();

  final WebSocketService _ws = WebSocketService();

  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  StreamSubscription? _signalSub;

  bool _isCaller = false;
  String _peerId = '';
  bool _isVideoCall = false;

  bool get isInCall => _pc != null;

  /// Display-name lookup used by the incoming-call router. Callers register a
  /// peer->name mapping (e.g. the currently open chat) so the ring screen can
  /// show a friendly name.
  String? Function(String peerId)? nameResolver;

  String? displayNameFor(String peerId) => nameResolver?.call(peerId);

  /// Callbacks fired by [CallManager], consumed by the call UI.
  void Function(String peerId, bool isVideo)? onIncomingCall;
  void Function()? onCallConnected;
  void Function()? onCallEnded;
  void Function()? onRemoteVideoAdded;

  RTCVideoRenderer localRenderer = RTCVideoRenderer();
  RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

  Future<void> init() async {
    await RtcConfig.instance.loadFromServer();
    await localRenderer.initialize();
    await remoteRenderer.initialize();
    await _signalSub?.cancel();
    _signalSub = _ws.callSignalStream.listen(_handleSignal);
  }

  // ---------------------------------------------------------------------------
  // Outbound call
  // ---------------------------------------------------------------------------

  Future<void> startCall({
    required String peerId,
    required bool isVideo,
  }) async {
    _isCaller = true;
    _peerId = peerId;
    _isVideoCall = isVideo;

    _ws.sendCallRing(peerId, isVideo: isVideo);
    _ws.sendCallAccept(peerId);

    await _createPeerConnection();
    await _getLocalMedia();
    await _negotiateOffer();
  }

  Future<void> acceptIncomingCall() async {
    _isCaller = false;
    _ws.sendCallAccept(_peerId);
    await _createPeerConnection();
    await _getLocalMedia();
  }

  Future<void> declineIncomingCall() async {
    _ws.sendCallDecline(_peerId);
    _cleanup();
  }

  Future<void> endCall() async {
    _ws.sendCallEnd(_peerId);
    _cleanup();
  }

  // ---------------------------------------------------------------------------
  // Signaling handlers
  // ---------------------------------------------------------------------------

  Future<void> _handleSignal(Map<String, dynamic> data) async {
    final type = data['type'] as String?;
    final senderId = data['sender_id'] as String?;
    if (senderId == null) return;

    switch (type) {
      case 'call_ring':
        _peerId = senderId;
        _isVideoCall = data['is_video'] as bool? ?? false;
        onIncomingCall?.call(senderId, _isVideoCall);
        break;
      case 'call_offer':
        if (_isCaller) break;
        await _createPeerConnection();
        await _setRemoteDescription(
          sdp: data['sdp'] as String,
          isOffer: true,
        );
        break;
      case 'call_answer':
        if (!_isCaller) break;
        await _setRemoteDescription(
          sdp: data['sdp'] as String,
          isOffer: false,
        );
        break;
      case 'call_ice':
        await _addIceCandidate(data);
        break;
      case 'call_accept':
        // The callee has accepted; the caller's offer is already negotiating.
        break;
      case 'call_decline':
        onCallEnded?.call();
        _cleanup();
        break;
      case 'call_end':
        onCallEnded?.call();
        _cleanup();
        break;
    }
  }

  Future<void> _setRemoteDescription({
    required String sdp,
    required bool isOffer,
  }) async {
    if (_pc == null) return;

    await _pc!.setRemoteDescription(
        RTCSessionDescription(sdp, isOffer ? 'offer' : 'answer'));

    if (isOffer) {
      final answer = await _pc!.createAnswer();
      await _pc!.setLocalDescription(answer);
      final answerSdp = answer.sdp;
      if (answerSdp != null) {
        _ws.sendCallAnswer(_peerId, answerSdp);
      }
    }
  }

  Future<void> _addIceCandidate(Map<String, dynamic> data) async {
    final candidate = data['candidate'] as String?;
    if (candidate == null || candidate.isEmpty) return;
    if (_pc == null) return;
    await _pc!.addCandidate(
      RTCIceCandidate(
        candidate,
        data['sdp_mid'] as String? ?? '',
        data['sdp_mline_index'] as int? ?? 0,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Media & negotiation
  // ---------------------------------------------------------------------------

  Future<void> _createPeerConnection() async {
    if (_pc != null) return;

    final config = {
      'iceServers': RtcConfig.instance.iceServers,
    };
    _pc = await createPeerConnection(config, {
      'mandatory': {},
      'optional': [
        {'DtlsSrtpKeyAgreement': true},
      ],
    });

    _pc!.onIceCandidate = (candidate) {
      final candidateValue = candidate.candidate;
      if (candidateValue == null) return;
      _ws.sendCallIce(
        _peerId,
        candidateValue,
        candidate.sdpMid ?? '',
        candidate.sdpMLineIndex ?? 0,
      );
    };

    _pc!.onTrack = (event) {
      if (event.track.kind == 'video' || event.track.kind == 'audio') {
        final stream = event.streams.isNotEmpty ? event.streams.first : null;
        if (stream != null) {
          _remoteStream = stream;
          remoteRenderer.srcObject = stream;
          onRemoteVideoAdded?.call();
        }
      }
    };

    _pc!.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        onCallConnected?.call();
      } else if (state ==
              RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        onCallEnded?.call();
        _cleanup();
      }
    };
  }

  Future<void> _getLocalMedia() async {
    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': _isVideoCall
          ? {
              'facingMode': 'user',
              'width': 1280,
              'height': 720,
            }
          : false,
    });

    for (final track in _localStream!.getTracks()) {
      await _pc!.addTrack(track, _localStream!);
    }
    localRenderer.srcObject = _localStream;
  }

  Future<void> _negotiateOffer() async {
    final offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);
    final offerSdp = offer.sdp;
    if (offerSdp != null) {
      _ws.sendCallSdp(_peerId, offerSdp);
    }
  }

  Future<void> toggleMute() async {
    for (final track
        in _localStream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = !track.enabled;
    }
  }

  Future<void> toggleCamera() async {
    for (final track
        in _localStream?.getVideoTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = !track.enabled;
    }
  }

  Future<void> switchCamera() async {
    for (final track
        in _localStream?.getVideoTracks() ?? <MediaStreamTrack>[]) {
      await track.switchCamera();
    }
  }

  void _cleanup() {
    _localStream?.getTracks().forEach((t) => t.stop());
    _localStream?.dispose();
    _remoteStream?.dispose();
    _pc?.dispose();
    _localStream = null;
    _remoteStream = null;
    _pc = null;
    _isCaller = false;
  }
}
