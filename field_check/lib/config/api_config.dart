import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

class ApiConfig {
  // If provided via --dart-define, prefer that value
  static const String _envBaseUrl = String.fromEnvironment('API_BASE_URL');
  static const String _defaultAndroidUrl = String.fromEnvironment('ANDROID_API_URL', defaultValue: 'http://192.168.1.100:3002');

  // Platform-aware base URL with sensible defaults for local development
  static String get baseUrl {
    if (_envBaseUrl.isNotEmpty) return _envBaseUrl;

    // Flutter Web can typically reach localhost directly
    if (kIsWeb) return 'http://localhost:3002';

    // On emulators/devices, localhost resolves differently
    try {
      if (Platform.isAndroid) {
        // Use environment-provided URL or default
        return _defaultAndroidUrl;
      }
      if (Platform.isIOS || Platform.isMacOS) {
        return 'http://localhost:3002';
      }
      if (Platform.isWindows || Platform.isLinux) {
        return 'http://localhost:3002';
      }
    } catch (_) {
      // Platform not available (e.g., in some test contexts)
    }

    // Fallback
    return 'http://localhost:3002';
  }
}