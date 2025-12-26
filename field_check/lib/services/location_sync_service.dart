import 'dart:async';
import 'package:geolocator/geolocator.dart' as geolocator;
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../services/user_service.dart';
import '../config/api_config.dart';

/// Real-time location tracking service for continuous employee monitoring
/// Syncs location to backend every 10-15 seconds while employee is checked in
class LocationSyncService {
  final UserService _userService = UserService();
  late io.Socket _socket;

  bool _isCheckedIn = false;
  bool _isTracking = false;
  late StreamSubscription<geolocator.Position>? _positionSubscription;
  DateTime? _lastSyncTime;

  LocationSyncService();

  /// Initialize Socket.io connection for real-time updates
  Future<void> initializeSocket() async {
    try {
      final token = await _userService.getToken();
      final options = io.OptionBuilder()
          .setTransports(['websocket'])
          .enableAutoConnect()
          .setTimeout(20000)
          .setExtraHeaders({
            if (token != null) 'Authorization': 'Bearer $token',
          })
          .build();

      options['reconnection'] = true;
      options['reconnectionAttempts'] = 999999;
      options['reconnectionDelay'] = 500;

      _socket = io.io(ApiConfig.baseUrl, options);

      _socket.onConnect((_) {
        // Socket connected
      });

      _socket.onDisconnect((_) {
        // Socket disconnected
      });

      _socket.on('locationUpdateRequired', (_) {
        // Server requesting location update
      });
    } catch (e) {
      // Failed to initialize socket - ignored
    }
  }

  /// Start real-time location tracking during check-in
  /// Emits location updates to backend every 10-15 seconds
  void startTracking() {
    if (_isTracking) return;
    _isCheckedIn = true;
    _isTracking = true;
    _startLocationStream();
  }

  /// Stop location tracking during check-out
  void stopTracking() {
    _isCheckedIn = false;
    _isTracking = false;
    try {
      _positionSubscription?.cancel();
    } catch (e) {
      // Error stopping location tracking - ignored
    }
  }

  /// Internal method to start position stream and sync
  void _startLocationStream() {
    try {
      _positionSubscription =
          geolocator.Geolocator.getPositionStream(
            locationSettings: const geolocator.LocationSettings(
              accuracy: geolocator.LocationAccuracy.bestForNavigation,
              distanceFilter:
                  2, // Update every 2 meters for responsive tracking
              timeLimit: Duration(seconds: 30), // Allow 30s for GPS lock
            ),
          ).listen(
            (geolocator.Position position) {
              // Accept positions with reasonable accuracy (< 100m)
              // This is more lenient to handle poor GPS conditions
              if (position.accuracy > 0 && position.accuracy <= 50) {
                final now = DateTime.now();

                // Sync location every 15 seconds for backend updates
                if (_lastSyncTime == null ||
                    now.difference(_lastSyncTime!).inSeconds >= 15) {
                  _lastSyncTime = now;
                  _syncLocationToBackend(position);
                }
              }
            },
            onError: (e) {
              // Position stream error - retrying
              Future.delayed(const Duration(seconds: 5), _startLocationStream);
            },
          );
    } catch (e) {
      // Failed to start location stream - retrying
      Future.delayed(const Duration(seconds: 5), _startLocationStream);
    }
  }

  /// Sync employee location to backend via Socket.io
  void _syncLocationToBackend(geolocator.Position position) {
    if (!_isCheckedIn || !_socket.connected) return;

    try {
      final locationData = {
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy': position.accuracy,
        'timestamp': DateTime.now().toIso8601String(),
      };

      // Emit location update with instant delivery
      _socket.emit('employeeLocationUpdate', locationData);

      // Location synced silently
    } catch (e) {
      // Error syncing location - ignored
    }
  }

  /// Dispose resources
  void dispose() {
    try {
      _positionSubscription?.cancel();
      _socket.dispose();
    } catch (e) {
      // Error disposing - ignored
    }
  }

  /// Check if currently tracking
  bool get isTracking => _isTracking;

  /// Check if socket is connected
  bool get isConnected => _socket.connected;
}
