import 'dart:async';
import 'package:flutter/foundation.dart';

/// Auto-checkout service for managing offline employee checkouts
class AutoCheckoutService {
  static final AutoCheckoutService _instance = AutoCheckoutService._internal();

  factory AutoCheckoutService() => _instance;
  AutoCheckoutService._internal();

  // Configuration
  static const Duration offlineThreshold = Duration(minutes: 30);
  static const Duration warningThreshold = Duration(minutes: 25);

  // Tracking
  final Map<String, OfflineTracker> _offlineTrackers = {};
  final StreamController<AutoCheckoutEvent> _eventStream =
      StreamController<AutoCheckoutEvent>.broadcast();

  Stream<AutoCheckoutEvent> get eventStream => _eventStream.stream;

  /// Track employee offline status
  void trackEmployeeOffline(String employeeId, String employeeName) {
    if (_offlineTrackers.containsKey(employeeId)) {
      _offlineTrackers[employeeId]!.updateOfflineTime();
      return;
    }

    final tracker = OfflineTracker(
      employeeId: employeeId,
      employeeName: employeeName,
      offlineStartTime: DateTime.now(),
    );

    _offlineTrackers[employeeId] = tracker;

    // Start monitoring this employee
    _monitorEmployee(employeeId, tracker);

    debugPrint('📍 Started tracking offline: $employeeName ($employeeId)');
  }

  /// Employee came back online
  void employeeOnline(String employeeId) {
    if (_offlineTrackers.containsKey(employeeId)) {
      final tracker = _offlineTrackers[employeeId]!;
      tracker.cancelTimers();
      _offlineTrackers.remove(employeeId);
      debugPrint('✅ Employee back online: ${tracker.employeeName}');
    }
  }

  /// Monitor employee and trigger events
  void _monitorEmployee(String employeeId, OfflineTracker tracker) {
    // Warning at 25 minutes
    tracker.warningTimer = Timer(warningThreshold, () {
      if (_offlineTrackers.containsKey(employeeId)) {
        _eventStream.add(
          AutoCheckoutEvent(
            type: AutoCheckoutEventType.warning,
            employeeId: employeeId,
            employeeName: tracker.employeeName,
            message:
                '⚠️ ${tracker.employeeName} will be auto-checked out in 5 minutes if offline',
            timestamp: DateTime.now(),
          ),
        );
        debugPrint(
          '⚠️ Warning: ${tracker.employeeName} will be auto-checked out soon',
        );
      }
    });

    // Auto-checkout at 30 minutes
    tracker.checkoutTimer = Timer(offlineThreshold, () {
      if (_offlineTrackers.containsKey(employeeId)) {
        _eventStream.add(
          AutoCheckoutEvent(
            type: AutoCheckoutEventType.autoCheckout,
            employeeId: employeeId,
            employeeName: tracker.employeeName,
            message:
                '🔴 ${tracker.employeeName} has been auto-checked out (offline for 30 min)',
            timestamp: DateTime.now(),
            isVoid: true,
          ),
        );
        _offlineTrackers.remove(employeeId);
        debugPrint('🔴 Auto-checkout: ${tracker.employeeName}');
      }
    });
  }

  /// Get offline duration for employee
  Duration? getOfflineDuration(String employeeId) {
    final tracker = _offlineTrackers[employeeId];
    if (tracker == null) return null;
    return DateTime.now().difference(tracker.offlineStartTime);
  }

  /// Get all offline employees
  List<OfflineTracker> getOfflineEmployees() {
    return _offlineTrackers.values.toList();
  }

  /// Get offline count
  int getOfflineCount() => _offlineTrackers.length;

  /// Dispose service
  void dispose() {
    for (final tracker in _offlineTrackers.values) {
      tracker.cancelTimers();
    }
    _offlineTrackers.clear();
    _eventStream.close();
  }
}

/// Offline tracker for individual employee
class OfflineTracker {
  final String employeeId;
  final String employeeName;
  final DateTime offlineStartTime;
  Timer? warningTimer;
  Timer? checkoutTimer;

  OfflineTracker({
    required this.employeeId,
    required this.employeeName,
    required this.offlineStartTime,
  });

  void updateOfflineTime() {
    // Update logic if needed
  }

  void cancelTimers() {
    warningTimer?.cancel();
    checkoutTimer?.cancel();
  }

  Duration get offlineDuration => DateTime.now().difference(offlineStartTime);
}

/// Auto-checkout event
class AutoCheckoutEvent {
  final AutoCheckoutEventType type;
  final String employeeId;
  final String employeeName;
  final String message;
  final DateTime timestamp;
  final bool isVoid;

  AutoCheckoutEvent({
    required this.type,
    required this.employeeId,
    required this.employeeName,
    required this.message,
    required this.timestamp,
    this.isVoid = false,
  });
}

/// Event types
enum AutoCheckoutEventType { warning, autoCheckout }

/// Employee checkout configuration
class EmployeeCheckoutConfig {
  final String employeeId;
  final int autoCheckoutMinutes;
  final int maxTasksPerDay;
  final bool autoCheckoutEnabled;

  EmployeeCheckoutConfig({
    required this.employeeId,
    this.autoCheckoutMinutes = 30,
    this.maxTasksPerDay = 10,
    this.autoCheckoutEnabled = true,
  });

  Map<String, dynamic> toMap() => {
    'employeeId': employeeId,
    'autoCheckoutMinutes': autoCheckoutMinutes,
    'maxTasksPerDay': maxTasksPerDay,
    'autoCheckoutEnabled': autoCheckoutEnabled,
  };

  factory EmployeeCheckoutConfig.fromMap(Map<String, dynamic> map) {
    return EmployeeCheckoutConfig(
      employeeId: map['employeeId'] ?? '',
      autoCheckoutMinutes: map['autoCheckoutMinutes'] ?? 30,
      maxTasksPerDay: map['maxTasksPerDay'] ?? 10,
      autoCheckoutEnabled: map['autoCheckoutEnabled'] ?? true,
    );
  }
}
