import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/constants/app_constants.dart';
import '../models/message_model.dart';

class WebSocketService {
  static final WebSocketService _instance = WebSocketService._internal();
  factory WebSocketService() => _instance;

  WebSocketChannel? _channel;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  final _messageController = StreamController<Message>.broadcast();
  final _groupMessageController = StreamController<Message>.broadcast();
  final _typingController = StreamController<Map<String, dynamic>>.broadcast();
  final _groupTypingController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _statusController = StreamController<Map<String, dynamic>>.broadcast();
  final _callController = StreamController<Map<String, dynamic>>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();

  Stream<Message> get messageStream => _messageController.stream;
  Stream<Message> get groupMessageStream => _groupMessageController.stream;
  Stream<Map<String, dynamic>> get typingStream => _typingController.stream;
  Stream<Map<String, dynamic>> get groupTypingStream =>
      _groupTypingController.stream;
  Stream<Map<String, dynamic>> get statusStream => _statusController.stream;
  Stream<Map<String, dynamic>> get callSignalStream => _callController.stream;
  Stream<bool> get connectionStream => _connectionController.stream;

  bool _isConnected = false;
  bool get isConnected => _isConnected;

  // Set when disconnect() is called on purpose (logout, screen teardown) so
  // the reconnect loop does not fight the caller.
  bool _intentionalDisconnect = false;
  bool _reconnecting = false;

  final Random _random = Random();

  Timer? _pingTimer;
  String? _currentUserId;

  WebSocketService._internal();

  Future<void> connect() async {
    if (_isConnected) return;
    _intentionalDisconnect = false;

    try {
      final token = await _storage.read(key: AppConstants.accessTokenKey);
      if (token == null) {
        throw Exception('No authentication token found');
      }

      // Auth via subprotocol - token is sent in the Sec-WebSocket-Protocol header
      // The server validates this token after connection
      final wsUrl =
          '${AppConstants.baseUrl.replaceFirst('http', 'ws')}${AppConstants.wsPath}';
      _channel = WebSocketChannel.connect(
        Uri.parse(wsUrl),
        protocols: [
          'Bearer',
          token
        ], // Server reads token from subprotocol list
      );

      _channel!.stream.listen(
        _handleMessage,
        onError: _handleError,
        onDone: _handleDone,
      );

      _isConnected = true;
      _connectionController.add(true);
      _startPingTimer();
    } catch (e) {
      _isConnected = false;
      _connectionController.add(false);
      rethrow;
    }
  }

  void _handleMessage(dynamic data) {
    try {
      final message = jsonDecode(data as String) as Map<String, dynamic>;
      final type = message['type'] as String?;

      switch (type) {
        case 'message':
          final messageData = message['data'] as Map<String, dynamic>?;
          if (messageData != null) {
            _messageController.add(Message.fromJson(messageData));
          }
          break;
        case 'group_message':
          final groupData = message['data'] as Map<String, dynamic>?;
          if (groupData != null) {
            _groupMessageController.add(Message.fromJson(groupData));
          }
          break;
        case 'typing':
          _typingController.add(message);
          break;
        case 'group_typing':
          _groupTypingController.add(message);
          break;
        case 'message_sent':
        case 'delivery_receipt':
        case 'read_receipt':
          _statusController.add(message);
          break;
        case 'call_ring':
        case 'call_offer':
        case 'call_answer':
        case 'call_ice':
        case 'call_accept':
        case 'call_decline':
        case 'call_end':
          _callController.add(message);
          break;
        case 'user_status':
          _statusController.add(message);
          break;
        case 'pong':
          break;
        default:
          break;
      }
    } catch (e) {
      // Silently ignore malformed messages rather than crashing
    }
  }

  void _handleError(dynamic error) {
    _isConnected = false;
    _connectionController.add(false);
    _reconnect();
  }

  Future<void> _reconnect() async {
    if (_currentUserId == null || _reconnecting || _intentionalDisconnect) {
      return;
    }
    _reconnecting = true;

    try {
      const maxAttempts = 10;
      const maxDelay = Duration(seconds: 30);
      var attempts = 0;
      var delay = const Duration(seconds: 1);

      while (
          attempts < maxAttempts && !_isConnected && !_intentionalDisconnect) {
        // Jitter ±50% so many clients don't reconnect in lockstep after a
        // server restart.
        final jitterMs =
            (delay.inMilliseconds * (0.5 + _random.nextDouble())).round();
        await Future.delayed(Duration(milliseconds: jitterMs));
        try {
          await connect();
          return;
        } catch (_) {
          attempts++;
          final doubled = delay * 2;
          delay = doubled > maxDelay ? maxDelay : doubled;
        }
      }
      if (!_isConnected && !_intentionalDisconnect) {
        _connectionController.add(false);
      }
    } finally {
      _reconnecting = false;
    }
  }

