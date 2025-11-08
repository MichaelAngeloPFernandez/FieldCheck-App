import 'dart:convert';
import '../models/geofence_model.dart';
import 'package:latlong2/latlong.dart';
import 'package:field_check/utils/http_util.dart';
import 'package:field_check/services/user_service.dart';

class GeofenceService {
  final String _geofencesPath = '/api/geofences';

  // In-memory cache for geofences
  final List<Geofence> _geofences = [];

  GeofenceService();

  Future<Map<String, String>> _buildHeaders() async {
    final token = await UserService().getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // Fetch geofences from the backend
  Future<List<Geofence>> fetchGeofences() async {
    try {
      final headers = await _buildHeaders();
      final response = await HttpUtil().get(_geofencesPath, headers: headers);
      if (response.statusCode == 200) {
        final List<dynamic> geofenceJson = json.decode(response.body);
        _geofences.clear();
        _geofences.addAll(geofenceJson.map((json) => Geofence.fromJson(json)).toList());
        return List.from(_geofences);
      } else {
        throw Exception('Failed to load geofences: ${response.body}');
      }
    } catch (e) {
      print('Error fetching geofences: $e');
      return [];
    }
  }

  // Get all geofences (from cache, call fetchGeofences first to update cache)
  List<Geofence> getAllGeofences() {
    return List.from(_geofences);
  }

  // Add a new geofence to the backend
  Future<void> addGeofence(Geofence geofence) async {
    try {
      final headers = await _buildHeaders();
      final response = await HttpUtil().post(
        _geofencesPath,
        headers: headers,
        body: geofence.toJson(),
      );
      if (response.statusCode == 201 || response.statusCode == 200) {
        final newGeofence = Geofence.fromJson(json.decode(response.body));
        _geofences.add(newGeofence);
      } else {
        throw Exception('Failed to add geofence: ${response.body}');
      }
    } catch (e) {
      print('Error adding geofence: $e');
      rethrow;
    }
  }

  // Update an existing geofence in the backend
  Future<void> updateGeofence(Geofence updatedGeofence) async {
    try {
      final headers = await _buildHeaders();
      final response = await HttpUtil().put(
        '$_geofencesPath/${updatedGeofence.id}',
        headers: headers,
        body: updatedGeofence.toJson(),
      );
      if (response.statusCode == 200) {
        final index = _geofences.indexWhere((g) => g.id == updatedGeofence.id);
        if (index != -1) {
          _geofences[index] = Geofence.fromJson(json.decode(response.body));
        }
      } else {
        throw Exception('Failed to update geofence: ${response.body}');
      }
    } catch (e) {
      print('Error updating geofence: $e');
      rethrow;
    }
  }

  // Delete a geofence by ID from the backend
  Future<void> deleteGeofence(String id) async {
    try {
      final headers = await _buildHeaders();
      final response = await HttpUtil().delete('$_geofencesPath/$id', headers: headers);
      if (response.statusCode == 200) {
        _geofences.removeWhere((g) => g.id == id);
      } else {
        throw Exception('Failed to delete geofence: ${response.body}');
      }
    } catch (e) {
      print('Error deleting geofence: $e');
      rethrow;
    }
  }

  // Find geofences near a given location
  List<Geofence> findGeofencesNear(LatLng location, double searchRadius) {
    return _geofences.where((geofence) {
      final geofenceLocation = LatLng(geofence.latitude, geofence.longitude);
      final distance = const Distance().as(LengthUnit.Meter, location, geofenceLocation);
      return distance <= searchRadius + geofence.radius;
    }).toList();
  }

  // Find the nearest active geofence to a given lat/lng from provided list
  Geofence? findNearestGeofence(double lat, double lng, List<Geofence> geofences) {
    if (geofences.isEmpty) return null;
    Geofence? nearest;
    double minDistance = double.infinity;
    final current = LatLng(lat, lng);
    for (final g in geofences) {
      if (!g.isActive) continue;
      final d = const Distance().as(LengthUnit.Meter, current, LatLng(g.latitude, g.longitude));
      if (d < minDistance) {
        minDistance = d;
        nearest = g;
      }
    }
    return nearest;
  }

  // Check if a location is inside any active geofence
  bool isLocationInsideAnyActiveGeofence(LatLng location) {
    return _geofences.any((geofence) {
      if (!geofence.isActive) return false;
      final geofenceLocation = LatLng(geofence.latitude, geofence.longitude);
      final distance = const Distance().as(LengthUnit.Meter, location, geofenceLocation);
      return distance <= geofence.radius;
    });
  }
}