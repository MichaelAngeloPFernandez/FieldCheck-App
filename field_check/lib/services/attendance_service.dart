import 'dart:convert';
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
        Uri.parse('${ApiConfig.baseUrl}/api/attendance/${attendanceData.isCheckedIn ? 'checkin' : 'checkout'}'),
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

      final uri = Uri.parse('${ApiConfig.baseUrl}/api/attendance/history').replace(
        queryParameters: queryParams.isNotEmpty ? queryParams : null,
      );

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
        return records.map((record) => AttendanceRecord.fromJson(record)).toList();
      } else {
        throw Exception('Failed to load attendance history');
      }
    } catch (e) {
      throw Exception('Error getting attendance history: $e');
    }
  }

  Future<List<AttendanceRecord>> getAttendanceRecords({
    DateTime? date,
    String? locationId,
    String? status,
  }) async {
    try {
      final token = await _userService.getToken();
      final queryParams = <String, String>{};
      
      if (date != null) {
        queryParams['date'] = date.toIso8601String();
      }
      if (locationId != null) {
        queryParams['geofenceId'] = locationId;
      }
      if (status != null) {
        queryParams['status'] = status;
      }

      final uri = Uri.parse('${ApiConfig.baseUrl}/api/attendance').replace(
        queryParameters: queryParams.isNotEmpty ? queryParams : null,
      );

      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> records = jsonDecode(response.body);
        return records.map((record) => AttendanceRecord.fromJson(record)).toList();
      } else {
        throw Exception('Failed to load attendance records');
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

  AttendanceRecord({
    required this.id,
    required this.isCheckIn,
    required this.timestamp,
    this.latitude,
    this.longitude,
    this.geofenceId,
    this.geofenceName,
    required this.userId,
  });

  factory AttendanceRecord.fromJson(Map<String, dynamic> json) {
    return AttendanceRecord(
      id: json['id'],
      isCheckIn: json['isCheckIn'],
      timestamp: DateTime.parse(json['timestamp']),
      latitude: json['latitude']?.toDouble(),
      longitude: json['longitude']?.toDouble(),
      geofenceId: json['geofenceId'],
      geofenceName: json['geofenceName'],
      userId: json['userId'],
    );
  }
}