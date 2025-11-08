class ApiConfig {
  // Configure via --dart-define=API_BASE_URL or fallback to localhost:3002
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:3002',
  );
}