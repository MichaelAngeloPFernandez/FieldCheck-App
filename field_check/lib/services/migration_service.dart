// ignore_for_file: avoid_print

import 'package:shared_preferences/shared_preferences.dart';

/// Service responsible for handling app data migrations between versions.
///
/// This service manages the migration of user data and settings when the app
/// is upgraded to a new version. It ensures a clean upgrade path by removing
/// deprecated settings and transforming data structures as needed.
///
/// ## Usage
///
/// The migration service should be called during app initialization in main.dart:
///
/// ```dart
/// void main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   
///   final migrationService = MigrationService();
///   await migrationService.runMigrations();
///   
///   // Continue with app initialization...
/// }
/// ```
///
/// ## Migration Versioning
///
/// Migrations are versioned sequentially. Each migration is only run once per
/// device, tracked by the 'migration_version' key in SharedPreferences.
///
/// ## Adding New Migrations
///
/// To add a new migration:
/// 1. Increment [_currentMigrationVersion]
/// 2. Add a new migration method (e.g., `_migrateToVersion2`)
/// 3. Call the new migration in [runMigrations] with appropriate version check
///
/// ## Error Handling
///
/// Migrations are designed to fail gracefully. If a migration encounters an
/// error, it will be logged but will not block app startup. This ensures that
/// users can still access the app even if a migration fails.
class MigrationService {
  static const String _migrationVersionKey = 'migration_version';
  static const int _currentMigrationVersion = 1;

  /// Run all pending migrations
  /// This should be called during app initialization
  Future<void> runMigrations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentVersion = prefs.getInt(_migrationVersionKey) ?? 0;

      // Run migrations sequentially based on version
      if (currentVersion < 1) {
        await _migrateToVersion1(prefs);
      }

      // Update migration version
      await prefs.setInt(_migrationVersionKey, _currentMigrationVersion);
      print('Migrations completed successfully. Current version: $_currentMigrationVersion');
    } catch (e) {
      print('Error running migrations: $e');
      // Don't rethrow - migrations should not block app startup
    }
  }

  /// Migration to version 1: Remove Bluetooth beacon settings
  /// 
  /// This migration removes deprecated Bluetooth beacon settings that are
  /// no longer used in the application. This ensures a clean upgrade path
  /// for users updating from previous versions.
  Future<void> _migrateToVersion1(SharedPreferences prefs) async {
    print('Running migration to version 1: Removing Bluetooth beacon settings');

    final keysToRemove = [
      'user.useBluetoothBeacons',
      'requireBeaconVerification',
    ];

    for (final key in keysToRemove) {
      if (prefs.containsKey(key)) {
        await prefs.remove(key);
        print('Removed deprecated setting: $key');
      }
    }

    print('Migration to version 1 completed');
  }
}
