import 'dart:async';
import 'dart:convert';
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
  final _typingController = StreamController<Map<String, dynamic>>.broadcast();
  final _statusController = StreamController<Map<String, dynamic>>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();

  Stream<Message> get messageStream => _messageController.stream;
  Stream<Map<String, dynamic>> get typingStream => _typingController.stream;
  Stream<Map<String, dynamic>> get statusStream => _statusController.stream;
  Stream<bool> get connectionStream => _connectionController.stream;

  bool _isConnected = false;
  bool get isConnected => _isConnected;

  Timer? _pingTimer;
  String? _currentUserId;

  WebSocketService._internal();

    Future<void> connect() async {
    if (_isConnected) return;

    try {
      final token = await _storage.read(key: AppConstants.accessTokenKey);
      if (token == null) {
        throw Exception('No authentication token found');
      }

      // Auth via subprotocol - token is sent in the Sec-WebSocket-Protocol header
      // The server validates this token after connection
      final wsUrl = '${AppConstants.baseUrl.replaceFirst('http', 'ws')}${AppConstants.wsPath}';
      _channel = WebSocketChannel.connect(
        Uri.parse(wsUrl),
        protocols: ['Bearer', token], // Server reads token from subprotocol list
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
        case 'typing':
          _typingController.add(message);
          break;
        case 'message_sent':
        case 'delivery_receipt':
        case 'read_receipt':
          _statusController.add(message);
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
    if (_currentUserId == null) return;

    const maxAttempts = 5;
    var attempts = 0;
    var delay = const Duration(seconds: 1);

    while (attempts < maxAttempts && !_isConnected) {
      await Future.delayed(delay);
      try {
        await connect();
        break;
      } catch (_) {
        attempts++;
        delay = Duration(seconds: delay.inSeconds * 2);
        if (attempts >= maxAttempts) {
          _connectionController.add(false);
        }
      }
    }
  }

  void _handleDone() {
    _isConnected = false;
    _connectionController.add(false);
    _pingTimer?.cancel();
    _pingTimer = null;
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
    _pingTimer?.cancel();
    await _channel?.sink.close();
    _channel = null;
    _isConnected = false;
    _connectionController.add(false);
  }

  void dispose() {
    disconnect();
    _messageController.close();
    _typingController.close();
    _statusController.close();
    _connectionController.close();
  }
}
