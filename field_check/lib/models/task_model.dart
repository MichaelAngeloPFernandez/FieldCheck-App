import 'package:field_check/models/user_model.dart';

class Task {
  final String id;
  final String title;
  final String description;
  final DateTime dueDate;
  final String assignedBy; // Admin user ID
  final DateTime createdAt;
  final String status; // e.g., 'pending', 'in_progress', 'completed'
  final String? userTaskId; // ID of the UserTask if assigned
  final UserModel? assignedTo; // Single assignee (for backward compatibility)
  final List<UserModel> assignedToMultiple; // Multiple assignees
  final String? geofenceId; // Auto-populated from assigned geofence
  final double? latitude;
  final double? longitude;
  final String? teamId; // Team assignment
  final List<String>? teamMembers; // List of team member IDs

  Task({
    required this.id,
    required this.title,
    required this.description,
    required this.dueDate,
    required this.assignedBy,
    required this.createdAt,
    required this.status,
    this.userTaskId,
    this.assignedTo,
    this.assignedToMultiple = const [],
    this.geofenceId,
    this.latitude,
    this.longitude,
    this.teamId,
    this.teamMembers,
  });

  factory Task.fromJson(Map<String, dynamic> json) {
    List<UserModel> assignedToMultiple = [];
    if (json['assignedToMultiple'] is List) {
      assignedToMultiple = (json['assignedToMultiple'] as List)
          .map((e) => UserModel.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    return Task(
      id: json['_id'] ?? json['id'] ?? '',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      dueDate: DateTime.parse(json['dueDate']),
      assignedBy: json['assignedBy'] ?? '',
      createdAt: DateTime.parse(json['createdAt']),
      status: json['status'] ?? 'pending',
      userTaskId: json['userTaskId'],
      assignedTo: json['assignedTo'] != null
          ? UserModel.fromJson(json['assignedTo'])
          : null,
      assignedToMultiple: assignedToMultiple,
      geofenceId: json['geofenceId'],
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      teamId: json['teamId'],
      teamMembers: json['teamMembers'] != null
          ? List<String>.from(json['teamMembers'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      '_id': id,
      'title': title,
      'description': description,
      'dueDate': dueDate.toIso8601String(),
      'assignedBy': assignedBy,
      'createdAt': createdAt.toIso8601String(),
      'status': status,
      'userTaskId': userTaskId,
      'assignedTo': assignedTo?.toJson(),
      'assignedToMultiple': assignedToMultiple.map((u) => u.toJson()).toList(),
      'geofenceId': geofenceId,
      'latitude': latitude,
      'longitude': longitude,
      'teamId': teamId,
      'teamMembers': teamMembers,
    };
  }

  Task copyWith({
    String? id,
    String? title,
    String? description,
    DateTime? dueDate,
    String? assignedBy,
    DateTime? createdAt,
    String? status,
    String? userTaskId,
    UserModel? assignedTo,
    List<UserModel>? assignedToMultiple,
    String? geofenceId,
    double? latitude,
    double? longitude,
    String? teamId,
    List<String>? teamMembers,
  }) {
    return Task(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      dueDate: dueDate ?? this.dueDate,
      assignedBy: assignedBy ?? this.assignedBy,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
      userTaskId: userTaskId ?? this.userTaskId,
      assignedTo: assignedTo ?? this.assignedTo,
      assignedToMultiple: assignedToMultiple ?? this.assignedToMultiple,
      geofenceId: geofenceId ?? this.geofenceId,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      teamId: teamId ?? this.teamId,
      teamMembers: teamMembers ?? this.teamMembers,
    );
  }
}
