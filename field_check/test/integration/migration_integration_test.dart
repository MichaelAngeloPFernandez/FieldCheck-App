import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:field_check/services/migration_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Migration Integration Tests', () {
    tearDown(() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    });

    test('should provide clean upgrade path from previous versions', () async {
      // Simulate a user upgrading from a version with Bluetooth settings
      SharedPreferences.setMockInitialValues({
        'user.useBluetoothBeacons': true,
        'requireBeaconVerification': true,
        'user.locationTrackingEnabled': true,
        'auth_token': 'existing_user_token',
        'user.themeMode': 'light',
      });

      final prefs = await SharedPreferences.getInstance();

      // Verify pre-migration state (old version)
      expect(prefs.getBool('user.useBluetoothBeacons'), true);
      expect(prefs.getBool('requireBeaconVerification'), true);
      expect(prefs.getBool('user.locationTrackingEnabled'), true);
      expect(prefs.getString('auth_token'), 'existing_user_token');

      // Simulate app startup with migration
      final migrationService = MigrationService();
      await migrationService.runMigrations();

      // Verify post-migration state (new version)
      // Bluetooth settings should be removed
      expect(prefs.containsKey('user.useBluetoothBeacons'), false);
      expect(prefs.containsKey('requireBeaconVerification'), false);

      // Other user settings should be preserved
      expect(prefs.getBool('user.locationTrackingEnabled'), true);
      expect(prefs.getString('auth_token'), 'existing_user_token');
      expect(prefs.getString('user.themeMode'), 'light');

      // Migration tracking should be in place
      expect(prefs.getInt('migration_version'), 1);
    });

    test('should handle fresh install without errors', () async {
      // Simulate a fresh install with no existing settings
      SharedPreferences.setMockInitialValues({});

      final prefs = await SharedPreferences.getInstance();

      // Run migration on fresh install
      final migrationService = MigrationService();
      await migrationService.runMigrations();

      // Should complete successfully and set migration version
      expect(prefs.getInt('migration_version'), 1);
      
      // No Bluetooth settings should exist
      expect(prefs.containsKey('user.useBluetoothBeacons'), false);
      expect(prefs.containsKey('requireBeaconVerification'), false);
    });

    test('should be idempotent - multiple runs should be safe', () async {
      // Set up initial state
      SharedPreferences.setMockInitialValues({
        'user.useBluetoothBeacons': true,
        'requireBeaconVerification': false,
        'user.locationTrackingEnabled': true,
      });

      final prefs = await SharedPreferences.getInstance();
      final migrationService = MigrationService();

      // Run migration multiple times
      await migrationService.runMigrations();
      await migrationService.runMigrations();
      await migrationService.runMigrations();

      // Should still be in correct state
      expect(prefs.containsKey('user.useBluetoothBeacons'), false);
      expect(prefs.containsKey('requireBeaconVerification'), false);
      expect(prefs.getBool('user.locationTrackingEnabled'), true);
      expect(prefs.getInt('migration_version'), 1);
    });

    test('should validate Requirement 2.4 - clean upgrade path', () async {
      // This test validates Requirement 2.4:
      // "WHEN upgrading from previous versions, THE Employee_App SHALL 
      // migrate settings without Bluetooth beacon references"

      // Arrange: Simulate user with old version settings
      SharedPreferences.setMockInitialValues({
        'user.useBluetoothBeacons': true,
        'requireBeaconVerification': true,
        'user.name': 'Test User',
        'user.email': 'test@example.com',
        'geofenceRadius': 150,
      });

      final prefs = await SharedPreferences.getInstance();

      // Act: Perform migration (simulating app upgrade)
      final migrationService = MigrationService();
      await migrationService.runMigrations();

      // Assert: Bluetooth settings removed, other settings preserved
      expect(
        prefs.containsKey('user.useBluetoothBeacons'),
        false,
        reason: 'Bluetooth beacon setting should be removed during migration',
      );
      expect(
        prefs.containsKey('requireBeaconVerification'),
        false,
        reason: 'Beacon verification setting should be removed during migration',
      );

      // Verify user data is preserved
      expect(prefs.getString('user.name'), 'Test User');
      expect(prefs.getString('user.email'), 'test@example.com');
      expect(prefs.getInt('geofenceRadius'), 150);

      // Verify migration tracking
      expect(
        prefs.getInt('migration_version'),
        1,
        reason: 'Migration version should be tracked',
      );
    });
  });
}
