import 'dart:math';
import 'package:latlong2/latlong.dart';
import 'user_model.dart';

class Geofence {
  final String? id;
  final String name;
  final String address;
  final double latitude;
  final double longitude;
  final double radius;
  final bool isActive;
  final String? createdBy;
  final DateTime? createdAt;
  final GeofenceShape shape;
  final List<UserModel>? assignedEmployees;
  final String? labelLetter;

  Geofence({
    this.id,
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.radius,
    this.isActive = true,
    this.createdBy,
    this.createdAt,
    this.shape = GeofenceShape.circle,
    this.assignedEmployees,
    this.labelLetter, // Initialize new field
  });

  // Create a copy with some fields changed
  Geofence copyWith({
    String? id,
    String? name,
    String? address,
    double? latitude,
    double? longitude,
    double? radius,
    bool? isActive,
    String? createdBy,
    DateTime? createdAt,
    GeofenceShape? shape,
    List<UserModel>? assignedEmployees,
    String? labelLetter,
  }) {
    return Geofence(
      id: id ?? this.id,
      name: name ?? this.name,
      address: address ?? this.address,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      radius: radius ?? this.radius,
      isActive: isActive ?? this.isActive,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      shape: shape ?? this.shape,
      assignedEmployees: assignedEmployees ?? this.assignedEmployees,
      labelLetter: labelLetter ?? this.labelLetter,
    );
  }

  // Check if a location is within this geofence
  bool isLocationWithin(double lat, double lng) {
    if (shape == GeofenceShape.circle) {
      return _isWithinCircle(lat, lng);
    } else {
      // For future implementation of polygon geofences
      return false;
    }
  }

  // Calculate if point is within circular geofence
  bool _isWithinCircle(double lat, double lng) {
    final distance = calculateDistance(latitude, longitude, lat, lng);
    return distance <= radius;
  }

  // Calculate distance between two coordinates in meters
  static double calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const R = 6371000; // Earth radius in meters
    final phi1 = lat1 * pi / 180;
    final phi2 = lat2 * pi / 180;
    final deltaPhi = (lat2 - lat1) * pi / 180;
    final deltaLambda = (lon2 - lon1) * pi / 180;

    final a =
        sin(deltaPhi / 2) * sin(deltaPhi / 2) +
        cos(phi1) * cos(phi2) * sin(deltaLambda / 2) * sin(deltaLambda / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return R * c; // Distance in meters
  }

  // Create a Geofence from JSON data
  factory Geofence.fromJson(Map<String, dynamic> json) {
    List<UserModel>? employees;
    final rawEmployees = json['assignedEmployees'];
    if (rawEmployees is List) {
      employees = rawEmployees.map<UserModel>((e) {
        if (e is Map<String, dynamic>) {
          return UserModel.fromJson(e);
        }
        if (e is Map) {
          return UserModel.fromJson(Map<String, dynamic>.from(e));
        }
        final id = e?.toString() ?? '';
        return UserModel(id: id, name: '', email: '', role: 'employee');
      }).toList();
    }

    return Geofence(
      id: json['_id'], // Backend uses _id
      name: json['name'],
      address: json['address'] ?? '',
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      radius: (json['radius'] as num).toDouble(),
      isActive: json['isActive'] ?? true,
      createdBy: json['createdBy'],
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : null,
      shape: _parseShape(json['shape']),
      assignedEmployees: employees,
      labelLetter: json['labelLetter'],
    );
  }

  // Convert Geofence to JSON
  Map<String, dynamic> toJson() {
    return {
      if (id != null) '_id': id, // Only include _id if it exists (for updates)
      'name': name,
      'address': address,
      'latitude': latitude,
      'longitude': longitude,
      'radius': radius,
      'isActive': isActive,
      'createdBy': createdBy,
      'createdAt': createdAt?.toIso8601String(),
      'shape': shape.toString().split('.').last,
      if (assignedEmployees != null)
        'assignedEmployees': assignedEmployees!.map((u) => u.id).toList(),
      if (labelLetter != null) 'labelLetter': labelLetter,
    };
  }

  static GeofenceShape _parseShape(String? shape) {
    if (shape == 'polygon') {
      return GeofenceShape.polygon;
    }
    return GeofenceShape.circle;
  }
}

enum GeofenceShape { circle, polygon }

class UserLocation {
  final double latitude;
  final double longitude;
  final double accuracy;
  final DateTime timestamp;

  UserLocation({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.timestamp,
  });

  LatLng toLatLng() {
    return LatLng(latitude, longitude);
  }

  factory UserLocation.fromLatLng(LatLng latLng) {
    return UserLocation(
      latitude: latLng.latitude,
      longitude: latLng.longitude,
      accuracy: 0.0, // Default accuracy, as LatLng doesn't provide it
      timestamp: DateTime.now(),
    );
  }

  factory UserLocation.fromJson(Map<String, dynamic> json) {
    return UserLocation(
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      accuracy: (json['accuracy'] as num).toDouble(),
      timestamp: DateTime.parse(json['timestamp']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}
