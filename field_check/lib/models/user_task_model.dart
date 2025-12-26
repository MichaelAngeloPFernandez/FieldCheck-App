class UserTask {
  final String id;
  final String userModelId;
  final String taskId;
  String status; // e.g., 'pending', 'in_progress', 'completed'
  final DateTime assignedAt;
  DateTime? completedAt;

  UserTask({
    required this.id,
    required this.userModelId,
    required this.taskId,
    this.status = 'pending',
    required this.assignedAt,
    this.completedAt,
  });

  factory UserTask.fromJson(Map<String, dynamic> json) {
    return UserTask(
      id: json['id'],
      userModelId: json['userId'],
      taskId: json['taskId'],
      status: json['status'],
      assignedAt: DateTime.parse(json['assignedAt']),
      completedAt: json['completedAt'] != null
          ? DateTime.parse(json['completedAt'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userModelId,
      'taskId': taskId,
      'status': status,
      'assignedAt': assignedAt.toIso8601String(),
      'completedAt': completedAt?.toIso8601String(),
    };
  }
}