  void _handleDone() {
    _isConnected = false;
    _connectionController.add(false);
    _pingTimer?.cancel();
    _pingTimer = null;

    // A clean server-side close (restart, idle timeout, network drop) needs
    // the same treatment as an error — otherwise the app stays disconnected
    // until the user takes a manual action.
    if (!_intentionalDisconnect) {
      _reconnect();
    }
  }

  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => sendPing(),
    );
  }

  void sendPing() {
    if (_channel != null && _isConnected) {
      _channel!.sink.add(jsonEncode({'type': 'ping'}));
    }
  }

  void sendMessage({
    required String receiverId,
    required String messageType,
    String content = '',
    String? fileUrl,
    String? fileName,
    int? fileSize,
    String? mediaType,
    String encryption = 'none',
    int? cipherType,
    String? cipherBody,
  }) {
    if (_channel == null || !_isConnected) {
      throw Exception('WebSocket not connected');
    }

    final message = {
      'type': 'message',
      'sender_id': _currentUserId,
      'receiver_id': receiverId,
      'message_type': messageType,
      'content': content,
      if (fileUrl != null) 'file_url': fileUrl,
      if (fileName != null) 'file_name': fileName,
      if (fileSize != null) 'file_size': fileSize,
      if (mediaType != null) 'media_type': mediaType,
      'encryption': encryption,
      if (cipherType != null) 'cipher_type': cipherType,
      if (cipherBody != null) 'cipher_body': cipherBody,
    };

    _channel!.sink.add(jsonEncode(message));
  }

  void sendTyping(String receiverId, bool isTyping) {
    if (_channel == null || !_isConnected) return;

    final message = {
      'type': 'typing',
      'sender_id': _currentUserId,
      'receiver_id': receiverId,
      'is_typing': isTyping,
    };

    _channel!.sink.add(jsonEncode(message));
  }

  void sendGroupMessage({
    required String groupId,
    required String messageType,
    String content = '',
    String? fileUrl,
    String? fileName,
    int? fileSize,
    String? mediaType,
    String encryption = 'none',
    int? cipherType,
    String? cipherBody,
    String? distribution,
  }) {
    if (_channel == null || !_isConnected) return;

    final message = {
      'type': 'group_message',
      'sender_id': _currentUserId,
      'group_id': groupId,
      'message_type': messageType,
      'content': content,
      if (fileUrl != null) 'file_url': fileUrl,
      if (fileName != null) 'file_name': fileName,
      if (fileSize != null) 'file_size': fileSize,
      if (mediaType != null) 'media_type': mediaType,
      'encryption': encryption,
      if (cipherType != null) 'cipher_type': cipherType,
      if (cipherBody != null) 'cipher_body': cipherBody,
      if (distribution != null) 'distribution': distribution,
    };

    _channel!.sink.add(jsonEncode(message));
  }

  void sendGroupTyping(String groupId, bool isTyping) {
    if (_channel == null || !_isConnected) return;

    final message = {
      'type': 'group_typing',
      'sender_id': _currentUserId,
      'group_id': groupId,
      'is_typing': isTyping,
    };

    _channel!.sink.add(jsonEncode(message));
  }

  void _sendCallSignal(
      String type, String receiverId, Map<String, dynamic> extra) {
    if (_channel == null || !_isConnected) return;

    final message = {
      'type': type,
      'sender_id': _currentUserId,
      'receiver_id': receiverId,
      ...extra,
    };
    _channel!.sink.add(jsonEncode(message));
  }

  /// Sends an outbound call ring to [receiverId] before media is negotiated.
  void sendCallRing(String receiverId, {required bool isVideo}) {
    _sendCallSignal('call_ring', receiverId, {'is_video': isVideo});
  }

  /// Relays a local SDP offer/answer to the peer.
  void sendCallSdp(String receiverId, String sessionDescription) {
    _sendCallSignal('call_offer', receiverId, {'sdp': sessionDescription});
  }

  void sendCallAnswer(String receiverId, String sdp) {
    _sendCallSignal('call_answer', receiverId, {'sdp': sdp});
  }

  /// Relays an ICE candidate to the peer.
  void sendCallIce(
      String receiverId, String candidate, String sdpMid, int sdpMLineIndex) {
    _sendCallSignal('call_ice', receiverId, {
      'candidate': candidate,
      'sdp_mid': sdpMid,
      'sdp_mline_index': sdpMLineIndex,
    });
  }

  void sendCallAccept(String receiverId) {
    _sendCallSignal('call_accept', receiverId, {});
  }

  void sendCallDecline(String receiverId) {
    _sendCallSignal('call_decline', receiverId, {});
  }

  void sendCallEnd(String receiverId) {
    _sendCallSignal('call_end', receiverId, {});
  }

  void sendDeliveryReceipt(String senderId, String messageId) {
    if (_channel == null || !_isConnected) return;

    final message = {
      'type': 'delivered',
      'sender_id': senderId,
      'receiver_id': _currentUserId,
      'message_id': messageId,
    };

    _channel!.sink.add(jsonEncode(message));
  }

  void sendReadReceipt(String senderId, String receiverId) {
    if (_channel == null || !_isConnected) return;

    final message = {
      'type': 'read',
      'sender_id': senderId,
      'receiver_id': receiverId,
    };

    _channel!.sink.add(jsonEncode(message));
  }

  void setCurrentUserId(String userId) {
    _currentUserId = userId;
  }

  String? get currentUserId => _currentUserId;

  Future<void> disconnect() async {
    _intentionalDisconnect = true;
    _pingTimer?.cancel();
    await _channel?.sink.close();
    _channel = null;
    _isConnected = false;
    _connectionController.add(false);
  }

  void dispose() {
    disconnect();
    _messageController.close();
    _groupMessageController.close();
    _typingController.close();
    _groupTypingController.close();
    _statusController.close();
    _callController.close();
    _connectionController.close();
  }
}
