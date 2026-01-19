class ApiConfig {
  // Local backend URL for development
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://fieldcheck-app.onrender.com',
  );
}
