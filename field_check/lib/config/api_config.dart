class ApiConfig {
  // Configure via --dart-define=API_BASE_URL or fallback to localhost:3002
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:3002',
  );
}