import 'package:geolocator/geolocator.dart';
import 'package:field_check/services/user_service.dart';
import 'package:field_check/models/user_model.dart';
import 'package:flutter/foundation.dart';

enum EmployeeAvailability { available, busy, overloaded, offline }

class NearbyEmployee {
  final UserModel user;
  final double distanceMeters;
  final EmployeeAvailability availability;
  final int activeTaskCount;
  final double workloadWeight;
  final bool isOnline;
  final Position? lastKnownLocation;

  NearbyEmployee({
    required this.user,
    required this.distanceMeters,
    required this.availability,
    required this.activeTaskCount,
    required this.workloadWeight,
    required this.isOnline,
    this.lastKnownLocation,
  });
}

class NearbyEmployeesService {
  static final NearbyEmployeesService _instance =
      NearbyEmployeesService._internal();

  factory NearbyEmployeesService() {
    return _instance;
  }

  NearbyEmployeesService._internal();

  final UserService _userService = UserService();

  /// Find nearby employees within a radius
  Future<List<NearbyEmployee>> findNearbyEmployees({
    required double latitude,
    required double longitude,
    required double radiusMeters,
    bool onlyAvailable = false,
    int maxResults = 10,
  }) async {
    try {
      // Get employees from backend
      final employees = await _userService.fetchEmployees();
      final nearbyList = <NearbyEmployee>[];

      for (final employee in employees) {
        // Skip if no location data
        if (employee.lastLatitude == null || employee.lastLongitude == null) {
          continue;
        }

        // Calculate distance
        final distance = Geolocator.distanceBetween(
          latitude,
          longitude,
          employee.lastLatitude!,
          employee.lastLongitude!,
        );

        // Skip if outside radius
        if (distance > radiusMeters) {
          continue;
        }

        // Determine availability
        final availability = _determineAvailability(
          employee.activeTaskCount ?? 0,
          employee.workloadWeight ?? 0.0,
        );

        // Skip if filtering for available only
        if (onlyAvailable && availability != EmployeeAvailability.available) {
          continue;
        }

        nearbyList.add(
          NearbyEmployee(
            user: employee,
            distanceMeters: distance,
            availability: availability,
            activeTaskCount: employee.activeTaskCount ?? 0,
            workloadWeight: employee.workloadWeight ?? 0.0,
            isOnline: employee.isOnline ?? false,
            lastKnownLocation: Position(
              latitude: employee.lastLatitude!,
              longitude: employee.lastLongitude!,
              timestamp: DateTime.now(),
              accuracy: 0,
              altitude: 0,
              heading: 0,
              speed: 0,
              speedAccuracy: 0,
              altitudeAccuracy: 0,
              headingAccuracy: 0,
            ),
          ),
        );
      }

      // Sort by distance
      nearbyList.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));

      // Return top N results
      return nearbyList.take(maxResults).toList();
    } catch (e) {
      debugPrint('❌ Error finding nearby employees: $e');
      return [];
    }
  }

  /// Get employees sorted by workload (ascending - least busy first)
  Future<List<NearbyEmployee>> getEmployeesByWorkload({
    required double latitude,
    required double longitude,
    required double radiusMeters,
    int maxResults = 10,
  }) async {
    try {
      final nearby = await findNearbyEmployees(
        latitude: latitude,
        longitude: longitude,
        radiusMeters: radiusMeters,
        maxResults: maxResults * 2, // Get more to sort
      );

      // Sort by workload weight (ascending)
      nearby.sort((a, b) => a.workloadWeight.compareTo(b.workloadWeight));

      return nearby.take(maxResults).toList();
    } catch (e) {
      debugPrint('❌ Error getting employees by workload: $e');
      return [];
    }
  }

  /// Get availability statistics for a region
  Future<AvailabilityStats> getAvailabilityStats({
    required double latitude,
    required double longitude,
    required double radiusMeters,
  }) async {
    try {
      final nearby = await findNearbyEmployees(
        latitude: latitude,
        longitude: longitude,
        radiusMeters: radiusMeters,
        maxResults: 1000,
      );

      int available = 0;
      int busy = 0;
      int overloaded = 0;
      int offline = 0;
      double avgDistance = 0;

      for (final emp in nearby) {
        switch (emp.availability) {
          case EmployeeAvailability.available:
            available++;
            break;
          case EmployeeAvailability.busy:
            busy++;
            break;
          case EmployeeAvailability.overloaded:
            overloaded++;
            break;
          case EmployeeAvailability.offline:
            offline++;
            break;
        }
        avgDistance += emp.distanceMeters;
      }

      if (nearby.isNotEmpty) {
        avgDistance /= nearby.length;
      }

      return AvailabilityStats(
        totalEmployees: nearby.length,
        availableCount: available,
        busyCount: busy,
        overloadedCount: overloaded,
        offlineCount: offline,
        averageDistance: avgDistance,
      );
    } catch (e) {
      debugPrint('❌ Error getting availability stats: $e');
      return AvailabilityStats.empty();
    }
  }

  EmployeeAvailability _determineAvailability(
    int activeTaskCount,
    double workloadWeight,
  ) {
    if (activeTaskCount == 0) {
      return EmployeeAvailability.available;
    } else if (workloadWeight > 10.0) {
      return EmployeeAvailability.overloaded;
    } else if (activeTaskCount > 5) {
      return EmployeeAvailability.busy;
    } else {
      return EmployeeAvailability.available;
    }
  }
}

class AvailabilityStats {
  final int totalEmployees;
  final int availableCount;
  final int busyCount;
  final int overloadedCount;
  final int offlineCount;
  final double averageDistance;

  AvailabilityStats({
    required this.totalEmployees,
    required this.availableCount,
    required this.busyCount,
    required this.overloadedCount,
    required this.offlineCount,
    required this.averageDistance,
  });

  factory AvailabilityStats.empty() {
    return AvailabilityStats(
      totalEmployees: 0,
      availableCount: 0,
      busyCount: 0,
      overloadedCount: 0,
      offlineCount: 0,
      averageDistance: 0,
    );
  }
}
