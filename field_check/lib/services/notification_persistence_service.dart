import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:field_check/services/task_service.dart';

/// Service for managing notification state persistence across app sessions
/// Provides unified notification state management for both admin and employee sides
class NotificationPersistenceService {
  static const String _adminReadIdsKey = 'admin_read_notification_ids';
  static const String _adminCachedNotificationsKey = 'admin_cached_notifications';
  static const String _adminUnreadCountKey = 'admin_unread_notifications_count';
  static const String _adminLastSyncKey = 'admin_notifications_last_sync';
  static const String _adminBackendSyncKey = 'admin_notifications_last_backend_sync';
  
  static const String _employeeReadIdsKey = 'employee_read_notification_ids';
  static const String _employeeUnreadCountKey = 'employee_unread_notifications_count';
  static const String _employeeLastSyncKey = 'employee_notifications_last_sync';
  static const String _employeeBackendSyncKey = 'employee_notifications_last_backend_sync';
  static const String _employeeReadStatesSyncKey = 'employee_notifications_read_states_sync';

  final TaskService _taskService = TaskService();

  /// Persist notification read states with enhanced data caching
  Future<void> persistNotificationReadStates({
    required List<String> readIds,
    required bool isAdmin,
    List<Map<String, dynamic>>? notificationData,
    int retryCount = 0,
  }) async {
    const maxRetries = 3;
    const retryDelay = Duration(seconds: 1);
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final readIdsKey = isAdmin ? _adminReadIdsKey : _employeeReadIdsKey;
      final lastSyncKey = isAdmin ? _adminLastSyncKey : _employeeLastSyncKey;
      
      // Store read notification IDs
      await prefs.setStringList(readIdsKey, readIds);
      
      // Store timestamp of last persistence for synchronization
      await prefs.setInt(lastSyncKey, DateTime.now().millisecondsSinceEpoch);
      
      // For admin, also cache notification data for offline access
      if (isAdmin && notificationData != null) {
        final notificationJson = notificationData.map((data) => 
          '${data['id']}|${data['title']}|${data['message']}|${data['type']}|${data['timestamp']}|${data['isRead']}|${data['payload']?.toString() ?? ''}'
        ).toList();
        
        await prefs.setStringList(_adminCachedNotificationsKey, notificationJson);
      }
      
      debugPrint('${isAdmin ? 'Admin' : 'Employee'} notification states persisted: ${readIds.length} read IDs');
    } catch (e) {
      debugPrint('Error persisting ${isAdmin ? 'admin' : 'employee'} notification read states: $e');
      
      // Retry persistence if it fails
      if (retryCount < maxRetries) {
        debugPrint('Retrying notification read states persistence (attempt ${retryCount + 1}/$maxRetries)');
        await Future.delayed(retryDelay);
        return persistNotificationReadStates(
          readIds: readIds,
          isAdmin: isAdmin,
          notificationData: notificationData,
          retryCount: retryCount + 1,
        );
      } else {
        debugPrint('Failed to persist notification read states after $maxRetries attempts');
      }
    }
  }

  /// Load cached notification read states
  Future<List<String>> loadCachedReadStates({required bool isAdmin}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final readIdsKey = isAdmin ? _adminReadIdsKey : _employeeReadIdsKey;
      return prefs.getStringList(readIdsKey) ?? [];
    } catch (e) {
      debugPrint('Error loading cached ${isAdmin ? 'admin' : 'employee'} read states: $e');
      return [];
    }
  }

  /// Load cached notification data (admin only)
  Future<List<Map<String, dynamic>>> loadCachedNotificationData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedNotifications = prefs.getStringList(_adminCachedNotificationsKey) ?? [];
      
      final notifications = <Map<String, dynamic>>[];
      for (final cachedData in cachedNotifications) {
        try {
          final parts = cachedData.split('|');
          if (parts.length >= 6) {
            notifications.add({
              'id': parts[0],
              'title': parts[1],
              'message': parts[2],
              'type': parts[3],
              'timestamp': parts[4],
              'isRead': parts[5] == 'true',
              'payload': parts.length > 6 && parts[6].isNotEmpty 
                ? {'cached': true, 'data': parts[6]} 
                : null,
            });
          }
        } catch (e) {
          debugPrint('Error parsing cached notification: $e');
        }
      }
      
      return notifications;
    } catch (e) {
      debugPrint('Error loading cached notification data: $e');
      return [];
    }
  }

  /// Persist notification count with enhanced tracking
  Future<void> persistNotificationCount({
    required int count,
    required bool isAdmin,
    int retryCount = 0,
  }) async {
    const maxRetries = 3;
    const retryDelay = Duration(seconds: 1);
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final countKey = isAdmin ? _adminUnreadCountKey : _employeeUnreadCountKey;
      final syncKey = isAdmin ? _adminLastSyncKey : _employeeLastSyncKey;
      
      await prefs.setInt(countKey, count);
      await prefs.setInt(syncKey, DateTime.now().millisecondsSinceEpoch);
      
      debugPrint('${isAdmin ? 'Admin' : 'Employee'} notification count persisted: $count');
    } catch (e) {
      debugPrint('Error persisting ${isAdmin ? 'admin' : 'employee'} notification count: $e');
      
      // Retry persistence if it fails
      if (retryCount < maxRetries) {
        debugPrint('Retrying notification count persistence (attempt ${retryCount + 1}/$maxRetries)');
        await Future.delayed(retryDelay);
        return persistNotificationCount(
          count: count,
          isAdmin: isAdmin,
          retryCount: retryCount + 1,
        );
      } else {
        debugPrint('Failed to persist notification count after $maxRetries attempts');
      }
    }
  }

  /// Load cached notification count
  Future<int> loadCachedNotificationCount({required bool isAdmin}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final countKey = isAdmin ? _adminUnreadCountKey : _employeeUnreadCountKey;
      return prefs.getInt(countKey) ?? 0;
    } catch (e) {
      debugPrint('Error loading cached ${isAdmin ? 'admin' : 'employee'} notification count: $e');
      return 0;
    }
  }

  /// Synchronize local notification states with backend
  Future<int> synchronizeWithBackend({
    required bool isAdmin,
    int? currentLocalCount,
    int retryCount = 0,
  }) async {
    const maxRetries = 3;
    const retryDelay = Duration(seconds: 2);
    
    try {
      // Get the current unread count from backend
      final backendUnreadCount = await _taskService.fetchTotalUnreadCount();
      
      // Compare with local state and update if different
      if (currentLocalCount != null && backendUnreadCount != currentLocalCount) {
        debugPrint('${isAdmin ? 'Admin' : 'Employee'} backend count ($backendUnreadCount) differs from local count ($currentLocalCount)');
        
        // Update cached count to match backend
        await persistNotificationCount(
          count: backendUnreadCount,
          isAdmin: isAdmin,
        );
        
        // Store backend sync timestamp
        final prefs = await SharedPreferences.getInstance();
        final backendSyncKey = isAdmin ? _adminBackendSyncKey : _employeeBackendSyncKey;
        await prefs.setInt(backendSyncKey, DateTime.now().millisecondsSinceEpoch);
      }
      
      return backendUnreadCount;
    } catch (e) {
      debugPrint('Error synchronizing ${isAdmin ? 'admin' : 'employee'} notification states with backend: $e');
      
      // Retry synchronization if it fails
      if (retryCount < maxRetries) {
        debugPrint('Retrying backend synchronization (attempt ${retryCount + 1}/$maxRetries)');
        await Future.delayed(retryDelay);
        return synchronizeWithBackend(
          isAdmin: isAdmin,
          currentLocalCount: currentLocalCount,
          retryCount: retryCount + 1,
        );
      } else {
        debugPrint('Failed to synchronize with backend after $maxRetries attempts');
        // Return current local count as fallback
        return currentLocalCount ?? 0;
      }
    }
  }

  /// Validate local read states against backend for consistency
  Future<List<String>> validateReadStatesWithBackend({required bool isAdmin}) async {
    try {
      // Get recent notifications from backend to validate read states
      final backendNotifications = await _taskService.listAppNotifications(
        unreadOnly: false,
        limit: 20,
        page: 1,
      );
      
      if (backendNotifications.isEmpty) {
        return await loadCachedReadStates(isAdmin: isAdmin);
      }
      
      final cachedReadIds = await loadCachedReadStates(isAdmin: isAdmin);
      final updatedReadIds = List<String>.from(cachedReadIds);
      bool hasChanges = false;
      
      for (final backendNotif in backendNotifications) {
        final id = (backendNotif['id'] ?? backendNotif['_id'] ?? '').toString();
        final isReadOnBackend = backendNotif['isRead'] == true;
        
        if (id.isNotEmpty) {
          if (isReadOnBackend && !updatedReadIds.contains(id)) {
            updatedReadIds.add(id);
            hasChanges = true;
          } else if (!isReadOnBackend && updatedReadIds.contains(id)) {
            updatedReadIds.remove(id);
            hasChanges = true;
          }
        }
      }
      
      // Update cached read states if there were changes
      if (hasChanges) {
        await persistNotificationReadStates(
          readIds: updatedReadIds,
          isAdmin: isAdmin,
        );
        debugPrint('Validated and updated ${updatedReadIds.length} ${isAdmin ? 'admin' : 'employee'} read states with backend');
      }
      
      return updatedReadIds;
    } catch (e) {
      debugPrint('Error validating ${isAdmin ? 'admin' : 'employee'} read states with backend: $e');
      // Return cached states as fallback
      return await loadCachedReadStates(isAdmin: isAdmin);
    }
  }

  /// Get last synchronization timestamp
  Future<DateTime?> getLastSyncTimestamp({required bool isAdmin}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final syncKey = isAdmin ? _adminLastSyncKey : _employeeLastSyncKey;
      final timestamp = prefs.getInt(syncKey);
      return timestamp != null ? DateTime.fromMillisecondsSinceEpoch(timestamp) : null;
    } catch (e) {
      debugPrint('Error getting last sync timestamp: $e');
      return null;
    }
  }

  /// Check if cached data is recent (within specified hours)
  Future<bool> isCacheRecent({required bool isAdmin, int maxHours = 24}) async {
    final lastSync = await getLastSyncTimestamp(isAdmin: isAdmin);
    if (lastSync == null) return false;
    
    return DateTime.now().difference(lastSync).inHours < maxHours;
  }

  /// Clear all cached notification data
  Future<void> clearCache({required bool isAdmin}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      if (isAdmin) {
        await prefs.remove(_adminReadIdsKey);
        await prefs.remove(_adminCachedNotificationsKey);
        await prefs.remove(_adminUnreadCountKey);
        await prefs.remove(_adminLastSyncKey);
        await prefs.remove(_adminBackendSyncKey);
      } else {
        await prefs.remove(_employeeReadIdsKey);
        await prefs.remove(_employeeUnreadCountKey);
        await prefs.remove(_employeeLastSyncKey);
        await prefs.remove(_employeeBackendSyncKey);
        await prefs.remove(_employeeReadStatesSyncKey);
      }
      
      debugPrint('Cleared ${isAdmin ? 'admin' : 'employee'} notification cache');
    } catch (e) {
      debugPrint('Error clearing ${isAdmin ? 'admin' : 'employee'} notification cache: $e');
    }
  }
}