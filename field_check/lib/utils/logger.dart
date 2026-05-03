import 'package:flutter/foundation.dart';

/// Centralized logging utility for debugging and monitoring
/// Tags help identify which part of the app is logging
class AppLogger {
  // Prevent instantiation
  AppLogger._();

  // ============================================================================
  // LOG LEVELS
  // ============================================================================
  
  /// Debug level - detailed information for debugging
  static void debug(String tag, String message, [dynamic error, StackTrace? stackTrace]) {
    if (kDebugMode) {
      print('🔵 [DEBUG] [$tag] $message');
      if (error != null) print('   Error: $error');
      if (stackTrace != null) print('   Stack: $stackTrace');
    }
  }

  /// Info level - general information about app flow
  static void info(String tag, String message) {
    if (kDebugMode) {
      print('ℹ️  [INFO] [$tag] $message');
    }
  }

  /// Warning level - something unexpected but not critical
  static void warning(String tag, String message, [dynamic error]) {
    if (kDebugMode) {
      print('⚠️  [WARNING] [$tag] $message');
      if (error != null) print('   Error: $error');
    }
  }

  /// Error level - something went wrong
  static void error(String tag, String message, [dynamic error, StackTrace? stackTrace]) {
    if (kDebugMode) {
      print('❌ [ERROR] [$tag] $message');
      if (error != null) print('   Error: $error');
      if (stackTrace != null) print('   Stack: $stackTrace');
    }
  }

  /// Success level - operation completed successfully
  static void success(String tag, String message) {
    if (kDebugMode) {
      print('✅ [SUCCESS] [$tag] $message');
    }
  }

  // ============================================================================
  // COMMON TAGS - Use these for consistency
  // ============================================================================
  static const String tagAuth = 'AUTH';
  static const String tagLocation = 'LOCATION';
  static const String tagGeofence = 'GEOFENCE';
  static const String tagAttendance = 'ATTENDANCE';
  static const String tagTask = 'TASK';
  static const String tagMap = 'MAP';
  static const String tagAPI = 'API';
  static const String tagDatabase = 'DATABASE';
  static const String tagUI = 'UI';
  static const String tagNavigation = 'NAVIGATION';
  static const String tagSocket = 'SOCKET';
  static const String tagSync = 'SYNC';
  static const String tagCache = 'CACHE';
  static const String tagAdmin = 'ADMIN';
  static const String tagReport = 'REPORT';
}
