import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:field_check/screens/admin_task_management_screen.dart';

/// **Property 1: Bug Condition** - Missing Ticket Linking Fields
/// **Validates: Requirements 1.4**
/// 
/// This test MUST FAIL on unfixed code to confirm the bug exists.
/// The test encodes the expected behavior - it will validate the fix when it passes after implementation.
/// 
/// CRITICAL: This test is EXPECTED TO FAIL on unfixed code (failure confirms bug exists)
/// DO NOT attempt to fix the test or the code when it fails
/// 
/// GOAL: Surface counterexamples that demonstrate missing ticket linking functionality
/// Scoped PBT Approach: Test task creation form for ticket linking fields availability
void main() {
  group('Phase 3: Missing Ticket Linking Fields Bug Exploration', () {
    setUp(() {
      // Test setup - no mock services needed for UI testing
    });

    /// Test that admin_task_management_screen task creation dialog lacks "Link to Pending Ticket" dropdown
    /// This test MUST FAIL on unfixed code - failure confirms the bug exists
    testWidgets('Task creation form lacks Link to Pending Ticket dropdown field', (WidgetTester tester) async {
      // Arrange: Create the admin task management screen
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdminTaskManagementScreen(embedded: true),
          ),
        ),
      );

      // Wait for the widget to settle
      await tester.pumpAndSettle();

      // Act: Find and tap the "Create Task" button to open the dialog
      final createTaskButton = find.text('Create Task');
      expect(createTaskButton, findsWidgets, 
        reason: 'Create Task button should be present in admin task management screen');
      
      await tester.tap(createTaskButton.first);
      await tester.pumpAndSettle();

      // Assert: Look for the "Link to Pending Ticket" dropdown field
      // This assertion MUST FAIL on unfixed code to confirm the bug exists
      final linkTicketDropdown = find.byWidgetPredicate((widget) {
        if (widget is DropdownButtonFormField<String>) {
          final decoration = widget.decoration;
          return decoration.labelText?.contains('Link to Pending Ticket') == true ||
                 decoration.hintText?.contains('Link to Pending Ticket') == true;
        }
        return false;
      });

      // EXPECTED TO FAIL: This confirms the ticket linking dropdown is missing
      expect(linkTicketDropdown, findsOneWidget,
        reason: 'COUNTEREXAMPLE: Task creation form should have "Link to Pending Ticket" dropdown field but it is missing. '
               'This confirms the bug condition - missing ticket linking fields in admin_task_management_screen.');
    });

    /// Test that task creation form lacks "Client Ticket Number" manual text field
    /// This test MUST FAIL on unfixed code - failure confirms the bug exists
    testWidgets('Task creation form lacks Client Ticket Number manual text field', (WidgetTester tester) async {
      // Arrange: Create the admin task management screen
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdminTaskManagementScreen(embedded: true),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Act: Open the task creation dialog
      final createTaskButton = find.text('Create Task');
      await tester.tap(createTaskButton.first);
      await tester.pumpAndSettle();

      // Assert: Look for the "Client Ticket Number" text field
      // This assertion MUST FAIL on unfixed code to confirm the bug exists
      final clientTicketField = find.byWidgetPredicate((widget) {
        if (widget is TextField) {
          final decoration = widget.decoration;
          return decoration?.labelText?.contains('Client Ticket Number') == true ||
                 decoration?.hintText?.contains('Client Ticket Number') == true;
        }
        return false;
      });

      // EXPECTED TO FAIL: This confirms the manual ticket number field is missing
      expect(clientTicketField, findsOneWidget,
        reason: 'COUNTEREXAMPLE: Task creation form should have "Client Ticket Number" manual text field but it is missing. '
               'This confirms the bug condition - missing ticket linking fields in admin_task_management_screen.');
    });

    /// Test that task creation succeeds but cannot associate with client tickets
    /// This test MUST FAIL on unfixed code - failure confirms the bug exists
    testWidgets('Task creation succeeds but lacks ticket association capability', (WidgetTester tester) async {
      // Arrange: Create the admin task management screen
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdminTaskManagementScreen(embedded: true),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Act: Open task creation dialog and fill required fields
      final createTaskButton = find.text('Create Task');
      await tester.tap(createTaskButton.first);
      await tester.pumpAndSettle();

      // Fill in the basic required fields
      await tester.enterText(find.byWidgetPredicate((widget) => 
        widget is TextField && 
        widget.decoration?.labelText == 'Title *'), 'Test Task for Ticket RNG-20240101-ABCD');
      
      await tester.enterText(find.byWidgetPredicate((widget) => 
        widget is TextField && 
        widget.decoration?.labelText == 'Description *'), 'Task related to client ticket RNG-20240101-ABCD');

      // Select due date
      final dueDateField = find.byWidgetPredicate((widget) => 
        widget is InkWell && 
        widget.child is InputDecorator &&
        (widget.child as InputDecorator).decoration.labelText == 'Due Date *');
      
      await tester.tap(dueDateField);
      await tester.pumpAndSettle();
      
      // Select tomorrow's date
      final tomorrow = DateTime.now().add(Duration(days: 1));
      await tester.tap(find.text(tomorrow.day.toString()));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      // Assert: Verify that there's no way to link this task to a client ticket
      // Look for any ticket-related fields or functionality
      final ticketLinkingCapability = find.byWidgetPredicate((widget) {
        // Check for any widget that might provide ticket linking functionality
        if (widget is DropdownButtonFormField) {
          final decoration = widget.decoration;
          final labelText = decoration?.labelText?.toLowerCase() ?? '';
          final hintText = decoration?.hintText?.toLowerCase() ?? '';
          return labelText.contains('ticket') || hintText.contains('ticket');
        }
        if (widget is TextField) {
          final decoration = widget.decoration;
          final labelText = decoration?.labelText?.toLowerCase() ?? '';
          final hintText = decoration?.hintText?.toLowerCase() ?? '';
          return labelText.contains('ticket') || hintText.contains('ticket');
        }
        return false;
      });

      // EXPECTED TO FAIL: This confirms no ticket linking capability exists
      expect(ticketLinkingCapability, findsWidgets,
        reason: 'COUNTEREXAMPLE: Task creation form should provide ticket linking capability but none exists. '
               'This confirms the bug condition - tasks can be created but cannot be associated with client tickets. '
               'Bug Condition: isBugCondition_Phase3(input) where input.userRole == "admin" AND '
               'input.screen == "admin_task_management_screen" AND input.action == "createTask" AND '
               'input.wantsTicketLinking == true AND NOT ticketLinkingFieldsExist(input.taskForm)');
    });

    /// Property-based test to verify missing ticket linking fields across various task creation scenarios
    /// This test MUST FAIL on unfixed code - failure confirms the bug exists
    testWidgets('Property test: Task form consistently lacks ticket linking across scenarios', (WidgetTester tester) async {
      // Test multiple scenarios where admins would want to link tasks to tickets
      final testScenarios = [
        {
          'title': 'Maintenance Task for Ticket ABC-123',
          'description': 'Fix AC unit reported in ticket ABC-123',
          'type': 'maintenance',
          'difficulty': 'medium',
          'expectedTicketNumber': 'ABC-123'
        },
        {
          'title': 'Inspection Task for Ticket DEF-456', 
          'description': 'Inspect electrical system per ticket DEF-456',
          'type': 'inspection',
          'difficulty': 'hard',
          'expectedTicketNumber': 'DEF-456'
        },
        {
          'title': 'General Task for Ticket GHI-789',
          'description': 'Address client concern from ticket GHI-789',
          'type': 'general', 
          'difficulty': 'easy',
          'expectedTicketNumber': 'GHI-789'
        }
      ];

      for (final scenario in testScenarios) {
        // Arrange: Create fresh widget for each scenario
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AdminTaskManagementScreen(embedded: true),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Act: Open task creation dialog
        final createTaskButton = find.text('Create Task');
        await tester.tap(createTaskButton.first);
        await tester.pumpAndSettle();

        // Assert: Verify ticket linking fields are missing for this scenario
        final hasTicketDropdown = find.byWidgetPredicate((widget) {
          if (widget is DropdownButtonFormField<String>) {
            final decoration = widget.decoration;
            return decoration?.labelText?.contains('Ticket') == true ||
                   decoration?.hintText?.contains('Ticket') == true;
          }
          return false;
        });

        final hasTicketTextField = find.byWidgetPredicate((widget) {
          if (widget is TextField) {
            final decoration = widget.decoration;
            return decoration?.labelText?.contains('Ticket') == true ||
                   decoration?.hintText?.contains('Ticket') == true;
          }
          return false;
        });

        // EXPECTED TO FAIL: Confirms missing ticket linking across all scenarios
        expect(hasTicketDropdown.evaluate().isNotEmpty || hasTicketTextField.evaluate().isNotEmpty, isTrue,
          reason: 'COUNTEREXAMPLE for scenario "${scenario['title']}": '
                 'Task creation form should have ticket linking fields (dropdown OR text field) '
                 'but neither exists. This confirms the bug exists across multiple task creation scenarios. '
                 'Expected ticket number: ${scenario['expectedTicketNumber']}');

        // Close dialog for next iteration
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
      }
    });
  });
}