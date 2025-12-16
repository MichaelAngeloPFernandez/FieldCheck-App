import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:field_check/config/api_config.dart';
import 'package:field_check/services/user_service.dart';

class AttendanceService {
  final UserService _userService = UserService();

  Future<AttendanceStatus> getCurrentAttendanceStatus() async {
    try {
      final token = await _userService.getToken();
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/attendance/status'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return AttendanceStatus.fromJson(data);
      } else {
        throw Exception('Failed to load attendance status');
      }
    } catch (e) {
      throw Exception('Error getting attendance status: $e');
    }
  }

  Future<void> submitAttendance(AttendanceData attendanceData) async {
    try {
      final token = await _userService.getToken();
      final response = await http.post(
        Uri.parse(
          '${ApiConfig.baseUrl}/api/attendance/${attendanceData.isCheckedIn ? 'checkin' : 'checkout'}',
        ),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'latitude': attendanceData.latitude,
          'longitude': attendanceData.longitude,
          'geofenceId': attendanceData.geofenceId,
          'timestamp': attendanceData.timestamp.toIso8601String(),
        }),
      );

      // Treat any 2xx as success (check-in returns 201, checkout 200)
      if (response.statusCode < 200 || response.statusCode >= 300) {
        String errorMsg = 'Failed to submit attendance';
        try {
          final body = jsonDecode(response.body);
          errorMsg = body['message'] ?? errorMsg;
        } catch (_) {
          // keep default errorMsg if body isn't JSON
        }
        throw Exception(errorMsg);
      }
    } catch (e) {
      throw Exception('Error submitting attendance: $e');
    }
  }

  Future<List<AttendanceRecord>> getAttendanceHistory({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final token = await _userService.getToken();
      final queryParams = <String, String>{};

      if (startDate != null) {
        queryParams['startDate'] = startDate.toIso8601String();
      }
      if (endDate != null) {
        queryParams['endDate'] = endDate.toIso8601String();
      }

      final uri = Uri.parse(
        '${ApiConfig.baseUrl}/api/attendance/history',
      ).replace(queryParameters: queryParams.isNotEmpty ? queryParams : null);

      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> records = data['records'] ?? [];
        return records
            .map((record) => AttendanceRecord.fromJson(record))
            .toList();
      } else {
        throw Exception('Failed to load attendance history');
      }
    } catch (e) {
      throw Exception('Error getting attendance history: $e');
    }
  }

  Future<void> deleteMyAttendanceRecord(String id) async {
    try {
      final token = await _userService.getToken();
      final response = await http.delete(
        Uri.parse('${ApiConfig.baseUrl}/api/attendance/history/$id'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Failed to delete attendance record');
      }
    } catch (e) {
      throw Exception('Error deleting attendance record: $e');
    }
  }

  Future<int> deleteMyAttendanceHistoryForMonth(int year, int month) async {
    try {
      final token = await _userService.getToken();
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/attendance/history')
          .replace(
            queryParameters: {
              'year': year.toString(),
              'month': month.toString(),
            },
          );

      final response = await http.delete(
        uri,
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        try {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          return (data['deletedCount'] as int?) ?? 0;
        } catch (_) {
          return 0;
        }
      } else if (response.statusCode == 204) {
        return 0;
      } else {
        throw Exception('Failed to delete attendance history for month');
      }
    } catch (e) {
      throw Exception('Error deleting attendance history for month: $e');
    }
  }

  Future<List<AttendanceRecord>> getAttendanceRecords({
    DateTime? date,
    String? locationId,
    String? status,
    String? employeeId,
  }) async {
    try {
      final token = await _userService.getToken();
      final queryParams = <String, String>{};

      if (date != null) {
        queryParams['startDate'] = date.toIso8601String();
        queryParams['endDate'] = date
            .add(const Duration(days: 1))
            .toIso8601String();
      }
      if (locationId != null) {
        queryParams['geofenceId'] = locationId;
      }
      if (status != null) {
        queryParams['status'] = status;
      }
      if (employeeId != null) {
        queryParams['employeeId'] = employeeId;
      }

      final uri = Uri.parse(
        '${ApiConfig.baseUrl}/api/attendance',
      ).replace(queryParameters: queryParams.isNotEmpty ? queryParams : null);

      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> records = jsonDecode(response.body);
        return records
            .map((record) => AttendanceRecord.fromJson(record))
            .toList();
      } else {
        throw Exception(
          'Failed to load attendance records: ${response.statusCode}',
        );
      }
    } catch (e) {
      throw Exception('Error getting attendance records: $e');
    }
  }
}

