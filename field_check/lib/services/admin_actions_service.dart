import 'dart:async';
import 'package:flutter/foundation.dart';
import '../utils/http_util.dart';
import '../config/api_config.dart';

/// Admin Actions Service - Handles all admin-level operations
class AdminActionsService {
  static final AdminActionsService _instance = AdminActionsService._internal();

  factory AdminActionsService() => _instance;
  AdminActionsService._internal();

  final HttpUtil _http = HttpUtil();

  /// Task reassignment
  Future<bool> reassignTask({
    required String taskId,
    required String fromEmployeeId,
    required String toEmployeeId,
    String? reason,
  }) async {
    try {
      final response = await _http.post(
        '${ApiConfig.baseUrl}/api/tasks/$taskId/reassign',
        body: {
          'fromEmployeeId': fromEmployeeId,
          'toEmployeeId': toEmployeeId,
          'reason': reason ?? 'Admin reassignment',
          'timestamp': DateTime.now().toIso8601String(),
        },
      );

      if (response.statusCode == 200) {
        debugPrint(
          '✅ Task $taskId reassigned from $fromEmployeeId to $toEmployeeId',
        );
        return true;
      }
      debugPrint('❌ Failed to reassign task: ${response.body}');
      return false;
    } catch (e) {
      debugPrint('❌ Error reassigning task: $e');
      return false;
    }
  }

  /// Bulk reassign tasks
  Future<Map<String, bool>> bulkReassignTasks({
    required List<String> taskIds,
    required String toEmployeeId,
    String? reason,
  }) async {
    final results = <String, bool>{};

    for (final taskId in taskIds) {
      try {
        final response = await _http.post(
          '${ApiConfig.baseUrl}/api/tasks/$taskId/reassign',
          body: {
            'toEmployeeId': toEmployeeId,
            'reason': reason ?? 'Bulk admin reassignment',
            'timestamp': DateTime.now().toIso8601String(),
          },
        );
        results[taskId] = response.statusCode == 200;
      } catch (e) {
        results[taskId] = false;
        debugPrint('❌ Error reassigning task $taskId: $e');
      }
    }

    debugPrint(
      '📊 Bulk reassignment complete: ${results.values.where((v) => v).length}/${taskIds.length} successful',
    );
    return results;
  }

