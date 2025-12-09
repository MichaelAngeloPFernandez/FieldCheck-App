import 'dart:convert';
import 'package:field_check/utils/http_util.dart';
import 'package:field_check/config/api_config.dart';
import 'package:field_check/models/user_model.dart';
import 'package:flutter/foundation.dart';

class EmployeeTrackingService {
  static final EmployeeTrackingService _instance =
      EmployeeTrackingService._internal();

  factory EmployeeTrackingService() {
    return _instance;
  }

  EmployeeTrackingService._internal();

  final String _basePath = '${ApiConfig.baseUrl}/api/employee-tracking';

  /// Get nearby employees within radius
  Future<List<UserModel>> getNearbyEmployees({
    required double latitude,
    required double longitude,
    double radiusMeters = 5000,
  }) async {
    try {
      final response = await HttpUtil().get(
        '$_basePath/nearby?latitude=$latitude&longitude=$longitude&radius=$radiusMeters',
        headers: await _headers(),
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to fetch nearby employees: ${response.body}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['employees'] is List) {
        final employees = (data['employees'] as List)
            .map((e) => UserModel.fromJson(e as Map<String, dynamic>))
            .toList();
        return employees;
      }
      return [];
    } catch (e) {
      debugPrint('❌ Error fetching nearby employees: $e');
      return [];
    }
  }

  /// Get employee workload
  Future<EmployeeWorkload?> getEmployeeWorkload(String employeeId) async {
    try {
      final response = await HttpUtil().get(
        '$_basePath/workload/$employeeId',
        headers: await _headers(),
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to fetch workload: ${response.body}');
      }

      return EmployeeWorkload.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    } catch (e) {
      debugPrint('❌ Error fetching workload: $e');
      return null;
    }
  }

  /// Get employee availability
  Future<EmployeeAvailability?> getEmployeeAvailability(
    String employeeId,
  ) async {
    try {
      final response = await HttpUtil().get(
        '$_basePath/availability/$employeeId',
        headers: await _headers(),
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to fetch availability: ${response.body}');
      }

      return EmployeeAvailability.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    } catch (e) {
      debugPrint('❌ Error fetching availability: $e');
      return null;
    }
  }

  /// Update employee location
  Future<void> updateEmployeeLocation({
    required double latitude,
    required double longitude,
    double? accuracy,
  }) async {
    try {
      final response = await HttpUtil().post(
        '$_basePath/location',
        body: {
          'latitude': latitude,
          'longitude': longitude,
          'accuracy': accuracy ?? 0,
        },
        headers: await _headers(),
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to update location: ${response.body}');
      }
      debugPrint('📍 Location updated successfully');
    } catch (e) {
      debugPrint('❌ Error updating location: $e');
    }
  }

  /// Get employee statistics
  Future<EmployeeStats?> getEmployeeStats(String employeeId) async {
    try {
      final response = await HttpUtil().get(
        '$_basePath/stats/$employeeId',
        headers: await _headers(),
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to fetch stats: ${response.body}');
      }

      return EmployeeStats.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    } catch (e) {
      debugPrint('❌ Error fetching stats: $e');
      return null;
    }
  }

