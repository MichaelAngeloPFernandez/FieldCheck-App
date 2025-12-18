import 'dart:async';
import 'package:flutter/foundation.dart';

class CheckInTimerEvent {
  final String employeeId;
  final DateTime checkInTime;
  final Duration elapsedTime;

  CheckInTimerEvent({
    required this.employeeId,
    required this.checkInTime,
    required this.elapsedTime,
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

  Stream<CheckInTimerEvent> get timerStream => _timerStream.stream;

  // State
  final Map<String, Timer> _activeTimers = {};
  final Map<String, DateTime> _checkInTimes = {};

  /// Start elapsed-time tracking for employee
  void startCheckInTimer(String employeeId, {DateTime? checkInTime}) {
    // Cancel existing timer if any
    _activeTimers[employeeId]?.cancel();

    final now = DateTime.now();
    final startTime = checkInTime ?? now;

    _checkInTimes[employeeId] = startTime;

    debugPrint('Elapsed-time tracking started for $employeeId at $startTime');

    // Create periodic timer to emit updates
    _activeTimers[employeeId] = Timer.periodic(
      const Duration(seconds: 1),
      (timer) => _updateTimer(employeeId),
    );

    // Emit initial event with 0 elapsed time to show 00:00 on first display
    _timerStream.add(
      CheckInTimerEvent(
        employeeId: employeeId,
        checkInTime: startTime,
        elapsedTime: Duration.zero,
      ),
    );
  }

  /// Stop check-in timer
  void stopCheckInTimer(String employeeId) {
    _activeTimers[employeeId]?.cancel();
    _activeTimers.remove(employeeId);
    _checkInTimes.remove(employeeId);
    debugPrint('Check-in timer stopped for $employeeId');
  }

  /// Update timer and emit event
  void _updateTimer(String employeeId) {
    final checkInTime = _checkInTimes[employeeId];
    if (checkInTime == null) return;

    final now = DateTime.now();
    final elapsed = now.difference(checkInTime);

    final event = CheckInTimerEvent(
      employeeId: employeeId,
      checkInTime: checkInTime,
      elapsedTime: elapsed,
    );

    _timerStream.add(event);
  }

  /// Get elapsed time for employee
  Duration? getElapsedTime(String employeeId) {
    final checkInTime = _checkInTimes[employeeId];
    if (checkInTime == null) return null;
    return DateTime.now().difference(checkInTime);
  }

  /// Check if timer is active
  bool isTimerActive(String employeeId) =>
      _activeTimers.containsKey(employeeId);

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
  }
}
