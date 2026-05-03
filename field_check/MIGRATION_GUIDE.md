# Migration Guide

## Overview

This document describes the data migration system implemented in the FieldCheck application to ensure clean upgrade paths between versions.

## Migration Service

The `MigrationService` is responsible for handling data migrations when users upgrade to new versions of the app. It automatically runs during app startup and ensures that deprecated settings are removed and data structures are updated as needed.

### Location

- **Service**: `lib/services/migration_service.dart`
- **Tests**: 
  - `test/services/migration_service_test.dart` (unit tests)
  - `test/integration/migration_integration_test.dart` (integration tests)

### How It Works

1. **Automatic Execution**: The migration service runs automatically during app initialization in `main.dart`
2. **Version Tracking**: Migrations are tracked using a version number stored in SharedPreferences
3. **Idempotent**: Each migration only runs once per device
4. **Fail-Safe**: Errors in migrations are logged but don't block app startup

## Current Migrations

### Version 1: Bluetooth Beacon Removal

**Purpose**: Remove deprecated Bluetooth beacon settings from user preferences.

**Settings Removed**:
- `user.useBluetoothBeacons`
- `requireBeaconVerification`

**Validates**: Requirement 2.4 - Clean upgrade path from previous versions

**Impact**: Users upgrading from versions with Bluetooth beacon functionality will have these settings automatically removed, while all other settings are preserved.

## Adding New Migrations

To add a new migration:

1. **Increment the version**:
   ```dart
   static const int _currentMigrationVersion = 2; // Increment this
   ```

2. **Create a migration method**:
   ```dart
   Future<void> _migrateToVersion2(SharedPreferences prefs) async {
     print('Running migration to version 2: Description');
     
     // Your migration logic here
     
     print('Migration to version 2 completed');
   }
   ```

3. **Add version check in runMigrations**:
   ```dart
   if (currentVersion < 2) {
     await _migrateToVersion2(prefs);
   }
   ```

4. **Write tests**:
   - Add unit tests in `test/services/migration_service_test.dart`
   - Add integration tests in `test/integration/migration_integration_test.dart`

## Testing

### Running Migration Tests

```bash
# Run all migration tests
flutter test test/services/migration_service_test.dart test/integration/migration_integration_test.dart

# Run only unit tests
flutter test test/services/migration_service_test.dart

# Run only integration tests
flutter test test/integration/migration_integration_test.dart
```

### Test Coverage

The migration system includes comprehensive tests for:
- ✅ Removing deprecated settings
- ✅ Preserving non-deprecated settings
- ✅ Handling missing settings gracefully
- ✅ Preventing duplicate migrations
- ✅ Setting migration version tracking
- ✅ Error handling without blocking startup
- ✅ Clean upgrade path validation
- ✅ Fresh install scenarios
- ✅ Idempotent behavior

## Best Practices

1. **Never Remove Old Migrations**: Keep all migration methods even after they've been deployed. Users may skip versions.

2. **Test Thoroughly**: Always test migrations with:
   - Fresh installs (no existing data)
   - Upgrades from previous versions (with existing data)
   - Multiple consecutive runs (idempotency)

3. **Preserve User Data**: Only remove settings that are truly deprecated. When in doubt, preserve the data.

4. **Log Actions**: Use print statements to log migration actions for debugging.

5. **Fail Gracefully**: Wrap migration logic in try-catch blocks to prevent blocking app startup.

6. **Document Changes**: Update this guide when adding new migrations.

## Troubleshooting

### Migration Not Running

If a migration doesn't seem to run:
1. Check the `migration_version` value in SharedPreferences
2. Verify the version check in `runMigrations()`
3. Check console logs for migration messages

### Settings Not Being Removed

If deprecated settings persist:
1. Verify the setting key names match exactly
2. Check if the migration version is being incremented
3. Clear app data and test with a fresh install

### App Startup Issues

If migrations cause startup problems:
1. Check console logs for error messages
2. Verify all migrations have proper error handling
3. Test with various data states (empty, partial, full)

## Related Requirements

- **Requirement 2.4**: WHEN upgrading from previous versions, THE Employee_App SHALL migrate settings without Bluetooth beacon references

## Version History

| Version | Description | Date |
|---------|-------------|------|
| 1 | Remove Bluetooth beacon settings | 2024 |

