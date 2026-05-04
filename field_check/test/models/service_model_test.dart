import 'package:flutter_test/flutter_test.dart';
import 'package:field_check/models/service_model.dart';

void main() {
  group('Service Model', () {
    test('creates service from JSON', () {
      final json = {
        '_id': 'service123',
        'companyId': 'company123',
        'name': 'Aircon Cleaning',
        'description': 'Professional aircon cleaning service',
        'isActive': true,
        'createdAt': '2024-01-01T00:00:00Z',
        'updatedAt': '2024-01-01T00:00:00Z',
        'templateCount': 3,
      };

      final service = Service.fromJson(json);

      expect(service.id, 'service123');
      expect(service.companyId, 'company123');
      expect(service.name, 'Aircon Cleaning');
      expect(service.description, 'Professional aircon cleaning service');
      expect(service.isActive, true);
      expect(service.templateCount, 3);
    });

    test('converts service to JSON', () {
      final now = DateTime.now();
      final service = Service(
        id: 'service123',
        companyId: 'company123',
        name: 'Aircon Cleaning',
        description: 'Professional aircon cleaning service',
        isActive: true,
        createdAt: now,
        updatedAt: now,
        templateCount: 3,
      );

      final json = service.toJson();

      expect(json['_id'], 'service123');
      expect(json['companyId'], 'company123');
      expect(json['name'], 'Aircon Cleaning');
      expect(json['description'], 'Professional aircon cleaning service');
      expect(json['isActive'], true);
      expect(json['templateCount'], 3);
    });

    test('copyWith creates new instance with updated fields', () {
      final now = DateTime.now();
      final service = Service(
        id: 'service123',
        companyId: 'company123',
        name: 'Aircon Cleaning',
        description: 'Professional aircon cleaning service',
        isActive: true,
        createdAt: now,
        updatedAt: now,
        templateCount: 3,
      );

      final updated = service.copyWith(
        name: 'Plumbing Repair',
        isActive: false,
      );

      expect(updated.id, 'service123');
      expect(updated.name, 'Plumbing Repair');
      expect(updated.isActive, false);
      expect(updated.description, 'Professional aircon cleaning service');
    });

    test('handles missing optional fields', () {
      final json = {
        '_id': 'service123',
        'companyId': 'company123',
        'name': 'Aircon Cleaning',
        'isActive': true,
        'createdAt': '2024-01-01T00:00:00Z',
        'updatedAt': '2024-01-01T00:00:00Z',
      };

      final service = Service.fromJson(json);

      expect(service.description, isNull);
      expect(service.templateCount, 0);
    });
  });
}
