import 'package:field_check/models/task_model.dart';

class TaskTemplate {
  final String id;
  final String serviceId;
  final String companyId;
  final String title;
  final String? description;
  final String type; // general, inspection, maintenance, delivery, other
  final String difficulty; // easy, medium, hard
  final List<TaskChecklistItem> checklist;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  TaskTemplate({
    required this.id,
    required this.serviceId,
    required this.companyId,
    required this.title,
    this.description,
    this.type = 'general',
    this.difficulty = 'medium',
    this.checklist = const [],
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  factory TaskTemplate.fromJson(Map<String, dynamic> json) {
    final List<TaskChecklistItem> checklist = json['checklist'] is List
        ? (json['checklist'] as List)
              .whereType<Map<String, dynamic>>()
              .map(TaskChecklistItem.fromJson)
              .toList()
        : <TaskChecklistItem>[];

    return TaskTemplate(
      id: json['_id'] ?? json['id'] ?? '',
      serviceId: json['serviceId'] ?? '',
      companyId: json['companyId'] ?? '',
      title: json['title'] ?? '',
      description: json['description'],
      type: json['type'] ?? 'general',
      difficulty: json['difficulty'] ?? 'medium',
      checklist: checklist,
      isActive: json['isActive'] ?? true,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      '_id': id,
      'serviceId': serviceId,
      'companyId': companyId,
      'title': title,
      'description': description,
      'type': type,
      'difficulty': difficulty,
      'checklist': checklist.map((c) => c.toJson()).toList(),
      'isActive': isActive,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  TaskTemplate copyWith({
    String? id,
    String? serviceId,
    String? companyId,
    String? title,
    String? description,
    String? type,
    String? difficulty,
    List<TaskChecklistItem>? checklist,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return TaskTemplate(
      id: id ?? this.id,
      serviceId: serviceId ?? this.serviceId,
      companyId: companyId ?? this.companyId,
      title: title ?? this.title,
      description: description ?? this.description,
      type: type ?? this.type,
      difficulty: difficulty ?? this.difficulty,
      checklist: checklist ?? this.checklist,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
