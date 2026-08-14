/// Environment-based configuration for the SecureChat client.
///
/// Values are provided at build/run time via `--dart-define`:
///
///   flutter run --dart-define=API_BASE_URL=https://api.example.com \
///               --dart-define=WS_PATH=/ws
///
/// A sensible default is used when the variable is not provided so the app
/// can still run against a local backend during development.
class EnvironmentConfig {
  EnvironmentConfig._();

  static const String _defaultBaseUrl = 'http://100.110.146.20:8081';
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
