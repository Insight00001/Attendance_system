class AppConfig {
  // Change to your server IP/domain for production
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:5000/api/v1', // Android emulator → localhost
  );

  static const String wsUrl = String.fromEnvironment(
    'WS_URL',
    defaultValue: 'http://127.0.0.1:5000/api/v1', // Android emulator → localhost
  );

  // Storage keys
  static const String accessTokenKey  = 'access_token';
  static const String refreshTokenKey = 'refresh_token';
  static const String userKey         = 'user_data';
  static const String themeKey        = 'theme_mode';

  // Timeouts
  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 30);

  // Pagination
  static const int defaultPageSize = 20;

  // Face recognition
  static const Duration cameraPreviewDelay = Duration(milliseconds: 500);
  static const int livenessFrameCount = 15; // frames to collect for blink detection

  // Shift defaults
  static const String defaultShiftStart = '08:00';
  static const String defaultShiftEnd   = '17:00';
}
