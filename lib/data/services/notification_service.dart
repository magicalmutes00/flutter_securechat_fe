import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  final _notificationController =
      StreamController<NotificationPayload>.broadcast();

  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    await _requestPermissions();
    _isInitialized = true;
  }

  Future<void> _requestPermissions() async {
    if (Platform.isAndroid) {
      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } else if (Platform.isIOS) {
      await _localNotifications
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );
    }
  }

  void _onNotificationTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload != null) {
      try {
        final decoded = jsonDecode(payload) as Map<String, dynamic>;
        _notificationController.add(NotificationPayload(
          title: '',
          body: '',
          senderId: decoded['sender_id']?.toString(),
          data: decoded,
        ));
      } catch (_) {}
    }
  }

  /// Opens the stream of notification TAP events. Displaying a notification
  /// does not emit here — only the user tapping one does.
  Stream<NotificationPayload> get notificationStream =>
      _notificationController.stream;

  Future<void> showLocalNotification({
    required String title,
    required String body,
    String? senderId,
    Map<String, dynamic>? data,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      'secure_chat_messages',
      'Messages',
      channelDescription: 'Chat message notifications',
      importance: Importance.high,
      priority: Priority.high,
      ticker: 'New message',
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    final payloadData =
        data ?? (senderId != null ? {'sender_id': senderId} : null);

    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title,
      body,
      details,
      // Must be valid JSON: the tap handler jsonDecodes it to route the user
      // to the originating conversation.
      payload: payloadData != null ? jsonEncode(payloadData) : null,
    );
  }

  Future<void> dispose() async {
    await _notificationController.close();
  }
}

class NotificationPayload {
  final String title;
  final String body;
  final String? senderId;
  final Map<String, dynamic>? data;

  NotificationPayload({
    required this.title,
    required this.body,
    this.senderId,
    this.data,
  });
}
