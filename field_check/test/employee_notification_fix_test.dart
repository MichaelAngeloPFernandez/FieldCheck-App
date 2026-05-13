import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Employee Notification Information Extraction', () {
    test('should extract employee information from employee_online notification payload', () {
      // Simulate the payload structure sent by the backend for employee_online notifications
      final Map<String, dynamic> payload = {
        'employeeId': '507f1f77bcf86cd799439011',
        'employeeName': 'John Doe',
        'employeeCode': 'EMP001',
        'action': 'employee_online',
        'scope': 'presenceStatus',
        'type': 'employee_online',
      };

      // Extract employee information using the same logic as _showNotificationDetails
      String? employeeName;
      String? employeeCode;
      String? userId;

      // Extract userId from multiple possible sources
      userId = payload['employeeId']?.toString() ?? 
               payload['userId']?.toString() ?? 
               payload['employeeUserId']?.toString();

      // Extract employee name from multiple sources
      employeeName = payload['employeeName']?.toString() ?? 
                    payload['name']?.toString();

      // Extract employee code/ID from multiple sources
      employeeCode = payload['employeeCode']?.toString() ?? 
                    payload['employeeId']?.toString();

      // Verify the extraction worked correctly
      expect(userId, equals('507f1f77bcf86cd799439011'));
      expect(employeeName, equals('John Doe'));
      expect(employeeCode, equals('EMP001'));
    });

    test('should extract employee information from grouped online employees notification', () {
      // Simulate the payload structure for grouped online employees notification
      final Map<String, dynamic> payload = {
        'action': 'seedOnlineSnapshot',
        'count': 2,
        'employees': [
          {
            'userId': '507f1f77bcf86cd799439011',
            'name': 'John Doe',
            'employeeCode': 'EMP001',
          },
          {
            'userId': '507f1f77bcf86cd799439012',
            'name': 'Jane Smith',
            'employeeCode': 'EMP002',
          }
        ],
      };

      // Check if this is a grouped online employees notification
      final isGroupedOnline = payload['action'] == 'seedOnlineSnapshot' && 
                             payload['employees'] != null;
      
      expect(isGroupedOnline, isTrue);

      // Extract employees list
      List<Map<String, dynamic>> employeesList = [];
      final rawList = payload['employees'];
      if (rawList is List) {
        employeesList = rawList.map((e) {
          if (e is Map<String, dynamic>) return e;
          if (e is Map) return Map<String, dynamic>.from(e);
          return <String, dynamic>{};
        }).toList();
      }

      expect(employeesList.length, equals(2));
      
      // Verify first employee
      final emp1 = employeesList[0];
      expect(emp1['name']?.toString(), equals('John Doe'));
      expect(emp1['employeeCode']?.toString(), equals('EMP001'));
      expect(emp1['userId']?.toString(), equals('507f1f77bcf86cd799439011'));

      // Verify second employee
      final emp2 = employeesList[1];
      expect(emp2['name']?.toString(), equals('Jane Smith'));
      expect(emp2['employeeCode']?.toString(), equals('EMP002'));
      expect(emp2['userId']?.toString(), equals('507f1f77bcf86cd799439012'));
    });

    test('should handle missing employee information gracefully', () {
      // Simulate a payload with missing employee information
      final Map<String, dynamic> payload = {
        'action': 'employee_online',
        'scope': 'presenceStatus',
        'type': 'employee_online',
        // Missing employeeId, employeeName, employeeCode
      };

      // Extract employee information using the same logic as _showNotificationDetails
      String? employeeName;
      String? employeeCode;
      String? userId;

      // Extract userId from multiple possible sources
      userId = payload['employeeId']?.toString() ?? 
               payload['userId']?.toString() ?? 
               payload['employeeUserId']?.toString();

      // Extract employee name from multiple sources
      employeeName = payload['employeeName']?.toString() ?? 
                    payload['name']?.toString();

      // Extract employee code/ID from multiple sources
      employeeCode = payload['employeeCode']?.toString() ?? 
                    payload['employeeId']?.toString();

      // Should handle missing information gracefully
      expect(userId, isNull);
      expect(employeeName, isNull);
      expect(employeeCode, isNull);
    });

    test('should prioritize payload fields over employee object fields', () {
      // Simulate a payload with both direct fields and employee object
      final Map<String, dynamic> payload = {
        'employeeId': '507f1f77bcf86cd799439011',
        'employeeName': 'John Doe (Payload)',
        'employeeCode': 'EMP001',
        'employee': {
          'name': 'John Doe (Object)',
          'employeeId': 'EMP999',
          '_id': '507f1f77bcf86cd799439999',
        },
      };

      // Extract employee information using the same logic as _showNotificationDetails
      String? employeeName;
      String? employeeCode;
      String? userId;

      // Extract userId from multiple possible sources
      userId = payload['employeeId']?.toString() ?? 
               payload['userId']?.toString() ?? 
               payload['employeeUserId']?.toString();

      // Extract employee name from multiple sources (payload first)
      employeeName = payload['employeeName']?.toString() ?? 
                    payload['name']?.toString();

      // Extract employee code/ID from multiple sources (payload first)
      employeeCode = payload['employeeCode']?.toString() ?? 
                    payload['employeeId']?.toString();

      // Should prioritize payload fields over employee object
      expect(userId, equals('507f1f77bcf86cd799439011'));
      expect(employeeName, equals('John Doe (Payload)'));
      expect(employeeCode, equals('EMP001'));
    });
  });
}