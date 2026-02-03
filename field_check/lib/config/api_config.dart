import 'package:flutter/foundation.dart';

class ApiConfig {
  static String get baseUrl {
    const env = String.fromEnvironment('API_BASE_URL', defaultValue: '');
    if (env.trim().isNotEmpty) return env.trim();

    const useLocal = bool.fromEnvironment(
      'USE_LOCAL_BACKEND',
      defaultValue: false,
    );

    if (kReleaseMode) return 'https://fieldcheck-app.onrender.com';
    if (useLocal) return 'http://localhost:3000';
    return 'https://fieldcheck-app.onrender.com';
  }

  static String get uploadsBaseUrl {
    const env = String.fromEnvironment('UPLOADS_BASE_URL', defaultValue: '');
    if (env.trim().isNotEmpty) return env.trim();
    return baseUrl;
  }
}
