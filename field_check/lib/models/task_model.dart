import 'package:field_check/models/user_model.dart';

class TaskChecklistItem {
  final String label;
  final bool isCompleted;
  final DateTime? completedAt;

  TaskChecklistItem({
    required this.label,
    this.isCompleted = false,
    this.completedAt,
  });

  factory TaskChecklistItem.fromJson(Map<String, dynamic> json) {
    return TaskChecklistItem(
      label: json['label'] ?? '',
      isCompleted: json['isCompleted'] ?? false,
      completedAt: json['completedAt'] != null
          ? DateTime.tryParse(json['completedAt'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'label': label,
      'isCompleted': isCompleted,
      'completedAt': completedAt?.toIso8601String(),
    };
  }
}

class Task {
  final String id;
  final String title;
  final String description;
  final String? type;
  final String? difficulty;
  final DateTime dueDate;
  final String assignedBy; // Admin user ID
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastViewedAt;
  final String status; // e.g., 'pending', 'in_progress', 'completed'
  final String rawStatus;
  final int progressPercent;
  final String? userTaskId; // ID of the UserTask if assigned
  final String?
  userTaskStatus; // Per-assignee status (pending_acceptance/accepted/in_progress/completed)
  final DateTime? userTaskAssignedAt;
  final DateTime? userTaskCompletedAt;
  final UserModel? assignedTo; // Single assignee (for backward compatibility)
  final List<UserModel> assignedToMultiple; // Multiple assignees
  final String? geofenceId; // Auto-populated from assigned geofence
  final double? latitude;
  final double? longitude;
  final String? teamId; // Team assignment
  final List<String>? teamMembers; // List of team member IDs
  final bool isArchived;
  final bool isOverdue;
  final List<TaskChecklistItem> checklist;
  final String? blockReason;

  Task({
    required this.id,
    required this.title,
    required this.description,
    this.type,
    this.difficulty,
    required this.dueDate,
    required this.assignedBy,
    required this.createdAt,
    required this.updatedAt,
    this.lastViewedAt,
    required this.status,
    required this.rawStatus,
    required this.progressPercent,
    this.userTaskId,
    this.userTaskStatus,
    this.userTaskAssignedAt,
    this.userTaskCompletedAt,
    this.assignedTo,
    this.assignedToMultiple = const [],
    this.geofenceId,
    this.latitude,
    this.longitude,
    this.teamId,
    this.teamMembers,
    this.isArchived = false,
    this.isOverdue = false,
    this.checklist = const [],
    this.blockReason,
  });

  factory Task.fromJson(Map<String, dynamic> json) {
    List<UserModel> assignedToMultiple = [];
    if (json['assignedToMultiple'] is List) {
      assignedToMultiple = (json['assignedToMultiple'] as List)
          .map((e) {
            if (e is Map<String, dynamic>) {
              return UserModel.fromJson(e);
            }
            if (e is Map) {
              return UserModel.fromJson(Map<String, dynamic>.from(e));
            }
            if (e is String) {
              return UserModel(id: e, name: '', email: '', role: 'employee');
            }
            return UserModel(id: '', name: '', email: '', role: 'employee');
          })
          .where((u) => u.id.isNotEmpty)
          .toList();
    }

    List<String>? teamMembers;
    if (json['teamMembers'] is List) {
      teamMembers = (json['teamMembers'] as List)
          .whereType<String>()
          .where((s) => s.trim().isNotEmpty)
          .toList();
    } else if (json['userIds'] is List) {
      teamMembers = (json['userIds'] as List)
          .whereType<String>()
          .where((s) => s.trim().isNotEmpty)
          .toList();
    }

    if (assignedToMultiple.isEmpty &&
        teamMembers != null &&
        teamMembers.isNotEmpty) {
      assignedToMultiple = teamMembers
          .map((id) => UserModel(id: id, name: '', email: '', role: 'employee'))
          .toList();
    }

    final List<TaskChecklistItem> checklist = json['checklist'] is List
        ? (json['checklist'] as List)
              .whereType<Map<String, dynamic>>()
              .map(TaskChecklistItem.fromJson)
              .toList()
        : <TaskChecklistItem>[];

    final int progress = json['progressPercent'] is num
        ? (json['progressPercent'] as num).toInt()
        : 0;

    final createdAt = DateTime.parse(json['createdAt']);
    final updatedAtRaw = (json['updatedAt'] ?? json['createdAt'])?.toString();
    final updatedAt = updatedAtRaw != null
        ? (DateTime.tryParse(updatedAtRaw) ?? createdAt)
        : createdAt;

    final lastViewedAtRaw = json['lastViewedAt']?.toString();
    final lastViewedAt = lastViewedAtRaw != null
        ? DateTime.tryParse(lastViewedAtRaw)
        : null;

    final userTaskAssignedAtRaw = json['userTaskAssignedAt']?.toString();
    final userTaskCompletedAtRaw = json['userTaskCompletedAt']?.toString();
    final userTaskAssignedAt = userTaskAssignedAtRaw != null
        ? DateTime.tryParse(userTaskAssignedAtRaw)
        : null;
    final userTaskCompletedAt = userTaskCompletedAtRaw != null
        ? DateTime.tryParse(userTaskCompletedAtRaw)
        : null;

    return Task(
      id: json['_id'] ?? json['id'] ?? '',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      type: json['type'],
      difficulty: json['difficulty'],
      dueDate: DateTime.parse(json['dueDate']),
      assignedBy: json['assignedBy'] ?? '',
      createdAt: createdAt,
      updatedAt: updatedAt,
      lastViewedAt: lastViewedAt,
      status: json['status'] ?? 'pending',
      rawStatus: json['rawStatus'] ?? (json['status'] ?? 'pending'),
      progressPercent: progress,
      userTaskId: json['userTaskId'],
      userTaskStatus: json['userTaskStatus'],
      userTaskAssignedAt: userTaskAssignedAt,
      userTaskCompletedAt: userTaskCompletedAt,
      assignedTo: json['assignedTo'] != null
          ? UserModel.fromJson(json['assignedTo'])
          : null,
      assignedToMultiple: assignedToMultiple,
      geofenceId: json['geofenceId'],
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      teamId: json['teamId'],
      teamMembers: teamMembers,
      isArchived: json['isArchived'] ?? false,
      isOverdue: json['isOverdue'] ?? false,
      checklist: checklist,
      blockReason: json['blockReason'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      '_id': id,
      'title': title,
      'description': description,
      'type': type,
      'difficulty': difficulty,
      'dueDate': dueDate.toIso8601String(),
      'assignedBy': assignedBy,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'lastViewedAt': lastViewedAt?.toIso8601String(),
      'status': status,
      'rawStatus': rawStatus,
      'progressPercent': progressPercent,
      'userTaskId': userTaskId,
      'userTaskStatus': userTaskStatus,
      'userTaskAssignedAt': userTaskAssignedAt?.toIso8601String(),
      'userTaskCompletedAt': userTaskCompletedAt?.toIso8601String(),
      'assignedTo': assignedTo?.toJson(),
      'assignedToMultiple': assignedToMultiple.map((u) => u.toJson()).toList(),
      'geofenceId': geofenceId,
      'latitude': latitude,
      'longitude': longitude,
      'teamId': teamId,
      'teamMembers': teamMembers,
      'isArchived': isArchived,
      'isOverdue': isOverdue,
      'checklist': checklist.map((c) => c.toJson()).toList(),
      'blockReason': blockReason,
    };
  }

  Task copyWith({
    String? id,
    String? title,
    String? description,
    String? type,
    String? difficulty,
    DateTime? dueDate,
    String? assignedBy,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastViewedAt,
    String? status,
    String? rawStatus,
    int? progressPercent,
    String? userTaskId,
    String? userTaskStatus,
    DateTime? userTaskAssignedAt,
    DateTime? userTaskCompletedAt,
    UserModel? assignedTo,
    List<UserModel>? assignedToMultiple,
    String? geofenceId,
    double? latitude,
    double? longitude,
    String? teamId,
    List<String>? teamMembers,
    bool? isArchived,
    bool? isOverdue,
    List<TaskChecklistItem>? checklist,
    String? blockReason,
  }) {
    return Task(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      type: type ?? this.type,
      difficulty: difficulty ?? this.difficulty,
      dueDate: dueDate ?? this.dueDate,
      assignedBy: assignedBy ?? this.assignedBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastViewedAt: lastViewedAt ?? this.lastViewedAt,
      status: status ?? this.status,
      rawStatus: rawStatus ?? this.rawStatus,
      progressPercent: progressPercent ?? this.progressPercent,
      userTaskId: userTaskId ?? this.userTaskId,
      userTaskStatus: userTaskStatus ?? this.userTaskStatus,
      userTaskAssignedAt: userTaskAssignedAt ?? this.userTaskAssignedAt,
      userTaskCompletedAt: userTaskCompletedAt ?? this.userTaskCompletedAt,
      assignedTo: assignedTo ?? this.assignedTo,
      assignedToMultiple: assignedToMultiple ?? this.assignedToMultiple,
      geofenceId: geofenceId ?? this.geofenceId,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      teamId: teamId ?? this.teamId,
      teamMembers: teamMembers ?? this.teamMembers,
      isArchived: isArchived ?? this.isArchived,
      isOverdue: isOverdue ?? this.isOverdue,
      checklist: checklist ?? this.checklist,
      blockReason: blockReason ?? this.blockReason,
    );
  }
}
