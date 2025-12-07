class ReportModel {
  final String id;
  final String type; // 'task' or 'attendance'
  final String? taskId;
  final String? attendanceId;
  final String employeeId;
  final String? geofenceId;
  final String content;
  final String status; // 'submitted' | 'reviewed'
  final DateTime submittedAt;
  final String? employeeName;
  final String? employeeEmail;
  final String? taskTitle;
  final String? geofenceName;
  final bool isArchived;
  final List<String> attachments;

  ReportModel({
    required this.id,
    required this.type,
    this.taskId,
    this.attendanceId,
    required this.employeeId,
    this.geofenceId,
    required this.content,
    required this.status,
    required this.submittedAt,
    this.employeeName,
    this.employeeEmail,
    this.taskTitle,
    this.geofenceName,
    this.isArchived = false,
    this.attachments = const [],
  });

  factory ReportModel.fromJson(Map<String, dynamic> json) {
    final employee = json['employee'];
    final task = json['task'];
    final geofence = json['geofence'];
    return ReportModel(
      id: json['_id'] ?? json['id'] ?? '',
      type: json['type'] ?? 'task',
      taskId: task is Map ? task['_id'] : task,
      attendanceId: json['attendance'] is Map
          ? json['attendance']['_id']
          : json['attendance'],
      employeeId: employee is Map ? employee['_id'] : employee,
      geofenceId: geofence is Map ? geofence['_id'] : geofence,
      content: json['content'] ?? '',
      status: json['status'] ?? 'submitted',
      submittedAt: DateTime.parse(
        json['submittedAt'] ??
            json['createdAt'] ??
            DateTime.now().toIso8601String(),
      ),
      employeeName: employee is Map ? employee['name'] : null,
      employeeEmail: employee is Map ? employee['email'] : null,
      taskTitle: task is Map ? task['title'] : null,
      geofenceName: geofence is Map ? geofence['name'] : null,
      isArchived: json['isArchived'] ?? false,
      attachments: json['attachments'] is List
          ? List<String>.from(json['attachments'])
          : const [],
    );
  }
}
