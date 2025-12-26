import 'package:field_check/utils/http_util.dart';
import 'package:field_check/services/user_service.dart';

class NotificationService {
  static const String _basePath = '/api/notifications';

  Future<Map<String, String>> _headers() async {
    final token = await UserService().getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// Send an urgent SMS to all active employees with a phone number.
  Future<void> sendUrgentSmsToEmployees(String message) async {
    final response = await HttpUtil().post(
      '$_basePath/urgent',
      body: <String, dynamic>{
        'message': message,
        // Backend defaults to employees when roles/userIds are omitted
      },
      headers: await _headers(),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to send urgent SMS: ${response.body}');
    }
  }

  /// Send task assignment notification SMS
  Future<void> sendTaskAssignmentSms({
    required String employeeId,
    required String taskTitle,
    required String taskDescription,
  }) async {
    final message =
        'New Task: $taskTitle - $taskDescription. Check your app for details.';
    final response = await HttpUtil().post(
      '$_basePath/task-assignment',
      body: <String, dynamic>{
        'employeeId': employeeId,
        'taskTitle': taskTitle,
        'taskDescription': taskDescription,
        'message': message,
      },
      headers: await _headers(),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to send task assignment SMS: ${response.body}');
    }
  }

  /// Send overdue task warning SMS
  Future<void> sendOverdueTaskSms({
    required String employeeId,
    required String taskTitle,
    required int hoursOverdue,
  }) async {
    final message =
        'URGENT: Task "$taskTitle" is $hoursOverdue hours overdue. Please complete or update status immediately.';
    final response = await HttpUtil().post(
      '$_basePath/overdue-task',
      body: <String, dynamic>{
        'employeeId': employeeId,
        'taskTitle': taskTitle,
        'hoursOverdue': hoursOverdue,
        'message': message,
      },
      headers: await _headers(),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to send overdue task SMS: ${response.body}');
    }
  }

  /// Send check-in/out confirmation SMS
  Future<void> sendAttendanceSms({
    required String employeeId,
    required bool isCheckIn,
    required String geofenceName,
    required String timestamp,
  }) async {
    final action = isCheckIn ? 'Checked In' : 'Checked Out';
    final message =
        '$action at $geofenceName on $timestamp. Your attendance has been recorded.';
    final response = await HttpUtil().post(
      '$_basePath/attendance',
      body: <String, dynamic>{
        'employeeId': employeeId,
        'isCheckIn': isCheckIn,
        'geofenceName': geofenceName,
        'timestamp': timestamp,
        'message': message,
      },
      headers: await _headers(),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to send attendance SMS: ${response.body}');
    }
  }

  /// Send workload warning SMS
  Future<void> sendWorkloadWarningSms({
    required String employeeId,
    required int activeTaskCount,
    required double difficultyWeight,
  }) async {
    final message =
        'Workload Alert: You have $activeTaskCount active tasks with difficulty weight $difficultyWeight. Consider completing some tasks or requesting help.';
    final response = await HttpUtil().post(
      '$_basePath/workload-warning',
      body: <String, dynamic>{
        'employeeId': employeeId,
        'activeTaskCount': activeTaskCount,
        'difficultyWeight': difficultyWeight,
        'message': message,
      },
      headers: await _headers(),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to send workload warning SMS: ${response.body}');
    }
  }

  /// Send escalation SMS to task assignee
  Future<void> sendEscalationSms({
    required String employeeId,
    required String taskTitle,
    required String escalationReason,
  }) async {
    final message =
        'ESCALATION: Task "$taskTitle" has been escalated. Reason: $escalationReason. Please respond immediately.';
    final response = await HttpUtil().post(
      '$_basePath/escalation',
      body: <String, dynamic>{
        'employeeId': employeeId,
        'taskTitle': taskTitle,
        'escalationReason': escalationReason,
        'message': message,
      },
      headers: await _headers(),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to send escalation SMS: ${response.body}');
    }
  }

  /// Send location verification warning SMS
  Future<void> sendLocationWaringSms({
    required String employeeId,
    required String reason,
  }) async {
    final message =
        'Location Verification Failed: $reason. Please verify your GPS is enabled and try again.';
    final response = await HttpUtil().post(
      '$_basePath/location-warning',
      body: <String, dynamic>{
        'employeeId': employeeId,
        'reason': reason,
        'message': message,
      },
      headers: await _headers(),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to send location warning SMS: ${response.body}');
    }
  }

  /// Send batch SMS to multiple employees
  Future<void> sendBatchSms({
    required List<String> employeeIds,
    required String message,
    required String notificationType, // 'task', 'attendance', 'alert', etc.
  }) async {
    final response = await HttpUtil().post(
      '$_basePath/batch',
      body: <String, dynamic>{
        'employeeIds': employeeIds,
        'message': message,
        'notificationType': notificationType,
      },
      headers: await _headers(),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to send batch SMS: ${response.body}');
    }
  }
}
