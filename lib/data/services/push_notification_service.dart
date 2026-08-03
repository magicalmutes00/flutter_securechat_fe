import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../../data/services/api_client.dart';
import 'notification_service.dart';

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
