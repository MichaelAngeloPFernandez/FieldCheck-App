class ReportModel {
  final String id;
  final String type; // 'task' or 'attendance'
  final String? taskId;
  final String? attendanceId;
  final String employeeId;
  final String? geofenceId;
  final String content;
  final String status; // 'submitted' | 'reviewed'
  final String? grade; // 'poor' | 'good' | 'excellent'
  final String gradeComment;
  final DateTime submittedAt;
  final DateTime? resubmitUntil;
  final String? employeeName;
  final String? employeeEmail;
  final String? taskTitle;
  final String? taskDifficulty;
  final String? geofenceName;
  final bool isArchived;
  final List<String> attachments;
  final bool taskIsOverdue;
  final String? taskBlockStatus;
  final String? taskBlockReasonCategory;
  final String? taskBlockReasonText;
  final DateTime? taskBlockedAt;

  ReportModel({
    required this.id,
    required this.type,
    this.taskId,
    this.attendanceId,
    required this.employeeId,
    this.geofenceId,
    required this.content,
    required this.status,
    this.grade,
    this.gradeComment = '',
    required this.submittedAt,
    this.resubmitUntil,
    this.employeeName,
    this.employeeEmail,
    this.taskTitle,
    this.taskDifficulty,
    this.geofenceName,
    this.isArchived = false,
    this.attachments = const [],
    this.taskIsOverdue = false,
    this.taskBlockStatus,
    this.taskBlockReasonCategory,
    this.taskBlockReasonText,
    this.taskBlockedAt,
  });

  factory ReportModel.fromJson(Map<String, dynamic> json) {
    final employee = json['employee'];
    final task = json['task'];
    final geofence = json['geofence'];
    final resubmitRaw = json['resubmitUntil']?.toString();
    final resubmitUntil = resubmitRaw != null
        ? DateTime.tryParse(resubmitRaw)
        : null;

    final blockedAtRaw = json['taskBlockedAt']?.toString();
    final taskBlockedAt = blockedAtRaw != null
        ? DateTime.tryParse(blockedAtRaw)
        : null;

    String parseEmployeeId() {
      if (employee is Map) {
        return (employee['_id'] ?? employee['id'] ?? '').toString();
      }
      if (employee != null) return employee.toString();
      return (json['employeeId'] ?? '').toString();
    }

    DateTime parseSubmittedAt() {
      final raw = json['submittedAt'] ?? json['createdAt'] ?? '';
      if (raw is String && raw.isNotEmpty) {
        return DateTime.tryParse(raw) ?? DateTime.now();
      }
      return DateTime.now();
    }

    return ReportModel(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      type: (json['type'] ?? 'task').toString(),
      taskId: task is Map ? task['_id']?.toString() : task?.toString(),
      attendanceId: json['attendance'] is Map
          ? json['attendance']['_id']?.toString()
          : json['attendance']?.toString(),
      employeeId: parseEmployeeId(),
      geofenceId: geofence is Map
          ? geofence['_id']?.toString()
          : geofence?.toString(),
      content: (json['content'] ?? '').toString(),
      status: (json['status'] ?? 'submitted').toString(),
      grade: json['grade']?.toString(),
      gradeComment: (json['gradeComment'] ?? '').toString(),
      submittedAt: parseSubmittedAt(),
      resubmitUntil: resubmitUntil,
      employeeName: employee is Map ? employee['name']?.toString() : null,
      employeeEmail: employee is Map ? employee['email']?.toString() : null,
      taskTitle: task is Map ? task['title']?.toString() : null,
      taskDifficulty: task is Map ? task['difficulty']?.toString() : null,
      geofenceName: geofence is Map ? geofence['name']?.toString() : null,
      isArchived: json['isArchived'] == true,
      attachments: json['attachments'] is List
          ? List<String>.from(json['attachments'].map((e) => e.toString()))
          : const [],
      taskIsOverdue: json['taskIsOverdue'] == true,
      taskBlockStatus: json['taskBlockStatus']?.toString(),
      taskBlockReasonCategory: json['taskBlockReasonCategory']?.toString(),
      taskBlockReasonText: json['taskBlockReasonText']?.toString(),
      taskBlockedAt: taskBlockedAt,
    );
  }
}
