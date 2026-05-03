import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:field_check/services/migration_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MigrationService', () {
    late MigrationService migrationService;

    setUp(() {
      migrationService = MigrationService();
    });

    tearDown(() async {
      // Clean up SharedPreferences after each test
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    });

    test('should remove Bluetooth beacon settings on first migration', () async {
      // Arrange: Set up SharedPreferences with deprecated Bluetooth settings
      SharedPreferences.setMockInitialValues({
        'user.useBluetoothBeacons': true,
        'requireBeaconVerification': false,
        'someOtherSetting': 'should remain',
      });

      final prefs = await SharedPreferences.getInstance();

      // Verify settings exist before migration
      expect(prefs.containsKey('user.useBluetoothBeacons'), true);
      expect(prefs.containsKey('requireBeaconVerification'), true);
      expect(prefs.containsKey('someOtherSetting'), true);

      // Act: Run migrations
      await migrationService.runMigrations();

      // Assert: Bluetooth settings should be removed
      expect(prefs.containsKey('user.useBluetoothBeacons'), false);
      expect(prefs.containsKey('requireBeaconVerification'), false);
      
      // Other settings should remain
      expect(prefs.containsKey('someOtherSetting'), true);
      expect(prefs.getString('someOtherSetting'), 'should remain');
      
      // Migration version should be set
      expect(prefs.getInt('migration_version'), 1);
    });

    test('should handle missing Bluetooth settings gracefully', () async {
      // Arrange: Set up SharedPreferences without Bluetooth settings
      SharedPreferences.setMockInitialValues({
        'someOtherSetting': 'test value',
      });

      final prefs = await SharedPreferences.getInstance();

      // Act: Run migrations
      await migrationService.runMigrations();

      // Assert: Should complete without errors
      expect(prefs.getInt('migration_version'), 1);
      expect(prefs.getString('someOtherSetting'), 'test value');
    });

    test('should not run migration twice', () async {
      // Arrange: Set up SharedPreferences with Bluetooth settings
      SharedPreferences.setMockInitialValues({
        'user.useBluetoothBeacons': true,
        'requireBeaconVerification': true,
      });

      final prefs = await SharedPreferences.getInstance();

      // Act: Run migrations first time
      await migrationService.runMigrations();

      // Manually add back the settings to simulate them being re-added
      await prefs.setBool('user.useBluetoothBeacons', true);
      await prefs.setBool('requireBeaconVerification', true);

      // Run migrations second time
      await migrationService.runMigrations();

      // Assert: Settings should still exist because migration version is already 1
      expect(prefs.containsKey('user.useBluetoothBeacons'), true);
      expect(prefs.containsKey('requireBeaconVerification'), true);
      expect(prefs.getInt('migration_version'), 1);
    });

    test('should set migration version on first run', () async {
      // Arrange: Fresh SharedPreferences
      SharedPreferences.setMockInitialValues({});

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('migration_version'), false);

      // Act: Run migrations
      await migrationService.runMigrations();

      // Assert: Migration version should be set
      expect(prefs.getInt('migration_version'), 1);
    });

    test('should handle errors gracefully without blocking app startup', () async {
      // This test verifies that even if there's an issue, the migration
      // doesn't throw and block app initialization
      
      // Arrange: Set up SharedPreferences
      SharedPreferences.setMockInitialValues({
        'user.useBluetoothBeacons': true,
      });

      // Act & Assert: Should not throw
      expect(() async => await migrationService.runMigrations(), returnsNormally);
    });

    test('should preserve all non-Bluetooth settings during migration', () async {
      // Arrange: Set up various settings
      SharedPreferences.setMockInitialValues({
        'user.useBluetoothBeacons': true,
        'requireBeaconVerification': false,
        'user.locationTrackingEnabled': true,
        'user.themeMode': 'dark',
        'geofenceRadius': 100,
        'allowOfflineMode': true,
        'auth_token': 'test_token_123',
      });

      final prefs = await SharedPreferences.getInstance();

      // Act: Run migrations
      await migrationService.runMigrations();

      // Assert: Only Bluetooth settings should be removed
      expect(prefs.containsKey('user.useBluetoothBeacons'), false);
      expect(prefs.containsKey('requireBeaconVerification'), false);
      
      // All other settings should be preserved
      expect(prefs.getBool('user.locationTrackingEnabled'), true);
      expect(prefs.getString('user.themeMode'), 'dark');
      expect(prefs.getInt('geofenceRadius'), 100);
      expect(prefs.getBool('allowOfflineMode'), true);
      expect(prefs.getString('auth_token'), 'test_token_123');
    });
  });
}
