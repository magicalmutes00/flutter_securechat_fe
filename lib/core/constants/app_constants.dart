import '../../core/environment/environment_config.dart';

class AppConstants {
  AppConstants._();

  // API Configuration - Now uses environment-based configuration
  static String get baseUrl => EnvironmentConfig.baseUrl;
  static const String apiPath = '/api';
  static String get wsPath => EnvironmentConfig.wsPath;

  // OneSignal Configuration
  // Replace with your OneSignal App ID from https://onesignal.com
  // Consider moving to environment config for different values per environment
  static const String oneSignalAppId = 'a2fab7dd-c0b6-419c-840b-4c995cf891b4';

  // Message Types
  static const String messageTypeText = 'text';
  static const String messageTypeImage = 'image';
  static const String messageTypeVideo = 'video';
  static const String messageTypeAudio = 'audio';
  static const String messageTypeDocument = 'document';

  // Message Status
  static const String messageStatusSent = 'sent';
  static const String messageStatusDelivered = 'delivered';
  static const String messageStatusRead = 'read';

  // Storage Keys
  static const String accessTokenKey = 'access_token';
  static const String refreshTokenKey = 'refresh_token';
  static const String userKey = 'user_data';

  // File Upload
  static const int maxFileSizeMB = 50;
  static const int maxImageSizeMB = 10;
  static const int maxVideoSizeMB = 50;
  static const int maxAudioSizeMB = 10;
  static const int maxDocumentSizeMB = 25;

  // Pagination
  static const int messagesPageSize = 50;

  // Animation
  static const int messageAnimationDuration = 300;

  // Regex Patterns
  static final RegExp phoneRegex = RegExp(r'^[+]?[(]?[0-9]{1,4}[)]?[-\s./0-9]*$');
  static final RegExp emailRegex = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
}

