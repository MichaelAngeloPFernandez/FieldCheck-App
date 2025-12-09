import 'dart:async';
import 'package:flutter/foundation.dart';

class CheckInTimerEvent {
  final String employeeId;
  final DateTime checkInTime;
  final Duration timeout;
  final bool isExpired;
  final Duration remainingTime;

  CheckInTimerEvent({
    required this.employeeId,
    required this.checkInTime,
    required this.timeout,
    required this.isExpired,
    required this.remainingTime,
  });
}

class CheckInTimerService {
  static final CheckInTimerService _instance = CheckInTimerService._internal();

  factory CheckInTimerService() {
    return _instance;
  }

  CheckInTimerService._internal();

  // Streams
  final _timerStream = StreamController<CheckInTimerEvent>.broadcast();
  final _expirationStream = StreamController<String>.broadcast();

  Stream<CheckInTimerEvent> get timerStream => _timerStream.stream;
  Stream<String> get expirationStream => _expirationStream.stream;

  // State
  final Map<String, Timer> _activeTimers = {};
  final Map<String, DateTime> _checkInTimes = {};
  final Map<String, Duration> _timeouts = {};
  Duration _defaultTimeout = const Duration(hours: 8);

  /// Set default timeout duration
  void setDefaultTimeout(Duration timeout) {
    _defaultTimeout = timeout;
    debugPrint(
      '⏱️ Default timeout set to ${timeout.inHours}h ${timeout.inMinutes % 60}m',
    );
  }

  /// Get default timeout
  Duration getDefaultTimeout() => _defaultTimeout;

  /// Start check-in timer for employee
  void startCheckInTimer(String employeeId, {Duration? customTimeout}) {
    // Cancel existing timer if any
    _activeTimers[employeeId]?.cancel();

    final timeout = customTimeout ?? _defaultTimeout;
    final now = DateTime.now();

    _checkInTimes[employeeId] = now;
    _timeouts[employeeId] = timeout;

    debugPrint(
      '⏱️ Check-in timer started for $employeeId (${timeout.inHours}h)',
    );

    // Create periodic timer to emit updates
    _activeTimers[employeeId] = Timer.periodic(
      const Duration(seconds: 1),
      (timer) => _updateTimer(employeeId),
    );

    // Emit initial event
    _updateTimer(employeeId);

    // Schedule expiration check
    Future.delayed(timeout, () => _handleTimeout(employeeId));
  }

  /// Stop check-in timer
  void stopCheckInTimer(String employeeId) {
    _activeTimers[employeeId]?.cancel();
    _activeTimers.remove(employeeId);
    _checkInTimes.remove(employeeId);
    _timeouts.remove(employeeId);
    debugPrint('⏹️ Check-in timer stopped for $employeeId');
  }

  /// Update timer and emit event
  void _updateTimer(String employeeId) {
    final checkInTime = _checkInTimes[employeeId];
    final timeout = _timeouts[employeeId];

    if (checkInTime == null || timeout == null) return;

    final now = DateTime.now();
    final elapsed = now.difference(checkInTime);
    final remaining = timeout.inSeconds - elapsed.inSeconds;
    final isExpired = remaining <= 0;

    final event = CheckInTimerEvent(
      employeeId: employeeId,
      checkInTime: checkInTime,
      timeout: timeout,
      isExpired: isExpired,
      remainingTime: Duration(seconds: remaining.clamp(0, timeout.inSeconds)),
    );

    _timerStream.add(event);

    if (isExpired) {
      _handleTimeout(employeeId);
    }
  }

  /// Handle timer expiration
  void _handleTimeout(String employeeId) {
    _activeTimers[employeeId]?.cancel();
    _activeTimers.remove(employeeId);

    debugPrint('⏰ Check-in timer expired for $employeeId');
    _expirationStream.add(employeeId);
  }

  /// Get remaining time for employee
  Duration? getRemainingTime(String employeeId) {
    final checkInTime = _checkInTimes[employeeId];
    final timeout = _timeouts[employeeId];

    if (checkInTime == null || timeout == null) return null;

    final elapsed = DateTime.now().difference(checkInTime);
    final remaining = timeout.inSeconds - elapsed.inSeconds;

    return Duration(seconds: remaining.clamp(0, timeout.inSeconds));
  }

  /// Check if timer is active
  bool isTimerActive(String employeeId) =>
      _activeTimers.containsKey(employeeId);

  /// Get all active timers
  Map<String, Duration> getActiveTimers() {
    final result = <String, Duration>{};
    for (final entry in _checkInTimes.entries) {
      final remaining = getRemainingTime(entry.key);
      if (remaining != null && remaining.inSeconds > 0) {
        result[entry.key] = remaining;
      }
    }
    return result;
  }

  /// Format duration for display
  static String formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// Dispose resources
  void dispose() {
    for (final timer in _activeTimers.values) {
      timer.cancel();
    }
    _activeTimers.clear();
    _timerStream.close();
    _expirationStream.close();
  }
}