  /// Get overdue tasks for employee
  Future<List<OverdueTask>> getOverdueTasks(String employeeId) async {
    try {
      final response = await HttpUtil().get(
        '$_basePath/overdue/$employeeId',
        headers: await _headers(),
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to fetch overdue tasks: ${response.body}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['overdueTasks'] is List) {
        return (data['overdueTasks'] as List)
            .map((e) => OverdueTask.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (e) {
      debugPrint('❌ Error fetching overdue tasks: $e');
      return [];
    }
  }

  Future<Map<String, String>> _headers() async {
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${await _getToken()}',
    };
  }

  Future<String> _getToken() async {
    // Implementation would fetch from secure storage
    return '';
  }
}

class EmployeeWorkload {
  final String employeeId;
  final String employeeName;
  final int activeTaskCount;
  final double workloadWeight;
  final int totalTasks;
  final int overdueTasks;
  final Map<String, int> tasksByDifficulty;

  EmployeeWorkload({
    required this.employeeId,
    required this.employeeName,
    required this.activeTaskCount,
    required this.workloadWeight,
    required this.totalTasks,
    required this.overdueTasks,
    required this.tasksByDifficulty,
  });

  factory EmployeeWorkload.fromJson(Map<String, dynamic> json) {
    return EmployeeWorkload(
      employeeId: json['employee']['id'] ?? '',
      employeeName: json['employee']['name'] ?? '',
      activeTaskCount: json['employee']['activeTaskCount'] ?? 0,
      workloadWeight: (json['employee']['workloadWeight'] ?? 0).toDouble(),
      totalTasks: json['tasks']['total'] ?? 0,
      overdueTasks: json['tasks']['overdue'] ?? 0,
      tasksByDifficulty: Map<String, int>.from(
        json['tasks']['byDifficulty'] ?? {},
      ),
    );
  }
}

class EmployeeAvailability {
  final String employeeId;
  final String employeeName;
  final String status; // 'available', 'busy', 'overloaded', 'offline', 'free'
  final bool isOnline;
  final int activeTaskCount;
  final double workloadWeight;

  EmployeeAvailability({
    required this.employeeId,
    required this.employeeName,
    required this.status,
    required this.isOnline,
    required this.activeTaskCount,
    required this.workloadWeight,
  });

  factory EmployeeAvailability.fromJson(Map<String, dynamic> json) {
    return EmployeeAvailability(
      employeeId: json['employee']['id'] ?? '',
      employeeName: json['employee']['name'] ?? '',
      status: json['employee']['status'] ?? 'offline',
      isOnline: json['employee']['isOnline'] ?? false,
      activeTaskCount: json['employee']['activeTaskCount'] ?? 0,
      workloadWeight: (json['employee']['workloadWeight'] ?? 0).toDouble(),
    );
  }
}

class EmployeeStats {
  final String employeeId;
  final String employeeName;
  final String email;
  final String role;
  final int totalTasks;
  final int completedTasks;
  final int activeTasks;
  final int overdueTasks;
  final double completionRate;
  final double workloadWeight;
  final int activeTaskCount;
  final bool isOnline;
  final DateTime? lastLocationUpdate;

  EmployeeStats({
    required this.employeeId,
    required this.employeeName,
    required this.email,
    required this.role,
    required this.totalTasks,
    required this.completedTasks,
    required this.activeTasks,
    required this.overdueTasks,
    required this.completionRate,
    required this.workloadWeight,
    required this.activeTaskCount,
    required this.isOnline,
    this.lastLocationUpdate,
  });

  factory EmployeeStats.fromJson(Map<String, dynamic> json) {
    return EmployeeStats(
      employeeId: json['employee']['id'] ?? '',
      employeeName: json['employee']['name'] ?? '',
      email: json['employee']['email'] ?? '',
      role: json['employee']['role'] ?? '',
      totalTasks: json['statistics']['totalTasks'] ?? 0,
      completedTasks: json['statistics']['completedTasks'] ?? 0,
      activeTasks: json['statistics']['activeTasks'] ?? 0,
      overdueTasks: json['statistics']['overdueTasks'] ?? 0,
      completionRate: (json['statistics']['completionRate'] ?? 0).toDouble(),
      workloadWeight: (json['statistics']['workloadWeight'] ?? 0).toDouble(),
      activeTaskCount: json['statistics']['activeTaskCount'] ?? 0,
      isOnline: json['statistics']['isOnline'] ?? false,
      lastLocationUpdate: json['statistics']['lastLocationUpdate'] != null
          ? DateTime.tryParse(
              json['statistics']['lastLocationUpdate'].toString(),
            )
          : null,
    );
  }
}

class OverdueTask {
  final String taskId;
  final String title;
  final String description;
  final String difficulty;
  final DateTime dueDate;
  final int hoursOverdue;
  final String status;

  OverdueTask({
    required this.taskId,
    required this.title,
    required this.description,
    required this.difficulty,
    required this.dueDate,
    required this.hoursOverdue,
    required this.status,
  });

  factory OverdueTask.fromJson(Map<String, dynamic> json) {
    return OverdueTask(
      taskId: json['id'] ?? '',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      difficulty: json['difficulty'] ?? 'medium',
      dueDate: DateTime.tryParse(json['dueDate'].toString()) ?? DateTime.now(),
      hoursOverdue: json['hoursOverdue'] ?? 0,
      status: json['status'] ?? 'pending',
    );
  }
}
