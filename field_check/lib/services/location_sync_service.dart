import 'dart:async';
import 'package:geolocator/geolocator.dart' as geolocator;
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:flutter/foundation.dart';
import '../services/user_service.dart';
import '../config/api_config.dart';

/// Real-time location tracking service for continuous employee monitoring
/// Syncs location to backend every 10-15 seconds while employee is checked in
class LocationSyncService {
  static final LocationSyncService _instance = LocationSyncService._internal();
  factory LocationSyncService() => _instance;
  LocationSyncService._internal();

  final UserService _userService = UserService();
  late io.Socket _socket;

  final ValueNotifier<bool> _connected = ValueNotifier<bool>(false);
  final ValueNotifier<String?> _lastError = ValueNotifier<String?>(null);
  final ValueNotifier<Map<String, dynamic>?> _lastEmitted =
      ValueNotifier<Map<String, dynamic>?>(null);
  final ValueNotifier<geolocator.Position?> _lastPosition =
      ValueNotifier<geolocator.Position?>(null);
  String _socketUrl = ApiConfig.baseUrl;

  bool _isCheckedIn = false;
  bool _sharingEnabled = true;
  bool _isTracking = false;
  bool _initialized = false;
  bool _pendingEmitOnConnect = false;
  late StreamSubscription<geolocator.Position>? _positionSubscription;
  DateTime? _lastSyncTime;
  final ValueNotifier<DateTime?> _lastSharedAt = ValueNotifier<DateTime?>(null);

  static const double _webAccuracyThresholdMeters = 1000.0;
  static const double _defaultAccuracyThresholdMeters = 100.0;

