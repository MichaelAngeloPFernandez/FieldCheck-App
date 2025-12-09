import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';

class LocationUpdate {
  final double latitude;
  final double longitude;
  final double accuracy;
  final double altitude;
  final double speed;
  final DateTime timestamp;
  final bool isValid;

  LocationUpdate({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.altitude,
    required this.speed,
    required this.timestamp,
    this.isValid = true,
  });

  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'accuracy': accuracy,
    'altitude': altitude,
    'speed': speed,
    'timestamp': timestamp.toIso8601String(),
    'isValid': isValid,
  };
}

class LocationTrackingEngine {
  static final LocationTrackingEngine _instance =
      LocationTrackingEngine._internal();

  factory LocationTrackingEngine() {
    return _instance;
  }

  LocationTrackingEngine._internal();

  // Streams
  final _locationStream = StreamController<LocationUpdate>.broadcast();
  final _gpsStatusStream = StreamController<bool>.broadcast();
  final _accuracyStream = StreamController<double>.broadcast();

  Stream<LocationUpdate> get locationStream => _locationStream.stream;
  Stream<bool> get gpsStatusStream => _gpsStatusStream.stream;
  Stream<double> get accuracyStream => _accuracyStream.stream;

  // State
  StreamSubscription<Position>? _positionSubscription;
  bool _isTracking = false;
  bool _gpsEnabled = false;
  LocationUpdate? _lastLocation;
  DateTime? _lastUpdateTime;
  final List<LocationUpdate> _locationHistory = [];
  static const int maxHistorySize = 100;

  // Configuration
  static const Duration updateInterval = Duration(seconds: 10);
  static const double accuracyThreshold = 50.0; // meters
  static const double minDistanceChange = 5.0; // meters

  /// Initialize location tracking
  Future<bool> initialize() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        final result = await Geolocator.requestPermission();
        if (result == LocationPermission.denied) {
          debugPrint('❌ Location permission denied');
          return false;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        debugPrint('❌ Location permission permanently denied');
        return false;
      }

      _gpsEnabled = await Geolocator.isLocationServiceEnabled();
      _gpsStatusStream.add(_gpsEnabled);

