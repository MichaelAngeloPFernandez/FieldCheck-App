import 'dart:async';
import 'package:flutter/foundation.dart';
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
        if (kDebugMode) print('LocationSyncService: Socket connected');
      });

      _socket.onDisconnect((_) {
        if (kDebugMode) print('LocationSyncService: Socket disconnected');
      });

      _socket.on('locationUpdateRequired', (_) {
        if (kDebugMode) {
          print('LocationSyncService: Server requesting location update');
        }
      });
    } catch (e) {
      if (kDebugMode) {
        print('Failed to initialize socket in LocationSyncService: $e');
      }
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
      if (kDebugMode) print('Error stopping location tracking: $e');
    }
  }

  /// Internal method to start position stream and sync
  void _startLocationStream() {
    try {
      _positionSubscription =
          geolocator.Geolocator.getPositionStream(
            locationSettings: const geolocator.LocationSettings(
              accuracy: geolocator.LocationAccuracy.bestForNavigation,
              distanceFilter: 5, // Update every 5 meters
            ),
          ).listen(
            (geolocator.Position position) {
              final now = DateTime.now();

              // Sync location every 10-15 seconds
              if (_lastSyncTime == null ||
                  now.difference(_lastSyncTime!).inSeconds >= 10) {
                _lastSyncTime = now;
                _syncLocationToBackend(position);
              }
            },
            onError: (e) {
              if (kDebugMode) {
                print('LocationSyncService: Position stream error: $e');
              }
            },
          );
    } catch (e) {
      if (kDebugMode) print('Failed to start location stream: $e');
    }
  }

  /// Sync employee location to backend via Socket.io
  void _syncLocationToBackend(geolocator.Position position) {
    if (!_isCheckedIn || !_socket.connected) return;

    try {
      _socket.emit('employeeLocationUpdate', {
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy': position.accuracy,
        'timestamp': DateTime.now().toIso8601String(),
      });
      if (kDebugMode) {
        print(
          'LocationSyncService: Synced location (${position.latitude}, ${position.longitude})',
        );
      }
    } catch (e) {
      if (kDebugMode) print('Error syncing location to backend: $e');
    }
  }

  /// Dispose resources
  void dispose() {
    try {
      _positionSubscription?.cancel();
      _socket.dispose();
    } catch (e) {
      if (kDebugMode) print('Error disposing LocationSyncService: $e');
    }
  }

  /// Check if currently tracking
  bool get isTracking => _isTracking;

  /// Check if socket is connected
  bool get isConnected => _socket.connected;
}
