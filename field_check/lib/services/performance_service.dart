import 'dart:async';
import 'package:flutter/foundation.dart';

/// Performance Service - Monitors and optimizes system performance
class PerformanceService {
  static final PerformanceService _instance = PerformanceService._internal();

  factory PerformanceService() => _instance;
  PerformanceService._internal();

  // Performance metrics
  final Map<String, PerformanceMetric> _metrics = {};
  final StreamController<Map<String, PerformanceMetric>> _metricsStream =
      StreamController<Map<String, PerformanceMetric>>.broadcast();

  Stream<Map<String, PerformanceMetric>> get metricsStream =>
      _metricsStream.stream;

  // Caching
  final Map<String, CachedData> _cache = {};
  final Map<String, Timer> _cacheTimers = {};

  /// Record performance metric
  void recordMetric(String name, Duration duration, {bool isSuccess = true}) {
    final metric = _metrics[name] ?? PerformanceMetric(name: name);

    metric.callCount++;
    metric.totalDuration += duration;
    metric.lastDuration = duration;
    metric.lastTimestamp = DateTime.now();
    metric.successCount += isSuccess ? 1 : 0;

    if (duration > metric.maxDuration) {
      metric.maxDuration = duration;
    }
    if (metric.minDuration == Duration.zero) {
      metric.minDuration = duration;
    } else if (duration < metric.minDuration) {
      metric.minDuration = duration;
    }

    _metrics[name] = metric;
    _metricsStream.add(Map.from(_metrics));

    debugPrint(
      '⏱️ $name: ${duration.inMilliseconds}ms (avg: ${metric.averageDuration.inMilliseconds}ms)',
    );
  }

  /// Get metric by name
  PerformanceMetric? getMetric(String name) => _metrics[name];

  /// Get all metrics
  Map<String, PerformanceMetric> getAllMetrics() => Map.from(_metrics);

  /// Clear metrics
  void clearMetrics() {
    _metrics.clear();
    _metricsStream.add({});
  }

  /// Cache data with TTL
  void cacheData(
    String key,
    dynamic data, {
    Duration ttl = const Duration(minutes: 5),
  }) {
    _cacheTimers[key]?.cancel();

    _cache[key] = CachedData(data: data, timestamp: DateTime.now(), ttl: ttl);

    _cacheTimers[key] = Timer(ttl, () {
      _cache.remove(key);
      _cacheTimers.remove(key);
      debugPrint('🗑️ Cache expired for key: $key');
    });

    debugPrint('💾 Cached data for key: $key (TTL: ${ttl.inSeconds}s)');
  }

  /// Get cached data
  dynamic getCachedData(String key) {
    final cached = _cache[key];
    if (cached != null && !cached.isExpired) {
      debugPrint('✅ Cache hit for key: $key');
      return cached.data;
    }
    _cache.remove(key);
    _cacheTimers[key]?.cancel();
    _cacheTimers.remove(key);
    return null;
  }

  /// Check if data is cached
  bool isCached(String key) {
    final cached = _cache[key];
    return cached != null && !cached.isExpired;
  }

  /// Clear cache
  void clearCache() {
    for (final timer in _cacheTimers.values) {
      timer.cancel();
    }
    _cache.clear();
    _cacheTimers.clear();
    debugPrint('🗑️ Cache cleared');
  }

  /// Get cache statistics
  Map<String, dynamic> getCacheStats() {
    return {
      'totalItems': _cache.length,
      'totalSize': _cache.values.fold(
        0,
        (sum, item) => sum + (item.data.toString().length),
      ),
      'items': _cache.entries
          .map(
            (e) => {
              'key': e.key,
              'size': e.value.data.toString().length,
              'age': DateTime.now().difference(e.value.timestamp).inSeconds,
              'ttl': e.value.ttl.inSeconds,
            },
          )
          .toList(),
    };
  }

  /// Batch location updates (for performance)
  final List<LocationUpdate> _locationBatch = [];
  Timer? _batchTimer;

  void addLocationUpdate(String employeeId, double lat, double lng) {
    _locationBatch.add(
      LocationUpdate(
        employeeId: employeeId,
        latitude: lat,
        longitude: lng,
        timestamp: DateTime.now(),
      ),
    );

    if (_locationBatch.length >= 10) {
      _flushLocationBatch();
    } else {
      _batchTimer ??= Timer(const Duration(seconds: 2), _flushLocationBatch);
    }
  }

  void _flushLocationBatch() {
    if (_locationBatch.isEmpty) return;

    debugPrint('📤 Flushing ${_locationBatch.length} location updates');
    // Send batch to backend
    _locationBatch.clear();
    _batchTimer?.cancel();
    _batchTimer = null;
  }

  /// Memory usage monitoring
  Future<MemoryStats> getMemoryStats() async {
    // This would require platform-specific implementation
    // For now, return placeholder
    return MemoryStats(usedMemory: 0, totalMemory: 0, percentageUsed: 0);
  }

  /// Dispose service
  void dispose() {
    _metricsStream.close();
    _batchTimer?.cancel();
    for (final timer in _cacheTimers.values) {
      timer.cancel();
    }
  }
}

/// Performance metric data class
class PerformanceMetric {
  final String name;
  int callCount = 0;
  int successCount = 0;
  Duration totalDuration = Duration.zero;
  Duration lastDuration = Duration.zero;
  Duration maxDuration = Duration.zero;
  Duration minDuration = Duration.zero;
  DateTime? lastTimestamp;

  PerformanceMetric({required this.name});

  Duration get averageDuration {
    if (callCount == 0) return Duration.zero;
    return Duration(milliseconds: totalDuration.inMilliseconds ~/ callCount);
  }

  double get successRate {
    if (callCount == 0) return 0;
    return (successCount / callCount) * 100;
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    'callCount': callCount,
    'successCount': successCount,
    'successRate': successRate,
    'averageDuration': averageDuration.inMilliseconds,
    'lastDuration': lastDuration.inMilliseconds,
    'maxDuration': maxDuration.inMilliseconds,
    'minDuration': minDuration.inMilliseconds,
    'lastTimestamp': lastTimestamp?.toIso8601String(),
  };
}

/// Cached data class
class CachedData {
  final dynamic data;
  final DateTime timestamp;
  final Duration ttl;

  CachedData({required this.data, required this.timestamp, required this.ttl});

  bool get isExpired => DateTime.now().difference(timestamp) > ttl;
}

/// Location update for batching
class LocationUpdate {
  final String employeeId;
  final double latitude;
  final double longitude;
  final DateTime timestamp;

  LocationUpdate({
    required this.employeeId,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
  });
}

/// Memory statistics
class MemoryStats {
  final int usedMemory;
  final int totalMemory;
  final double percentageUsed;

  MemoryStats({
    required this.usedMemory,
    required this.totalMemory,
    required this.percentageUsed,
  });
}