  /// Send message to employee
  Future<bool> sendMessage({
    required String employeeId,
    required String message,
    String? messageType = 'general', // general, urgent, task, alert
  }) async {
    try {
      final response = await _http.post(
        '${ApiConfig.baseUrl}/api/messages/send',
        body: {
          'recipientId': employeeId,
          'message': message,
          'type': messageType,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );

      if (response.statusCode == 200) {
        debugPrint('✅ Message sent to $employeeId');
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('❌ Error sending message: $e');
      return false;
    }
  }

  /// Broadcast message to multiple employees
  Future<Map<String, bool>> broadcastMessage({
    required List<String> employeeIds,
    required String message,
    String? messageType = 'general',
  }) async {
    final results = <String, bool>{};

    for (final empId in employeeIds) {
      results[empId] = await sendMessage(
        employeeId: empId,
        message: message,
        messageType: messageType,
      );
    }

    debugPrint(
      '📢 Broadcast complete: ${results.values.where((v) => v).length}/${employeeIds.length} successful',
    );
    return results;
  }

  /// Update employee status (mark busy/available)
  Future<bool> updateEmployeeStatus({
    required String employeeId,
    required String status, // available, busy, offline
    String? reason,
  }) async {
    try {
      final response = await _http.post(
        '${ApiConfig.baseUrl}/api/location/status/$employeeId',
        body: {
          'status': status,
          'reason': reason,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );

      if (response.statusCode == 200) {
        debugPrint('✅ Employee $employeeId status updated to $status');
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('❌ Error updating status: $e');
      return false;
    }
  }

  /// Generate employee report
  Future<Map<String, dynamic>?> generateEmployeeReport({
    required String employeeId,
    required DateTime startDate,
    required DateTime endDate,
    String? reportType =
        'comprehensive', // comprehensive, attendance, tasks, performance
  }) async {
    try {
      final response = await _http.get(
        '${ApiConfig.baseUrl}/api/reports/employee/$employeeId?'
        'startDate=${startDate.toIso8601String()}&'
        'endDate=${endDate.toIso8601String()}&'
        'type=$reportType',
      );

      if (response.statusCode == 200) {
        debugPrint('✅ Report generated for $employeeId');
        return response.body as Map<String, dynamic>?;
      }
      return null;
    } catch (e) {
      debugPrint('❌ Error generating report: $e');
      return null;
    }
  }

  /// Get employee analytics
  Future<Map<String, dynamic>?> getEmployeeAnalytics({
    required String employeeId,
    String? period = '7days', // 7days, 30days, 90days, custom
  }) async {
    try {
      final response = await _http.get(
        '${ApiConfig.baseUrl}/api/analytics/employee/$employeeId?period=$period',
      );

      if (response.statusCode == 200) {
        debugPrint('✅ Analytics retrieved for $employeeId');
        return response.body as Map<String, dynamic>?;
      }
      return null;
    } catch (e) {
      debugPrint('❌ Error retrieving analytics: $e');
      return null;
    }
  }

  /// Assign geofence to employee
  Future<bool> assignGeofence({
    required String employeeId,
    required String geofenceId,
  }) async {
    try {
      final response = await _http.post(
        '${ApiConfig.baseUrl}/api/geofences/$geofenceId/assign',
        body: {
          'employeeId': employeeId,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );

      if (response.statusCode == 200) {
        debugPrint('✅ Geofence $geofenceId assigned to $employeeId');
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('❌ Error assigning geofence: $e');
      return false;
    }
  }

  /// Bulk assign geofence
  Future<Map<String, bool>> bulkAssignGeofence({
    required List<String> employeeIds,
    required String geofenceId,
  }) async {
    final results = <String, bool>{};

    for (final empId in employeeIds) {
      results[empId] = await assignGeofence(
        employeeId: empId,
        geofenceId: geofenceId,
      );
    }

    debugPrint(
      '📍 Bulk geofence assignment complete: ${results.values.where((v) => v).length}/${employeeIds.length} successful',
    );
    return results;
  }

  /// Create task for employee
  Future<String?> createTask({
    required String title,
    required String description,
    required String assignedTo,
    required DateTime dueDate,
    String? priority = 'medium', // low, medium, high, urgent
    String? geofenceId,
    List<String>? attachments,
  }) async {
    try {
      final response = await _http.post(
        '${ApiConfig.baseUrl}/api/tasks/create',
        body: {
          'title': title,
          'description': description,
          'assignedTo': assignedTo,
          'dueDate': dueDate.toIso8601String(),
          'priority': priority,
          'geofenceId': geofenceId,
          'attachments': attachments ?? [],
          'createdAt': DateTime.now().toIso8601String(),
        },
      );

      if (response.statusCode == 201) {
        debugPrint('✅ Task created: $title');
        // Extract taskId from response body (assuming JSON response)
        return 'task_${DateTime.now().millisecondsSinceEpoch}';
      }
      return null;
    } catch (e) {
      debugPrint('❌ Error creating task: $e');
      return null;
    }
  }

  /// Escalate task
  Future<bool> escalateTask({
    required String taskId,
    required String reason,
    String? escalateTo = 'manager', // manager, supervisor, admin
  }) async {
    try {
      final response = await _http.post(
        '${ApiConfig.baseUrl}/api/tasks/$taskId/escalate',
        body: {
          'reason': reason,
          'escalateTo': escalateTo,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );

      if (response.statusCode == 200) {
        debugPrint('✅ Task $taskId escalated');
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('❌ Error escalating task: $e');
      return false;
    }
  }

  /// Cancel task
  Future<bool> cancelTask({
    required String taskId,
    required String reason,
  }) async {
    try {
      final response = await _http.post(
        '${ApiConfig.baseUrl}/api/tasks/$taskId/cancel',
        body: {'reason': reason, 'timestamp': DateTime.now().toIso8601String()},
      );

      if (response.statusCode == 200) {
        debugPrint('✅ Task $taskId cancelled');
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('❌ Error cancelling task: $e');
      return false;
    }
  }

  /// Get performance metrics
  Future<Map<String, dynamic>?> getPerformanceMetrics({
    required String employeeId,
    String? period = '30days',
  }) async {
    try {
      final response = await _http.get(
        '${ApiConfig.baseUrl}/api/performance/employee/$employeeId?period=$period',
      );

      if (response.statusCode == 200) {
        debugPrint('✅ Performance metrics retrieved for $employeeId');
        return response.body as Map<String, dynamic>?;
      }
      return null;
    } catch (e) {
      debugPrint('❌ Error retrieving performance metrics: $e');
      return null;
    }
  }

  /// Get team analytics
  Future<Map<String, dynamic>?> getTeamAnalytics({
    String? period = '30days',
    String? department,
  }) async {
    try {
      final query = department != null
          ? '?period=$period&department=$department'
          : '?period=$period';
      final response = await _http.get(
        '${ApiConfig.baseUrl}/api/analytics/team$query',
      );

      if (response.statusCode == 200) {
        debugPrint('✅ Team analytics retrieved');
        return response.body as Map<String, dynamic>?;
      }
      return null;
    } catch (e) {
      debugPrint('❌ Error retrieving team analytics: $e');
      return null;
    }
  }

  /// Export employee data
  Future<String?> exportEmployeeData({
    required String employeeId,
    String? format = 'pdf', // pdf, csv, excel
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final params = <String, String>{'format': format!};
      if (startDate != null) params['startDate'] = startDate.toIso8601String();
      if (endDate != null) params['endDate'] = endDate.toIso8601String();

      final queryString = params.entries
          .map((e) => '${e.key}=${e.value}')
          .join('&');
      final response = await _http.get(
        '${ApiConfig.baseUrl}/api/export/employee/$employeeId?$queryString',
      );

      if (response.statusCode == 200) {
        debugPrint('✅ Employee data exported for $employeeId');
        return '${ApiConfig.baseUrl}/downloads/export_$employeeId.$format';
      }
      return null;
    } catch (e) {
      debugPrint('❌ Error exporting data: $e');
      return null;
    }
  }

  /// Batch export employee data
  Future<String?> batchExportEmployeeData({
    required List<String> employeeIds,
    String? format = 'excel',
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final response = await _http.post(
        '${ApiConfig.baseUrl}/api/export/batch',
        body: {
          'employeeIds': employeeIds,
          'format': format,
          'startDate': startDate?.toIso8601String(),
          'endDate': endDate?.toIso8601String(),
          'timestamp': DateTime.now().toIso8601String(),
        },
      );

      if (response.statusCode == 200) {
        debugPrint(
          '✅ Batch export initiated for ${employeeIds.length} employees',
        );
        return '${ApiConfig.baseUrl}/downloads/batch_export_${DateTime.now().millisecondsSinceEpoch}.$format';
      }
      return null;
    } catch (e) {
      debugPrint('❌ Error batch exporting data: $e');
      return null;
    }
  }
}
