import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:field_check/screens/admin_task_management_screen.dart';

/// Simple verification test to check if ticket linking fields are present
/// This test should PASS when Phase 3 is implemented correctly
void main() {
  group('Phase 3: Ticket Linking Fields Verification', () {
    testWidgets('Task creation form has ticket linking fields', (WidgetTester tester) async {
      // Arrange: Create the admin task management screen
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdminTaskManagementScreen(embedded: true),
          ),
        ),
      );

      // Wait for initial render
      await tester.pump();

      // Act: Find and tap the "Create Task" button to open the dialog
      final createTaskButton = find.text('Create Task');
      expect(createTaskButton, findsWidgets, 
        reason: 'Create Task button should be present in admin task management screen');
      
      await tester.tap(createTaskButton.first);
      await tester.pump(); // Just pump once to open dialog

      // Assert: Look for the "Link to Pending Ticket" dropdown field
      final linkTicketDropdown = find.byWidgetPredicate((widget) {
        if (widget is DropdownButtonFormField<String>) {
          final decoration = widget.decoration;
          return decoration?.labelText?.contains('Link to Pending Ticket') == true ||
                 decoration?.hintText?.contains('Link to Pending Ticket') == true;
        }
        return false;
      });

      // This should PASS now that ticket linking is implemented
      expect(linkTicketDropdown, findsOneWidget,
        reason: 'Task creation form should have "Link to Pending Ticket" dropdown field');

      // Assert: Look for the "Client Ticket Number" text field
      final clientTicketField = find.byWidgetPredicate((widget) {
        if (widget is TextField) {
          final decoration = widget.decoration;
          return decoration?.labelText?.contains('Client Ticket Number') == true ||
                 decoration?.hintText?.contains('Client Ticket Number') == true;
        }
        return false;
      });

      // This should PASS now that ticket linking is implemented
      expect(clientTicketField, findsOneWidget,
        reason: 'Task creation form should have "Client Ticket Number" manual text field');
    });
  });
}