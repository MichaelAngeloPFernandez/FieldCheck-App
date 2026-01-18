import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../config/api_config.dart';
import '../services/user_service.dart';

/// Employee status enum
enum EmployeeStatus {
  available, // 🟢 Green - Online, idle, ready for tasks
  moving, // 🔵 Blue - Online, actively moving
  busy, // 🔴 Red - Active task or high workload
  offline, // ⚫ Gray - Offline
}

/// Employee location data model
class EmployeeLocation {
  final String employeeId;
  final String name;
  final double latitude;
  final double longitude;
  final double accuracy;
  final double? speed;
  final EmployeeStatus status;
  final DateTime timestamp;
  final int activeTaskCount;
  final double workloadScore;
  final String? currentGeofence;
  final double? distanceToNearestTask;
  final bool isOnline;
  final int? batteryLevel;

  EmployeeLocation({
    required this.employeeId,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    this.speed,
    required this.status,
    required this.timestamp,
    required this.activeTaskCount,
    required this.workloadScore,
    this.currentGeofence,
    this.distanceToNearestTask,
    required this.isOnline,
    this.batteryLevel,
  });

  factory EmployeeLocation.fromJson(Map<String, dynamic> json) {
    return EmployeeLocation(
      employeeId: json['employeeId'] as String,
      name: json['name'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      accuracy: (json['accuracy'] as num).toDouble(),
      speed: json['speed'] != null ? (json['speed'] as num).toDouble() : null,
      status: _parseStatus(json['status']),
      timestamp: DateTime.parse(json['timestamp'] as String),
      activeTaskCount: json['activeTaskCount'] as int? ?? 0,
      workloadScore: (json['workloadScore'] as num?)?.toDouble() ?? 0.0,
      currentGeofence: json['currentGeofence'] as String?,
      distanceToNearestTask: json['distanceToNearestTask'] != null
          ? (json['distanceToNearestTask'] as num).toDouble()
          : null,
      isOnline: json['isOnline'] as bool? ?? true,
      batteryLevel: json['batteryLevel'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
    'employeeId': employeeId,
    'name': name,
    'latitude': latitude,
    'longitude': longitude,
    'accuracy': accuracy,
    'speed': speed,
    'status': status.toString(),
    'timestamp': timestamp.toIso8601String(),
    'activeTaskCount': activeTaskCount,
    'workloadScore': workloadScore,
    'currentGeofence': currentGeofence,
    'distanceToNearestTask': distanceToNearestTask,
    'isOnline': isOnline,
    'batteryLevel': batteryLevel,
  };

  static EmployeeStatus _parseStatus(dynamic status) {
    if (status is String) {
      return EmployeeStatus.values.firstWhere(
        (e) => e.toString() == 'EmployeeStatus.$status',
        orElse: () => EmployeeStatus.offline,
      );
    }
    return EmployeeStatus.offline;
  }
}

/// Enhanced employee location service with real-time tracking
class EmployeeLocationService {
  static final EmployeeLocationService _instance =
      EmployeeLocationService._internal();

  factory EmployeeLocationService() => _instance;
  EmployeeLocationService._internal();

  final UserService _userService = UserService();
  late io.Socket _socket;

  // Streams
  final _employeeLocationsController =
      StreamController<List<EmployeeLocation>>.broadcast();
  final _singleLocationController =
      StreamController<EmployeeLocation>.broadcast();
  final _statusChangeController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<List<EmployeeLocation>> get employeeLocationsStream =>
      _employeeLocationsController.stream;
  Stream<EmployeeLocation> get singleLocationStream =>
      _singleLocationController.stream;
  Stream<Map<String, dynamic>> get statusChangeStream =>
      _statusChangeController.stream;

  bool _isConnected = false;
  bool get isConnected => _isConnected;

  final Map<String, EmployeeLocation> _cachedLocations = {};
  final Map<String, List<EmployeeLocation>> _locationHistory = {};
  static const int maxHistoryPerEmployee = 50;

  /// Initialize socket connection for real-time location updates
  Future<void> initialize() async {
    if (_isConnected) return;

    try {
      final token = await _userService.getToken();
      final options = io.OptionBuilder()
          .setTransports(['websocket', 'polling'])
          .setExtraHeaders({
            if (token != null) 'Authorization': 'Bearer $token',
          })
          .setTimeout(60000)
          .build();

      options['reconnection'] = true;
      options['reconnectionAttempts'] = 999999;
      options['reconnectionDelay'] = 1000;
      options['reconnectionDelayMax'] = 10000;

      _socket = io.io(ApiConfig.baseUrl, options);

      _socket.onConnect((_) {
        debugPrint('✅ EmployeeLocationService: Connected');
        _isConnected = true;
        _joinLocationRoom();
      });

      _socket.onDisconnect((_) {
        debugPrint('❌ EmployeeLocationService: Disconnected');
        _isConnected = false;
      });

      _setupEventListeners();
    } catch (e) {
      debugPrint('❌ EmployeeLocationService init error: $e');
    }
  }

  void _setupEventListeners() {
    // Real-time employee location updates
    _socket.on('employeeLocationUpdate', (data) {
      try {
        final location = EmployeeLocation.fromJson(
          data as Map<String, dynamic>,
        );
        _updateLocationCache(location);
        _singleLocationController.add(location);
        _broadcastAllLocations();
      } catch (e) {
        debugPrint('❌ Error processing location update: $e');
      }
    });

    // Batch location updates
    _socket.on('employeeLocationsUpdate', (data) {
      try {
        final locations = (data as List)
            .map((e) => EmployeeLocation.fromJson(e as Map<String, dynamic>))
            .toList();
        for (final location in locations) {
          _updateLocationCache(location);
        }
        _employeeLocationsController.add(locations);
      } catch (e) {
        debugPrint('❌ Error processing batch locations: $e');
      }
    });

    // Employee status changes
    _socket.on('employeeStatusChange', (data) {
      try {
        _statusChangeController.add(data as Map<String, dynamic>);
        // Update cached location with new status
        final employeeId = data['employeeId'] as String;
        if (_cachedLocations.containsKey(employeeId)) {
          final oldLocation = _cachedLocations[employeeId]!;
          final newStatus = EmployeeStatus.values.firstWhere(
            (e) => e.toString() == 'EmployeeStatus.${data['status']}',
            orElse: () => EmployeeStatus.offline,
          );
          final updatedLocation = EmployeeLocation(
            employeeId: oldLocation.employeeId,
            name: oldLocation.name,
            latitude: oldLocation.latitude,
            longitude: oldLocation.longitude,
            accuracy: oldLocation.accuracy,
            speed: oldLocation.speed,
            status: newStatus,
            timestamp: DateTime.now(),
            activeTaskCount:
                data['activeTaskCount'] ?? oldLocation.activeTaskCount,
            workloadScore: data['workloadScore'] ?? oldLocation.workloadScore,
            currentGeofence: oldLocation.currentGeofence,
            distanceToNearestTask: oldLocation.distanceToNearestTask,
            isOnline: data['isOnline'] ?? oldLocation.isOnline,
            batteryLevel: oldLocation.batteryLevel,
          );
          _updateLocationCache(updatedLocation);
          _broadcastAllLocations();
        }
      } catch (e) {
        debugPrint('❌ Error processing status change: $e');
      }
    });

    // Employee went offline
    _socket.on('employeeOffline', (data) {
      try {
        final employeeId = data['employeeId'] as String;
        if (_cachedLocations.containsKey(employeeId)) {
          final oldLocation = _cachedLocations[employeeId]!;
          final offlineLocation = EmployeeLocation(
            employeeId: oldLocation.employeeId,
            name: oldLocation.name,
            latitude: oldLocation.latitude,
            longitude: oldLocation.longitude,
            accuracy: oldLocation.accuracy,
            speed: oldLocation.speed,
            status: EmployeeStatus.offline,
            timestamp: DateTime.now(),
            activeTaskCount: oldLocation.activeTaskCount,
            workloadScore: oldLocation.workloadScore,
            currentGeofence: oldLocation.currentGeofence,
            distanceToNearestTask: oldLocation.distanceToNearestTask,
            isOnline: false,
            batteryLevel: oldLocation.batteryLevel,
          );
          _updateLocationCache(offlineLocation);
          _broadcastAllLocations();
        }
      } catch (e) {
        debugPrint('❌ Error processing offline event: $e');
      }
    });
  }

  void _updateLocationCache(EmployeeLocation location) {
    _cachedLocations[location.employeeId] = location;

    // Store in history
    if (!_locationHistory.containsKey(location.employeeId)) {
      _locationHistory[location.employeeId] = [];
    }
    _locationHistory[location.employeeId]!.add(location);

    // Keep history size manageable
    if (_locationHistory[location.employeeId]!.length > maxHistoryPerEmployee) {
      _locationHistory[location.employeeId]!.removeAt(0);
    }
  }

  void _broadcastAllLocations() {
    final locations = _cachedLocations.values.toList();
    _employeeLocationsController.add(locations);
  }

  void _joinLocationRoom() {
    if (_socket.connected) {
      _socket.emit('joinLocationRoom', {});
    }
  }

  /// Get all cached employee locations
  List<EmployeeLocation> getAllLocations() {
    return _cachedLocations.values.toList();
  }

  /// Get location for specific employee
  EmployeeLocation? getEmployeeLocation(String employeeId) {
    return _cachedLocations[employeeId];
  }

  /// Get location history for employee
  List<EmployeeLocation> getLocationHistory(String employeeId) {
    return _locationHistory[employeeId] ?? [];
  }

  /// Get employees by status
  List<EmployeeLocation> getEmployeesByStatus(EmployeeStatus status) {
    return _cachedLocations.values
        .where((loc) => loc.status == status)
        .toList();
  }

  /// Get online employees
  List<EmployeeLocation> getOnlineEmployees() {
    return _cachedLocations.values.where((loc) => loc.isOnline).toList();
  }

  /// Get offline employees
  List<EmployeeLocation> getOfflineEmployees() {
    return _cachedLocations.values.where((loc) => !loc.isOnline).toList();
  }

  /// Emit location update from employee
  void emitLocationUpdate(Map<String, dynamic> locationData) {
    if (_socket.connected) {
      _socket.emit('employeeLocationUpdate', locationData);
    }
  }

  /// Request admin to manually update employee status
  void requestStatusUpdate(String employeeId, EmployeeStatus newStatus) {
    if (_socket.connected) {
      _socket.emit('requestStatusUpdate', {
        'employeeId': employeeId,
        'status': newStatus.toString().split('.').last,
      });
    }
  }

  void dispose() {
    _employeeLocationsController.close();
    _singleLocationController.close();
    _statusChangeController.close();
    _socket.disconnect();
  }
}
