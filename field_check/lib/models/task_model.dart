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
  final UserModel? assignedTo; // Assuming a UserModel for assigned user
  final double? latitude;
  final double? longitude;
  final String? address;

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
    this.latitude,
    this.longitude,
    this.address,
  });

  factory Task.fromJson(Map<String, dynamic> json) {
    final loc = json['location'];
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
      latitude: (loc != null) ? (loc['latitude'] as num?)?.toDouble() : null,
      longitude: (loc != null) ? (loc['longitude'] as num?)?.toDouble() : null,
      address: (loc != null) ? (loc['address'] as String?) : null,
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
      'location': (latitude != null && longitude != null)
          ? {
              'latitude': latitude,
              'longitude': longitude,
              'address': address ?? '',
            }
          : null,
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
    double? latitude,
    double? longitude,
    String? address,
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
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      address: address ?? this.address,
    );
  }
}