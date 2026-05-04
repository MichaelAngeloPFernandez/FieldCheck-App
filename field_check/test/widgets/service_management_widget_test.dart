import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:field_check/widgets/service_management_widget.dart';

void main() {
  group('ServiceManagementWidget', () {
    testWidgets('renders service management widget', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ServiceManagementWidget(),
          ),
        ),
      );

      // Verify the widget renders
      expect(find.byType(ServiceManagementWidget), findsOneWidget);
    });

    testWidgets('displays loading state initially', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ServiceManagementWidget(),
          ),
        ),
      );

      // Should show loading indicator
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}