  /// Initialize Socket.io connection for real-time updates
  Future<void> initializeSocket() async {
    try {
      if (_initialized) {
        return;
      }
      final token = await _userService.getToken();
      final options = io.OptionBuilder()
          .setTransports(['websocket', 'polling'])
          .enableAutoConnect()
          .setTimeout(20000)
          .setExtraHeaders({
            if (token != null) 'Authorization': 'Bearer $token',
          })
          .build();

      options['reconnection'] = true;
      options['reconnectionAttempts'] = 999999;
      options['reconnectionDelay'] = 500;

      _socketUrl = ApiConfig.baseUrl;
      _socket = io.io(_socketUrl, options);
      _initialized = true;

      _socket.onConnect((_) {
        _connected.value = true;
        _lastError.value = null;
        debugPrint('✅ LocationSyncService: Connected ($_socketUrl)');
        try {
          // Notify admins that this employee is online
          _emitEmployeeOnline();
        } catch (_) {}

        // If sharing/tracking started before socket was connected, emit once now.
        if (_sharingEnabled && (_pendingEmitOnConnect || _isTracking)) {
          _pendingEmitOnConnect = false;
          _emitCurrentOnce();
        }
      });

      _socket.onDisconnect((_) {
        _connected.value = false;
        debugPrint('❌ LocationSyncService: Disconnected');
      });

      _socket.onConnectError((err) {
        _connected.value = false;
        _lastError.value = 'connect_error: $err';
        debugPrint('❌ LocationSyncService: connect_error $err');
      });

      _socket.onError((err) {
        _lastError.value = 'error: $err';
        debugPrint('❌ LocationSyncService: error $err');
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
    if (!_initialized) {
      _lastError.value = 'socket_not_initialized: call initializeSocket() first';
      _pendingEmitOnConnect = true;
      return;
    }
    if (!_socket.connected) {
      _pendingEmitOnConnect = true;
      return;
    }
    _emitCurrentOnce();
  }

  /// Start live location sharing even when not checked-in.
  /// This powers the admin map "online/roaming" status.
  void startSharing() {
    _sharingEnabled = true;
    if (_isTracking) return;
    _isTracking = true;
    _startLocationStream();
    if (!_initialized) {
      _lastError.value = 'socket_not_initialized: call initializeSocket() first';
      _pendingEmitOnConnect = true;
      return;
    }
    if (!_socket.connected) {
      _pendingEmitOnConnect = true;
      return;
    }
    _emitCurrentOnce();
  }

  Future<void> _emitCurrentOnce() async {
    try {
      if (!_sharingEnabled || !_initialized || !_socket.connected) return;
      final pos = await geolocator.Geolocator.getCurrentPosition(
        locationSettings: const geolocator.LocationSettings(
          accuracy: geolocator.LocationAccuracy.best,
          timeLimit: Duration(seconds: 10),
        ),
      );
      _lastPosition.value = pos;
      _syncLocationToBackend(pos);
    } catch (e) {
      _lastError.value = 'get_current_error: $e';
    }
  }

  /// Stop location tracking during check-out
  void stopTracking() {
    _isCheckedIn = false;
    _isTracking = false;
    _sharingEnabled = false;
    try {
      _positionSubscription?.cancel();
    } catch (e) {
      // Error stopping location tracking - ignored
    }
  }

  void stopSharing() {
    _sharingEnabled = false;
    _isTracking = false;
    try {
      _positionSubscription?.cancel();
    } catch (_) {}
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
              _lastPosition.value = position;
              // Accept positions with reasonable accuracy (< 100m)
              // This is more lenient to handle poor GPS conditions
              final threshold = kIsWeb
                  ? _webAccuracyThresholdMeters
                  : _defaultAccuracyThresholdMeters;
              if (position.accuracy > 0 && position.accuracy <= threshold) {
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
              _lastError.value = 'position_stream_error: $e';
              // Position stream error - retrying
              Future.delayed(const Duration(seconds: 5), _startLocationStream);
            },
          );
    } catch (e) {
      _lastError.value = 'position_stream_start_error: $e';
      // Failed to start location stream - retrying
      Future.delayed(const Duration(seconds: 5), _startLocationStream);
    }
  }

  /// Sync employee location to backend via Socket.io
  void _syncLocationToBackend(geolocator.Position position) {
    if (!_sharingEnabled || !_initialized || !_socket.connected) return;

    try {
      final profile = _userService.currentUser;
      final locationData = {
        'employeeId': profile?.id,
        'name': profile?.name,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy': position.accuracy,
        'timestamp': DateTime.now().toIso8601String(),
        // Map can interpret this as roaming/online when not checked in
        'isCheckedIn': _isCheckedIn,
      };

      // Emit location update with instant delivery
      _socket.emit('employeeLocationUpdate', locationData);

      _lastEmitted.value = locationData;

      _lastSharedAt.value = DateTime.now();

      // Location synced silently
    } catch (e) {
      _lastError.value = 'emit_error: $e';
      // Error syncing location - ignored
    }
  }

  /// Dispose resources
  void dispose() {
    try {
      _positionSubscription?.cancel();
      _socket.dispose();
      _lastSharedAt.dispose();
      _connected.dispose();
      _lastError.dispose();
      _lastEmitted.dispose();
      _lastPosition.dispose();
    } catch (e) {
      // Error disposing - ignored
    }
  }

  /// Check if currently tracking
  bool get isTracking => _isTracking;

  bool get isSharingEnabled => _sharingEnabled;

  /// Check if socket is connected
  bool get isConnected => _socket.connected;

  ValueListenable<bool> get connectedListenable => _connected;
  ValueListenable<String?> get lastErrorListenable => _lastError;
  ValueListenable<Map<String, dynamic>?> get lastEmittedListenable =>
      _lastEmitted;
  ValueListenable<geolocator.Position?> get lastPositionListenable =>
      _lastPosition;
  String get socketUrl => _socketUrl;

  ValueListenable<DateTime?> get lastSharedListenable => _lastSharedAt;
  DateTime? get lastSharedAt => _lastSharedAt.value;

  void _emitEmployeeOnline() {
    final profile = _userService.currentUser;
    _socket.emit('employeeOnline', {
      'employeeId': profile?.id,
      'name': profile?.name,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }
}
