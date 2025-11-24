import 'dart:async';
import 'package:flutter/foundation.dart';

/// Performance monitoring utility to track and optimize app responsiveness
class PerformanceMonitor {
  static final PerformanceMonitor _instance = PerformanceMonitor._internal();

  factory PerformanceMonitor() {
    return _instance;
  }

  PerformanceMonitor._internal();

  final Map<String, List<Duration>> _timings = {};
  final Map<String, int> _operationCounts = {};

  /// Track operation timing
  Future<T> measureOperation<T>(
    String operationName,
    Future<T> Function() operation,
  ) async {
    final stopwatch = Stopwatch()..start();
    try {
      final result = await operation();
      stopwatch.stop();
      _recordTiming(operationName, stopwatch.elapsed);
      return result;
    } catch (e) {
      stopwatch.stop();
      _recordTiming(operationName, stopwatch.elapsed);
      rethrow;
    }
  }

  /// Track synchronous operation timing
  T measureSync<T>(String operationName, T Function() operation) {
    final stopwatch = Stopwatch()..start();
    try {
      final result = operation();
      stopwatch.stop();
      _recordTiming(operationName, stopwatch.elapsed);
      return result;
    } catch (e) {
      stopwatch.stop();
      _recordTiming(operationName, stopwatch.elapsed);
      rethrow;
    }
  }

  void _recordTiming(String operationName, Duration duration) {
    _timings.putIfAbsent(operationName, () => []);
    _timings[operationName]!.add(duration);
    _operationCounts[operationName] =
        (_operationCounts[operationName] ?? 0) + 1;

    // Keep only last 100 measurements to avoid memory bloat
    if (_timings[operationName]!.length > 100) {
      _timings[operationName]!.removeAt(0);
    }
  }

  /// Get average timing for an operation (in milliseconds)
  double getAverageMs(String operationName) {
    final timings = _timings[operationName];
    if (timings == null || timings.isEmpty) return 0;
    final sum = timings.fold<int>(
      0,
      (acc, duration) => acc + duration.inMicroseconds,
    );
    return sum / timings.length / 1000;
  }

  /// Get operation count
  int getOperationCount(String operationName) {
    return _operationCounts[operationName] ?? 0;
  }

  /// Print performance report
  void printReport() {
    if (!kDebugMode) return; // Only print in debug mode
    // ignore: avoid_print
    print('\n═══════════════════════════════════════════════════════');
    // ignore: avoid_print
    print('PERFORMANCE MONITOR REPORT');
    // ignore: avoid_print
    print('═══════════════════════════════════════════════════════');
    _timings.forEach((operation, timings) {
      if (timings.isNotEmpty) {
        final avgMs = getAverageMs(operation);
        final count = getOperationCount(operation);
        final minMs = timings
            .map((d) => d.inMicroseconds / 1000)
            .reduce((a, b) => a < b ? a : b);
        final maxMs = timings
            .map((d) => d.inMicroseconds / 1000)
            .reduce((a, b) => a > b ? a : b);
        if (kDebugMode) {
          print(
            '$operation: avg=${avgMs.toStringAsFixed(2)}ms '
            'min=${minMs.toStringAsFixed(2)}ms '
            'max=${maxMs.toStringAsFixed(2)}ms (count=$count)',
          );
        }
      }
    });
    if (kDebugMode) print('═══════════════════════════════════════════════════════\n');
  }

  /// Clear all recordings
  void reset() {
    _timings.clear();
    _operationCounts.clear();
  }
}
