class ApiConfig {
  // Local backend URL for development
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:3002',
  );
}