      debugPrint('✅ Location tracking initialized');
      return true;
    } catch (e) {
      debugPrint('❌ Location initialization error: $e');
      return false;
    }
  }

  /// Start continuous location tracking
  Future<void> startTracking() async {
    if (_isTracking) return;

    try {
      _isTracking = true;
      debugPrint('📍 Starting location tracking');

      // Get initial position
      final initialPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        timeLimit: const Duration(seconds: 10),
      );
      _processLocation(initialPosition);

      // Start continuous tracking
      _positionSubscription =
          Geolocator.getPositionStream(
            locationSettings: LocationSettings(
              accuracy: LocationAccuracy.best,
              distanceFilter: minDistanceChange.toInt(),
              timeLimit: updateInterval,
            ),
          ).listen(
            _processLocation,
            onError: (error) {
              debugPrint('❌ Location stream error: $error');
              _gpsEnabled = false;
              _gpsStatusStream.add(false);
            },
          );
    } catch (e) {
      debugPrint('❌ Error starting tracking: $e');
      _isTracking = false;
    }
  }

  /// Stop location tracking
  Future<void> stopTracking() async {
    _isTracking = false;
    await _positionSubscription?.cancel();
    debugPrint('⏹️ Location tracking stopped');
  }

  /// Process incoming location data
  void _processLocation(Position position) {
    try {
      final now = DateTime.now();

      // Validate location accuracy
      final isAccurate = position.accuracy <= accuracyThreshold;

      // Create location update
      final update = LocationUpdate(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        altitude: position.altitude,
        speed: position.speed,
        timestamp: now,
        isValid: isAccurate,
      );

      // Update state
      _lastLocation = update;
      _lastUpdateTime = now;
      _gpsEnabled = true;

      // Add to history
      _locationHistory.add(update);
      if (_locationHistory.length > maxHistorySize) {
        _locationHistory.removeAt(0);
      }

      // Emit streams
      _locationStream.add(update);
      _gpsStatusStream.add(true);
      _accuracyStream.add(position.accuracy);

      if (kDebugMode) {
        debugPrint(
          '📍 Location: (${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}) '
          '• Accuracy: ${position.accuracy.toStringAsFixed(1)}m '
          '• Speed: ${position.speed.toStringAsFixed(2)}m/s',
        );
      }
    } catch (e) {
      debugPrint('❌ Error processing location: $e');
    }
  }

  /// Get current location
  Future<LocationUpdate?> getCurrentLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        timeLimit: const Duration(seconds: 10),
      );
      final update = LocationUpdate(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        altitude: position.altitude,
        speed: position.speed,
        timestamp: DateTime.now(),
      );
      return update;
    } catch (e) {
      debugPrint('❌ Error getting current location: $e');
      return null;
    }
  }

  /// Get last location
  LocationUpdate? getLastLocation() => _lastLocation;

  /// Get location history
  List<LocationUpdate> getLocationHistory() => List.from(_locationHistory);

  /// Get GPS status
  bool isGpsEnabled() => _gpsEnabled;

  /// Get tracking status
  bool isTracking() => _isTracking;

  /// Get last update time
  DateTime? getLastUpdateTime() => _lastUpdateTime;

  /// Get time since last update
  Duration? getTimeSinceLastUpdate() {
    if (_lastUpdateTime == null) return null;
    return DateTime.now().difference(_lastUpdateTime!);
  }

  /// Calculate distance between two locations
  static double calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadiusMeters = 6371000.0;
    final dLat = _toRad(lat2 - lat1);
    final dLon = _toRad(lon2 - lon1);
    final a =
        Math.sin(dLat / 2) * Math.sin(dLat / 2) +
        Math.cos(_toRad(lat1)) *
            Math.cos(_toRad(lat2)) *
            Math.sin(dLon / 2) *
            Math.sin(dLon / 2);
    final c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return earthRadiusMeters * c;
  }

  static double _toRad(double degrees) => degrees * 3.14159265359 / 180;

  /// Dispose resources
  void dispose() {
    _positionSubscription?.cancel();
    _locationStream.close();
    _gpsStatusStream.close();
    _accuracyStream.close();
  }
}

// Math helper
class Math {
  static double sin(double x) => _sin(x);
  static double cos(double x) => _cos(x);
  static double atan2(double y, double x) => _atan2(y, x);
  static double sqrt(double x) => _sqrt(x);

  static double _sin(double x) {
    // Simplified sine approximation
    x = x % (2 * 3.14159265359);
    if (x > 3.14159265359) x -= 2 * 3.14159265359;
    final x2 = x * x;
    return x * (1 - x2 / 6 + x2 * x2 / 120 - x2 * x2 * x2 / 5040);
  }

  static double _cos(double x) {
    x = x % (2 * 3.14159265359);
    final x2 = x * x;
    return 1 - x2 / 2 + x2 * x2 / 24 - x2 * x2 * x2 / 720;
  }

  static double _atan2(double y, double x) {
    if (x == 0 && y == 0) return 0;
    if (x > 0) return _atan(y / x);
    if (x < 0 && y >= 0) return _atan(y / x) + 3.14159265359;
    if (x < 0 && y < 0) return _atan(y / x) - 3.14159265359;
    if (x == 0 && y > 0) return 3.14159265359 / 2;
    return -3.14159265359 / 2;
  }

  static double _atan(double x) {
    final x2 = x * x;
    return x / (1 + 0.28 * x2) * (1 + x2 / (3 + 0.409 * x2));
  }

  static double _sqrt(double x) {
    if (x < 0) return 0;
    if (x == 0) return 0;
    double result = x;
    for (int i = 0; i < 10; i++) {
      result = (result + x / result) / 2;
    }
    return result;
  }
}
