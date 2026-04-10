import 'package:flutter/foundation.dart';

class ApiConfig {
  static String get baseUrl {
    const env = String.fromEnvironment('API_BASE_URL', defaultValue: '');
    if (env.trim().isNotEmpty) return env.trim();

    const useLocal = bool.fromEnvironment(
      'USE_LOCAL_BACKEND',
      defaultValue: false,
    );

    if (useLocal) return 'http://localhost:3002';

    if (kReleaseMode) return 'https://fieldcheck-app-mwk3.onrender.com';
    if (kIsWeb) return 'https://fieldcheck-app-mwk3.onrender.com';
    return 'https://fieldcheck-app-mwk3.onrender.com';
  }

  static String get chatBaseUrl {
    const env = String.fromEnvironment('CHAT_API_BASE_URL', defaultValue: '');
    if (env.trim().isNotEmpty) return env.trim();

    // Use the same host as baseUrl so chat calls don't fall through to a stale
    // Render endpoint and trigger unnecessary 404-then-retry failover.
    return baseUrl;
  }

  static String get uploadsBaseUrl {
    const env = String.fromEnvironment('UPLOADS_BASE_URL', defaultValue: '');
    if (env.trim().isNotEmpty) return env.trim();
    return baseUrl;
  }
}
