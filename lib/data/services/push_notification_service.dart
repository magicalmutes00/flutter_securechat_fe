import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../data/services/api_client.dart';
import 'in_app_notification_service.dart';
import 'notification_service.dart';

/// Runs in a separate isolate when a push arrives with the app
/// backgrounded or killed. Must stay top-level with the entry-point pragma
/// so the native side can find it after tree-shaking.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {
    // Firebase not configured in this isolate — nothing to do.
    return;
  }

  // Pushes carrying a `notification` block are displayed by the OS itself;
  // showing another one here would duplicate them. Only data-only pushes
  // need a manually raised notification.
  if (message.notification != null) return;

  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    ),
  );

  final data = message.data;
  try {
    await plugin.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      data['title'] ?? 'New message',
      data['body'] ?? '',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'secure_chat_messages',
          'Messages',
          channelDescription: 'Chat message notifications',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: jsonEncode(data),
    );
  } catch (_) {
    // Background notification display is best-effort.
  }
}

class PushNotificationHandler {
  static final PushNotificationHandler _instance =
      PushNotificationHandler._internal();
  factory PushNotificationHandler() => _instance;
  PushNotificationHandler._internal();

  final ApiClient _api = ApiClient();
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  bool _configuredForFcm = false;
  Future<void>? _pendingInit;

  /// Initializes Firebase (if the host app configured it) and foreground
  /// message routing. Safe to call repeatedly; returns the same future.
  Future<void> init({
    required NotificationService notificationService,
  }) {
    _pendingInit ??= _doInit(notificationService);
    return _pendingInit!;
  }

  Future<void> _doInit(NotificationService notification) async {
    try {
      await Firebase.initializeApp();
      _configuredForFcm = true;
    } catch (e) {
      // No Firebase options (default app not configured) — app keeps working,
      // push simply won't be active.
      _configuredForFcm = false;
      return;
    }

    await _messaging.requestPermission();
    _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final nt = message.notification;
      unawaited(notification.showLocalNotification(
        title: nt?.title ?? 'New message',
        body: nt?.body ?? '',
        data: message.data,
      ));
    });

    // Tapping the OS notification while the app is backgrounded (not
    // killed): route straight into the originating conversation.
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      InAppNotificationService.instance.openConversationFromPushData(
        Map<String, dynamic>.from(message.data),
      );
    });

    // App launched from a killed state via the OS notification tap: the
    // initial message is consumed once here and routed the same way.
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      // Defer past the first frame so the navigator is mounted.
      unawaited(Future.delayed(const Duration(milliseconds: 500), () {
        InAppNotificationService.instance.openConversationFromPushData(
          Map<String, dynamic>.from(initialMessage.data),
        );
      }));
    }

    // Refresh the stored token when FCM rotates it.
    _messaging.onTokenRefresh.listen((token) {
      unawaited(_registerToken(token));
    });

    final token = await _messaging.getToken();
    if (token != null) {
      await _registerToken(token);
    }
  }

  Future<void> _registerToken(String token) async {
    try {
      await _api.registerPushToken(token);
    } catch (_) {
      // Token registration is best-effort; the app must keep working offline.
    }
  }

  /// Called during logout to release the token.
  Future<void> unregister() async {
    if (!_configuredForFcm) return;
    try {
      final token = await _messaging.getToken();
      if (token != null) {
        await _api.unregisterPushToken(token);
      }
    } catch (_) {}
  }
}
