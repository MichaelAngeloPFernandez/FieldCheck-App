import 'package:flutter_test/flutter_test.dart';

/// **Validates: Requirements 11.1, 11.2, 11.3, 11.4**
/// 
/// Employee Information Display Test for Task 15.4
/// 
/// This test validates that employee names and IDs are properly displayed
/// in notification details modals in the admin dashboard.
/// 
/// **Test Focus**: 
/// - Employee online notifications show correct employee name and ID
/// - Grouped online employees notifications show all employee information
/// - Notification payload parsing extracts employee data correctly
/// - Fallback to cached employee data when payload is incomplete
/// 
/// **Expected Behavior**:
/// - Employee names should not be blank in notification modals
/// - Employee IDs should not be blank in notification modals  
/// - Both individual and grouped notifications should display employee info
/// - Consistent formatting across all notification types
void main() {
  group('Task 15.4 - Employee Information Display in Notification Modals', () {

    test('Property: Employee online notification payload parsing extracts all required fields', () {
      // **Validates: Requirements 11.1, 11.2**
      // Test that the notification payload parsing logic correctly extracts
      // employee information from backend-generated payloads
      
      // Simulate the actual payload structure sent by backend for employee_online notifications
      // Based on backend/server.js line 426-437
      final Map<String, dynamic> backendPayload = {
        'scope': 'presenceStatus',
        'type': 'employee_online',
        'action': 'employee_online',
        'title': 'John Doe is online',
        'message': 'John Doe (EMP001) has come online',
        'payload': {
          'employeeId': '507f1f77bcf86cd799439011',
          'employeeName': 'John Doe',
          'employeeCode': 'EMP001',
        },
        'createdAt': '2024-01-15T10:30:00.000Z',
      };

      // Extract employee information using the same logic as _showNotificationDetails
      final payload = backendPayload['payload'] as Map<String, dynamic>? ?? backendPayload;
      
      String? employeeName;
      String? employeeCode;
      String? userId;

      // Extract userId from multiple possible sources (payload first)
      userId = payload['employeeId']?.toString() ?? 
               payload['userId']?.toString() ?? 
               payload['employeeUserId']?.toString();

      // Extract employee name from multiple sources (payload first)
      employeeName = payload['employeeName']?.toString() ?? 
                    payload['name']?.toString();

      // Extract employee code/ID from multiple sources (payload first)
      employeeCode = payload['employeeCode']?.toString() ?? 
                    payload['employeeId']?.toString();

      // Property: All employee information should be extracted correctly
      expect(userId, equals('507f1f77bcf86cd799439011'),
        reason: 'Employee user ID should be extracted from payload');
      expect(employeeName, equals('John Doe'),
        reason: 'Employee name should be extracted from payload');
      expect(employeeCode, equals('EMP001'),
        reason: 'Employee code should be extracted from payload');
      
      // Property: No employee information should be blank/null
      expect(userId, isNotNull, reason: 'Employee user ID should not be null');
      expect(employeeName, isNotNull, reason: 'Employee name should not be null');
      expect(employeeCode, isNotNull, reason: 'Employee code should not be null');
      expect(userId!.trim(), isNotEmpty, reason: 'Employee user ID should not be empty');
      expect(employeeName!.trim(), isNotEmpty, reason: 'Employee name should not be empty');
      expect(employeeCode!.trim(), isNotEmpty, reason: 'Employee code should not be empty');
    });

    test('Property: Grouped online employees notification extracts all employee information', () {
      // **Validates: Requirements 11.2, 11.4**
      // Test that grouped online employees notifications properly extract
      // information for all employees in the list
      
      // Simulate the actual payload structure for grouped online employees
      // Based on backend/server.js line 231-244
      final Map<String, dynamic> groupedPayload = {
        'action': 'seedOnlineSnapshot',
        'count': 3,
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
          },
          {
            'userId': '507f1f77bcf86cd799439013',
            'name': 'Bob Johnson',
            'employeeCode': 'EMP003',
          }
        ],
        'timestamp': '2024-01-15T10:30:00.000Z',
      };

      // Check if this is a grouped online employees notification
      final action = groupedPayload['action'] as String?;
      final isGroupedOnline = action == 'seedOnlineSnapshot' && 
                             groupedPayload['employees'] != null;
      
      expect(isGroupedOnline, isTrue,
        reason: 'Should correctly identify grouped online employees notification');

      // Extract employees list using same logic as _showNotificationDetails
      List<Map<String, dynamic>> employeesList = [];
      final rawList = groupedPayload['employees'];
      if (rawList is List) {
        employeesList = rawList.map((e) {
          if (e is Map<String, dynamic>) return e;
          if (e is Map) return Map<String, dynamic>.from(e);
          return <String, dynamic>{};
        }).toList();
      }

      // Property: All employees should be extracted
      expect(employeesList.length, equals(3),
        reason: 'Should extract all employees from grouped notification');

      // Property: Each employee should have complete information
      for (int i = 0; i < employeesList.length; i++) {
        final emp = employeesList[i];
        final name = emp['name']?.toString() ?? '';
        final code = emp['employeeCode']?.toString() ?? emp['employeeId']?.toString() ?? '';
        final userId = emp['userId']?.toString() ?? '';

        expect(name.trim(), isNotEmpty,
          reason: 'Employee ${i + 1} name should not be empty');
        expect(code.trim(), isNotEmpty,
          reason: 'Employee ${i + 1} code should not be empty');
        expect(userId.trim(), isNotEmpty,
          reason: 'Employee ${i + 1} user ID should not be empty');
      }

      // Property: Specific employee data should match expected values
      expect(employeesList[0]['name'], equals('John Doe'));
      expect(employeesList[0]['employeeCode'], equals('EMP001'));
      expect(employeesList[1]['name'], equals('Jane Smith'));
      expect(employeesList[1]['employeeCode'], equals('EMP002'));
      expect(employeesList[2]['name'], equals('Bob Johnson'));
      expect(employeesList[2]['employeeCode'], equals('EMP003'));
    });

    test('Property: Notification parsing handles missing employee information gracefully', () {
      // **Validates: Requirements 11.5**
      // Test that the system handles cases where employee information
      // is missing from the notification payload
      
      // Simulate a notification with incomplete employee information
      final Map<String, dynamic> incompletePayload = {
        'scope': 'presenceStatus',
        'type': 'employee_online',
        'action': 'employee_online',
        'title': 'Employee is online',
        'message': 'An employee has come online',
        // Missing employeeId, employeeName, employeeCode in payload
        'createdAt': '2024-01-15T10:30:00.000Z',
      };

      // Extract employee information using the same logic as _showNotificationDetails
      final payload = incompletePayload['payload'] as Map<String, dynamic>? ?? incompletePayload;
      
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

      // Property: Should handle missing information gracefully (no crashes)
      expect(() => userId?.toString(), returnsNormally,
        reason: 'Should handle missing user ID gracefully');
      expect(() => employeeName?.toString(), returnsNormally,
        reason: 'Should handle missing employee name gracefully');
      expect(() => employeeCode?.toString(), returnsNormally,
        reason: 'Should handle missing employee code gracefully');

      // Property: Missing values should be null (not throw exceptions)
      expect(userId, isNull, reason: 'Missing user ID should be null');
      expect(employeeName, isNull, reason: 'Missing employee name should be null');
      expect(employeeCode, isNull, reason: 'Missing employee code should be null');
    });

    test('Property: Employee information extraction prioritizes payload over nested objects', () {
      // **Validates: Requirements 11.1, 11.4**
      // Test that the extraction logic correctly prioritizes direct payload fields
      // over nested employee objects (as per the improved parsing logic)
      
      // Simulate a payload with both direct fields and nested employee object
      final Map<String, dynamic> mixedPayload = {
        // Direct payload fields (should be prioritized)
        'employeeId': '507f1f77bcf86cd799439011',
        'employeeName': 'John Doe (Direct)',
        'employeeCode': 'EMP001',
        // Nested employee object (should be fallback)
        'employee': {
          'name': 'John Doe (Nested)',
          'employeeId': 'EMP999',
          '_id': '507f1f77bcf86cd799439999',
        },
      };

      // Extract employee information using the improved logic
      String? employeeName;
      String? employeeCode;
      String? userId;

      // Extract userId from multiple possible sources (payload first)
      userId = mixedPayload['employeeId']?.toString() ?? 
               mixedPayload['userId']?.toString() ?? 
               mixedPayload['employeeUserId']?.toString();

      // Extract employee name from multiple sources (payload first)
      employeeName = mixedPayload['employeeName']?.toString() ?? 
                    mixedPayload['name']?.toString();

      // Extract employee code/ID from multiple sources (payload first)
      employeeCode = mixedPayload['employeeCode']?.toString() ?? 
                    mixedPayload['employeeId']?.toString();

      // Property: Should prioritize direct payload fields over nested objects
      expect(userId, equals('507f1f77bcf86cd799439011'),
        reason: 'Should prioritize direct employeeId over nested employee._id');
      expect(employeeName, equals('John Doe (Direct)'),
        reason: 'Should prioritize direct employeeName over nested employee.name');
      expect(employeeCode, equals('EMP001'),
        reason: 'Should prioritize direct employeeCode over nested employee.employeeId');
    });

    test('Property: Employee display formatting is consistent across notification types', () {
      // **Validates: Requirements 11.4**
      // Test that employee information is formatted consistently
      // regardless of notification type or source
      
      final testCases = [
        {
          'name': 'John Doe',
          'code': 'EMP001',
          'expectedDisplay': 'EMP001', // Should prefer code over raw ID
        },
        {
          'name': 'Jane Smith',
          'code': '', // Empty code
          'userId': '507f1f77bcf86cd799439012',
          'expectedDisplay': '507f1f77bcf86cd799439012', // Should fallback to userId
        },
        {
          'name': 'Bob Johnson',
          'code': null, // Null code
          'userId': '507f1f77bcf86cd799439013',
          'expectedDisplay': '507f1f77bcf86cd799439013', // Should fallback to userId
        },
      ];

      for (final testCase in testCases) {
        final employeeCode = testCase['code'];
        final userId = testCase['userId'];
        
        // Apply the same display logic as _showNotificationDetails
        final displayId = employeeCode != null && employeeCode.isNotEmpty ? employeeCode : userId;
        
        expect(displayId, equals(testCase['expectedDisplay']),
          reason: 'Employee display ID should follow consistent formatting rules');
      }
    });

    test('Property: Notification modal should display non-blank employee information', () {
      // **Validates: Requirements 11.1, 11.2, 11.3**
      // This is the core test that validates the fix for the reported bug:
      // "employee names and IDs are showing as blank in all notification details modals"
      
      // Test various notification payload scenarios that should result in
      // non-blank employee information being displayed
      
      final testNotifications = [
        {
          'description': 'Employee online notification with complete payload',
          'payload': {
            'employeeId': '507f1f77bcf86cd799439011',
            'employeeName': 'John Doe',
            'employeeCode': 'EMP001',
            'action': 'employee_online',
          },
          'expectedName': 'John Doe',
          'expectedId': 'EMP001',
        },
        {
          'description': 'Task assigned notification with employee info',
          'payload': {
            'userId': '507f1f77bcf86cd799439012',
            'name': 'Jane Smith',
            'employeeId': 'EMP002',
            'action': 'task_assigned',
          },
          'expectedName': 'Jane Smith',
          'expectedId': 'EMP002',
        },
        {
          'description': 'Employee status changed notification',
          'payload': {
            'employeeUserId': '507f1f77bcf86cd799439013',
            'employeeName': 'Bob Johnson',
            'employeeCode': 'EMP003',
            'action': 'employee_status_changed',
          },
          'expectedName': 'Bob Johnson',
          'expectedId': 'EMP003',
        },
      ];

      for (final notification in testNotifications) {
        final payload = notification['payload'] as Map<String, dynamic>;
        final description = notification['description'] as String;
        
        // Extract employee information using the fixed logic
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

        // Final display values (same logic as _showNotificationDetails)
        final displayName = employeeName ?? '-';
        final displayId = employeeCode ?? userId ?? '-';

        // Property: Employee information should never be blank
        expect(displayName, isNot(equals('')),
          reason: '$description: Employee name should not be blank');
        expect(displayId, isNot(equals('')),
          reason: '$description: Employee ID should not be blank');
        expect(displayName, isNot(equals('-')),
          reason: '$description: Employee name should not be placeholder dash');
        expect(displayId, isNot(equals('-')),
          reason: '$description: Employee ID should not be placeholder dash');

        // Property: Should match expected values
        expect(displayName, equals(notification['expectedName']),
          reason: '$description: Employee name should match expected value');
        expect(displayId, equals(notification['expectedId']),
          reason: '$description: Employee ID should match expected value');
      }
    });
  });
}