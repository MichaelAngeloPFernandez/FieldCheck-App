import 'package:flutter_test/flutter_test.dart';
import 'package:field_check/models/task_template_model.dart';
import 'package:field_check/models/task_model.dart';

void main() {
  group('TaskTemplate Model', () {
    test('creates task template from JSON', () {
      final json = {
        '_id': 'template123',
        'serviceId': 'service123',
        'companyId': 'company123',
        'title': 'Inspect Filters',
        'description': 'Inspect and clean aircon filters',
        'type': 'inspection',
        'difficulty': 'easy',
        'checklist': [
          {'label': 'Check filter condition', 'isCompleted': false},
          {'label': 'Clean filter', 'isCompleted': false},
        ],
        'isActive': true,
        'createdAt': '2024-01-01T00:00:00Z',
        'updatedAt': '2024-01-01T00:00:00Z',
      };

      final template = TaskTemplate.fromJson(json);

      expect(template.id, 'template123');
      expect(template.serviceId, 'service123');
      expect(template.companyId, 'company123');
      expect(template.title, 'Inspect Filters');
      expect(template.description, 'Inspect and clean aircon filters');
      expect(template.type, 'inspection');
      expect(template.difficulty, 'easy');
      expect(template.checklist.length, 2);
      expect(template.isActive, true);
    });

    test('converts task template to JSON', () {
      final now = DateTime.now();
      final checklist = [
        TaskChecklistItem(label: 'Check filter condition'),
        TaskChecklistItem(label: 'Clean filter'),
      ];

      final template = TaskTemplate(
        id: 'template123',
        serviceId: 'service123',
        companyId: 'company123',
        title: 'Inspect Filters',
        description: 'Inspect and clean aircon filters',
        type: 'inspection',
        difficulty: 'easy',
        checklist: checklist,
        isActive: true,
        createdAt: now,
        updatedAt: now,
      );

      final json = template.toJson();

      expect(json['_id'], 'template123');
      expect(json['serviceId'], 'service123');
      expect(json['companyId'], 'company123');
      expect(json['title'], 'Inspect Filters');
      expect(json['type'], 'inspection');
      expect(json['difficulty'], 'easy');
      expect(json['checklist'].length, 2);
      expect(json['isActive'], true);
    });

    test('copyWith creates new instance with updated fields', () {
      final now = DateTime.now();
      final template = TaskTemplate(
        id: 'template123',
        serviceId: 'service123',
        companyId: 'company123',
        title: 'Inspect Filters',
        description: 'Inspect and clean aircon filters',
        type: 'inspection',
        difficulty: 'easy',
        checklist: [],
        isActive: true,
        createdAt: now,
        updatedAt: now,
      );

      final updated = template.copyWith(
        title: 'Clean Coils',
        difficulty: 'medium',
      );

      expect(updated.id, 'template123');
      expect(updated.title, 'Clean Coils');
      expect(updated.difficulty, 'medium');
      expect(updated.type, 'inspection');
    });

    test('handles default values', () {
      final json = {
        '_id': 'template123',
        'serviceId': 'service123',
        'companyId': 'company123',
        'title': 'Inspect Filters',
        'createdAt': '2024-01-01T00:00:00Z',
        'updatedAt': '2024-01-01T00:00:00Z',
      };

      final template = TaskTemplate.fromJson(json);

      expect(template.type, 'general');
      expect(template.difficulty, 'medium');
      expect(template.checklist, isEmpty);
      expect(template.isActive, true);
    });

    test('handles checklist items correctly', () {
      final json = {
        '_id': 'template123',
        'serviceId': 'service123',
        'companyId': 'company123',
        'title': 'Inspect Filters',
        'checklist': [
          {
            'label': 'Check filter condition',
            'isCompleted': true,
            'completedAt': '2024-01-01T10:00:00Z',
          },
          {
            'label': 'Clean filter',
            'isCompleted': false,
          },
        ],
        'createdAt': '2024-01-01T00:00:00Z',
        'updatedAt': '2024-01-01T00:00:00Z',
      };

      final template = TaskTemplate.fromJson(json);

      expect(template.checklist.length, 2);
      expect(template.checklist[0].label, 'Check filter condition');
      expect(template.checklist[0].isCompleted, true);
      expect(template.checklist[1].label, 'Clean filter');
      expect(template.checklist[1].isCompleted, false);
    });
  });
}