class AttendanceStatus {
  final bool isCheckedIn;
  final String? lastCheckTime;
  final String? lastGeofenceName;
  final DateTime? lastCheckTimestamp;

  AttendanceStatus({
    required this.isCheckedIn,
    this.lastCheckTime,
    this.lastGeofenceName,
    this.lastCheckTimestamp,
  });

  factory AttendanceStatus.fromJson(Map<String, dynamic> json) {
    return AttendanceStatus(
      isCheckedIn: json['isCheckedIn'] ?? false,
      lastCheckTime: json['lastCheckTime'],
      lastGeofenceName: json['lastGeofenceName'],
      lastCheckTimestamp: json['lastCheckTimestamp'] != null
          ? DateTime.parse(json['lastCheckTimestamp'])
          : null,
    );
  }
}

class AttendanceData {
  final bool isCheckedIn;
  final DateTime timestamp;
  final double? latitude;
  final double? longitude;
  final String? geofenceId;
  final String? geofenceName;

  AttendanceData({
    required this.isCheckedIn,
    required this.timestamp,
    this.latitude,
    this.longitude,
    this.geofenceId,
    this.geofenceName,
  });
}

class AttendanceRecord {
  final String id;
  final bool isCheckIn;
  final DateTime timestamp;
  final double? latitude;
  final double? longitude;
  final String? geofenceId;
  final String? geofenceName;
  final String userId;
  final String? employeeName;
  final String? employeeEmail;
  final bool isVoid;
  final bool autoCheckout;
  final String? voidReason;

  AttendanceRecord({
    required this.id,
    required this.isCheckIn,
    required this.timestamp,
    this.latitude,
    this.longitude,
    this.geofenceId,
    this.geofenceName,
    required this.userId,
    this.employeeName,
    this.employeeEmail,
    this.isVoid = false,
    this.autoCheckout = false,
    this.voidReason,
  });

  factory AttendanceRecord.fromJson(Map<String, dynamic> json) {
    // Handle both direct attendance records and report objects
    final attendance = json['attendance'] as Map<String, dynamic>? ?? json;
    final employee = json['employee'] as Map<String, dynamic>?;
    final geofence = json['geofence'] as Map<String, dynamic>?;

    // Determine if it's check-in or check-out
    bool isCheckIn;
    final hasCheckOut = attendance['checkOut'] != null;

    if (hasCheckOut) {
      // If a checkout timestamp exists, the record should be treated as
      // a completed (checked-out) attendance entry regardless of status.
      isCheckIn = false;
    } else if (attendance['status'] != null) {
      isCheckIn = (attendance['status'] as String).toLowerCase() == 'in';
    } else {
      final content = json['content'] as String? ?? '';
      isCheckIn = content.toLowerCase().contains('checked in');
    }

    String? timestampStr;

    if (hasCheckOut && attendance['checkOut'] != null) {
      timestampStr = attendance['checkOut']?.toString();
    } else if (attendance['checkIn'] != null) {
      timestampStr = attendance['checkIn']?.toString();
    } else {
      timestampStr = (json['submittedAt'] ?? json['timestamp'])?.toString();
    }

    final DateTime parsedTimestamp = timestampStr != null
        ? DateTime.parse(timestampStr)
        : DateTime.now();

    return AttendanceRecord(
      id: json['_id'] ?? json['id'] ?? '',
      isCheckIn: isCheckIn,
      timestamp: parsedTimestamp,
      latitude:
          (attendance['location']?['coordinates']?[1] as num?)?.toDouble() ??
          (attendance['latitude'] as num?)?.toDouble(),
      longitude:
          (attendance['location']?['coordinates']?[0] as num?)?.toDouble() ??
          (attendance['longitude'] as num?)?.toDouble(),
      geofenceId: geofence?['_id'] ?? json['geofenceId'],
      geofenceName: geofence?['name'] ?? json['geofenceName'],
      userId: employee?['_id'] ?? json['userId'] ?? '',
      employeeName: employee?['name'] ?? json['employeeName'],
      employeeEmail: employee?['email'] ?? json['employeeEmail'],
      isVoid:
          (attendance['isVoid'] as bool?) ?? (json['isVoid'] as bool?) ?? false,
      autoCheckout:
          (attendance['autoCheckout'] as bool?) ??
          (json['autoCheckout'] as bool?) ??
          false,
      voidReason:
          attendance['voidReason'] as String? ?? json['voidReason'] as String?,
    );
  }
}

