import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:field_check/screens/admin_task_management_screen.dart';

/// Debug test to see what widgets are in the task creation dialog
void main() {
  testWidgets('Debug task creation dialog contents', (WidgetTester tester) async {
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
    print('Create Task buttons found: ${createTaskButton.evaluate().length}');
    
    if (createTaskButton.evaluate().isNotEmpty) {
      await tester.tap(createTaskButton.first);
      
      // Wait longer for async operations to complete
      print('Waiting for dialog to open...');
      await tester.pump(Duration(seconds: 1));
      await tester.pump(Duration(seconds: 1));
      await tester.pump(Duration(seconds: 1));

      // Debug: Print all widgets in the dialog
      final allWidgets = find.byType(Widget);
      print('Total widgets found: ${allWidgets.evaluate().length}');

      // Look for all DropdownButtonFormField widgets
      final dropdowns = find.byType(DropdownButtonFormField);
      print('DropdownButtonFormField widgets found: ${dropdowns.evaluate().length}');

      // Look for all TextField widgets
      final textFields = find.byType(TextField);
      print('TextField widgets found: ${textFields.evaluate().length}');

      // Look for AlertDialog
      final dialog = find.byType(AlertDialog);
      print('AlertDialog found: ${dialog.evaluate().length}');

      // Look for any text containing "ticket"
      final ticketText = find.textContaining('ticket', findRichText: true);
      print('Text containing "ticket": ${ticketText.evaluate().length}');

      // Look for any text containing "Link"
      final linkText = find.textContaining('Link', findRichText: true);
      print('Text containing "Link": ${linkText.evaluate().length}');

      // Print all text widgets to see what's actually there
      final allText = find.byType(Text);
      print('Text widgets found: ${allText.evaluate().length}');
      for (final element in allText.evaluate()) {
        final widget = element.widget as Text;
        if (widget.data != null && widget.data!.toLowerCase().contains('create')) {
          print('Text: "${widget.data}"');
        }
      }
    }
  });
}