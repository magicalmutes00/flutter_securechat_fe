import 'dart:async';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final _notificationController = StreamController<NotificationPayload>.broadcast();
  Stream<NotificationPayload> get notificationStream => _notificationController.stream;

  void showNotification({
    required String title,
    required String body,
    String? senderId,
  }) {
    if (!_notificationController.isClosed) {
      _notificationController.add(NotificationPayload(
        title: title,
        body: body,
        senderId: senderId,
      ));
    }
  }

  void dispose() {
    _notificationController.close();
  }
}

class NotificationPayload {
  final String title;
  final String body;
  final String? senderId;

  NotificationPayload({
    required this.title,
    required this.body,
    this.senderId,
  });
}