/// Location validation helper for geofence and mock location detection
class LocationValidator {
  static final UserService _userService = UserService();

  /// Validates location for attendance check-in/out
  /// Returns: {valid: bool, reason: String, isMockLocation: bool}
  static Future<Map<String, dynamic>> validateLocation({
    required double latitude,
    required double longitude,
    required double? accuracy,
    required String? geofenceId,
  }) async {
    try {
      // Check 1: Accuracy validation (mock location detection)
      // Real GPS typically has accuracy < 30m, mocked locations often > 100m
      if (accuracy != null && accuracy > 100.0) {
        return {
          'valid': false,
          'reason':
              'Location accuracy too low (${accuracy.toStringAsFixed(1)}m). Please enable high-accuracy GPS.',
          'isMockLocation': true,
        };
      }

      // Check 2: Impossible speed detection
      // If location changed by > 500km in < 1 minute, it's likely spoofed
      final token = await _userService.getToken();
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/attendance/last-location'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final lastLat = (data['latitude'] as num?)?.toDouble();
        final lastLng = (data['longitude'] as num?)?.toDouble();
        final lastTime = data['timestamp'] != null
            ? DateTime.parse(data['timestamp'])
            : null;

        if (lastLat != null && lastLng != null && lastTime != null) {
          final distance = _calculateDistance(
            lastLat,
            lastLng,
            latitude,
            longitude,
          );
          final timeDiff = DateTime.now().difference(lastTime).inSeconds;

          // More than 500km in less than 1 minute = impossible
          if (distance > 500 && timeDiff < 60) {
            return {
              'valid': false,
              'reason':
                  'Impossible location change detected. Please check your GPS.',
              'isMockLocation': true,
            };
          }
        }
      }

      // Check 3: Geofence validation
      if (geofenceId != null && geofenceId.isNotEmpty) {
        final geofenceResponse = await http.get(
          Uri.parse('${ApiConfig.baseUrl}/api/geofences/$geofenceId'),
          headers: {
            'Content-Type': 'application/json',
            if (token != null) 'Authorization': 'Bearer $token',
          },
        );

        if (geofenceResponse.statusCode == 200) {
          final geofence = jsonDecode(geofenceResponse.body);
          final centerLat = (geofence['latitude'] as num?)?.toDouble();
          final centerLng = (geofence['longitude'] as num?)?.toDouble();
          final radius = (geofence['radius'] as num?)?.toDouble() ?? 100.0;

          if (centerLat != null && centerLng != null) {
            final distance = _calculateDistance(
              centerLat,
              centerLng,
              latitude,
              longitude,
            );

            if (distance > radius) {
              return {
                'valid': false,
                'reason':
                    'You are ${distance.toStringAsFixed(0)}m outside the geofence (${radius.toStringAsFixed(0)}m radius).',
                'isMockLocation': false,
              };
            }
          }
        }
      }

      // All checks passed
      return {
        'valid': true,
        'reason': 'Location verified',
        'isMockLocation': false,
      };
    } catch (e) {
      // If validation fails, allow but warn
      return {
        'valid': true,
        'reason': 'Could not verify location: $e',
        'isMockLocation': false,
      };
    }
  }

  /// Calculate distance between two coordinates using Haversine formula
  /// Returns distance in kilometers
  static double _calculateDistance(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const earthRadiusKm = 6371.0;

    final dLat = _toRad(lat2 - lat1);
    final dLng = _toRad(lng2 - lng1);

    final a =
        (math.sin(dLat / 2) * math.sin(dLat / 2)) +
        (math.cos(_toRad(lat1)) *
            math.cos(_toRad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2));

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusKm * c;
  }

  static double _toRad(double deg) => deg * (math.pi / 180.0);
}
