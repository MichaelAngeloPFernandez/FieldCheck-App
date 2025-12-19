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
  final String? taskDifficulty;
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
    this.taskDifficulty,
    this.geofenceName,
    this.isArchived = false,
    this.attachments = const [],
  });

  factory ReportModel.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> src = (json['report'] is Map<String, dynamic>)
        ? json['report']
        : json;

    String _readString(dynamic v) {
      if (v == null) return '';
      if (v is String) return v;
      return v.toString();
    }

    final dynamic contentRaw = src.containsKey('content')
        ? src['content']
        : (src.containsKey('message')
              ? src['message']
              : (src.containsKey('description')
                    ? src['description']
                    : (src.containsKey('text')
                          ? src['text']
                          : (src.containsKey('details')
                                ? src['details']
                                : null))));

    final employee = json['employee'];
    final task = json['task'];
    final geofence = json['geofence'];
    return ReportModel(
      id: src['_id'] ?? src['id'] ?? '',
      type: src['type'] ?? 'task',
      taskId: task is Map ? task['_id'] : task,
      attendanceId: src['attendance'] is Map
          ? src['attendance']['_id']
          : src['attendance'],
      employeeId: employee is Map ? employee['_id'] : employee,
      geofenceId: geofence is Map ? geofence['_id'] : geofence,
      content: _readString(contentRaw),
      status: src['status'] ?? 'submitted',
      submittedAt: DateTime.parse(
        src['submittedAt'] ??
            src['createdAt'] ??
            DateTime.now().toIso8601String(),
      ),
      employeeName: employee is Map ? employee['name'] : null,
      employeeEmail: employee is Map ? employee['email'] : null,
      taskTitle: task is Map ? task['title'] : null,
      taskDifficulty: task is Map ? task['difficulty'] : null,
      geofenceName: geofence is Map ? geofence['name'] : null,
      isArchived: src['isArchived'] ?? false,
      attachments: src['attachments'] is List
          ? List<String>.from(src['attachments'])
          : const [],
    );
  }
}
