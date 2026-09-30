/// Environment-based configuration for the SecureChat client.
///
/// Values are provided at build/run time via `--dart-define`:
///
///   flutter run --dart-define=API_BASE_URL=https://api.example.com \
///               --dart-define=WS_PATH=/ws
///
/// The default points at the production deployment on Render; for local
/// backend development pass your own URL, e.g.
/// `--dart-define=API_BASE_URL=http://10.0.2.2:8080` (Android emulator →
/// host machine).
class EnvironmentConfig {
  EnvironmentConfig._();

  static const String _defaultBaseUrl =
      'https://flutter-securechat-bk.onrender.com';
  static const String _defaultWsPath = '/ws';

  /// Base URL of the SecureChat backend (REST + WS host).
  ///
  /// Example: `https://api.securechat.example.com`.
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: _defaultBaseUrl,
  );

  /// WebSocket path on the backend used for realtime messaging.
  static const String wsPath = String.fromEnvironment(
    'WS_PATH',
    defaultValue: _defaultWsPath,
  );

  /// Full WebSocket URL derived from [baseUrl] and [wsPath].
  static String get wsUrl => '${baseUrl.replaceFirst('http', 'ws')}$wsPath';
}
