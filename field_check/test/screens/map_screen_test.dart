import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:field_check/screens/map_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tests for Phase 3: Map Functionality Enhancement
/// Validates Requirements 6.1, 6.2, 6.3, 6.4, 8.1, 8.2, 8.3, 8.4, 8.5, 9.1, 9.2, 9.3, 9.4, 9.5
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Mock SharedPreferences for tests
    SharedPreferences.setMockInitialValues({});
  });

  group('Map Screen Creation Tests', () {
    testWidgets('Map screen widget can be instantiated', (WidgetTester tester) async {
      // Arrange & Act
      await tester.pumpWidget(
        const MaterialApp(
          home: MapScreen(),
        ),
      );

      // Assert - Widget should be created without errors
      expect(find.byType(MapScreen), findsOneWidget);
    });

    testWidgets('Map screen should have scaffold structure', (WidgetTester tester) async {
      // Arrange & Act
      await tester.pumpWidget(
        const MaterialApp(
          home: MapScreen(),
        ),
      );
      await tester.pump();

      // Assert - Should have basic scaffold structure
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('Map screen should have app bar with title', (WidgetTester tester) async {
      // Arrange & Act
      await tester.pumpWidget(
        const MaterialApp(
          home: MapScreen(),
        ),
      );
      await tester.pump();

      // Assert - Should have app bar
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.text('FieldCheck Map'), findsOneWidget);
    });
  });

  group('Map Navigation Tests (Requirement 6.1, 6.2, 6.3, 6.4)', () {
    testWidgets('Map screen can be navigated to from another screen', (WidgetTester tester) async {
      // Arrange & Act
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const MapScreen(),
                    ),
                  );
                },
                child: const Text('Open Map'),
              ),
            ),
          ),
        ),
      );

      // Tap the button to navigate
      await tester.tap(find.text('Open Map'));
      await tester.pumpAndSettle();

      // Assert - Should navigate to map screen
      expect(find.byType(MapScreen), findsOneWidget);
    });

    testWidgets('Map screen preserves navigation history for back button', (WidgetTester tester) async {
      // Arrange & Act
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const MapScreen(),
                    ),
                  );
                },
                child: const Text('Open Map'),
              ),
            ),
          ),
        ),
      );

      // Navigate to map
      await tester.tap(find.text('Open Map'));
      await tester.pumpAndSettle();

      // Assert - Should have back button in app bar
      expect(find.byType(BackButton), findsOneWidget);
    });
  });

  group('Map Control Buttons Tests', () {
    testWidgets('Map screen should have center map button (Requirement 8.1)', (WidgetTester tester) async {
      // Arrange & Act
      await tester.pumpWidget(
        const MaterialApp(
          home: MapScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Assert - Should have center map button with my_location icon
      expect(find.byIcon(Icons.my_location), findsOneWidget);
    });

    testWidgets('Map screen should have fit map button (Requirement 9.1)', (WidgetTester tester) async {
      // Arrange & Act
      await tester.pumpWidget(
        const MaterialApp(
          home: MapScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Assert - Should have fit map button with center_focus_strong icon
      expect(find.byIcon(Icons.center_focus_strong), findsOneWidget);
    });

    testWidgets('Map screen should have search button', (WidgetTester tester) async {
      // Arrange & Act
      await tester.pumpWidget(
        const MaterialApp(
          home: MapScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Assert - Should have search button
      expect(find.byIcon(Icons.search), findsWidgets);
    });

    testWidgets('Map screen should have refresh button', (WidgetTester tester) async {
      // Arrange & Act
      await tester.pumpWidget(
        const MaterialApp(
          home: MapScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Assert - Should have refresh button in app bar
      expect(find.byIcon(Icons.refresh), findsOneWidget);
    });
  });

  group('Map Button Tooltips Tests', () {
    testWidgets('Center map button should have correct tooltip (Requirement 8.1)', (WidgetTester tester) async {
      // Arrange & Act
      await tester.pumpWidget(
        const MaterialApp(
          home: MapScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Find the center map button by icon
      final centerButton = find.ancestor(
        of: find.byIcon(Icons.my_location),
        matching: find.byType(Tooltip),
      );

      // Assert - Should have tooltip
      expect(centerButton, findsOneWidget);
      
      final tooltip = tester.widget<Tooltip>(centerButton);
      expect(tooltip.message, contains('Center map'));
    });

    testWidgets('Fit map button should have correct tooltip (Requirement 9.1)', (WidgetTester tester) async {
      // Arrange & Act
      await tester.pumpWidget(
        const MaterialApp(
          home: MapScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Find the fit map button by icon
      final fitButton = find.ancestor(
        of: find.byIcon(Icons.center_focus_strong),
        matching: find.byType(Tooltip),
      );

      // Assert - Should have tooltip
      expect(fitButton, findsOneWidget);
      
      final tooltip = tester.widget<Tooltip>(fitButton);
      expect(tooltip.message, contains('Fit map'));
    });
  });
}
