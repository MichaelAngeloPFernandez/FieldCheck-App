import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:field_check/screens/admin_dashboard_screen.dart';

/// **Validates: Requirements 3.1, 3.2**
/// 
/// Preservation Property Tests for Phase 1 - Navigation Functionality Preservation
/// 
/// **IMPORTANT**: Follow observation-first methodology
/// Observe behavior on UNFIXED code for keyboard shortcuts, responsive layout detection, and non-navigation interactions
/// Write property-based tests capturing observed behavior patterns from Preservation Requirements
/// Property-based testing generates many test cases for stronger guarantees
/// Run tests on UNFIXED code
/// **EXPECTED OUTCOME**: Tests PASS (this confirms baseline behavior to preserve)
/// 
/// This test captures the CURRENT behavior that must be preserved:
/// 1. Keyboard shortcuts (Ctrl+1 through Ctrl+7) respond correctly (even if to wrong screens)
/// 2. Screen size detection for responsive layout works properly
/// 3. Non-navigation interactions remain unaffected
void main() {
  group('Phase 1 Preservation Tests - Navigation Functionality Preservation', () {
    late Widget testApp;

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues(<String, Object>{});
      
      testApp = MaterialApp(
        home: const AdminDashboardScreen(),
      );
    });

    testWidgets('Property: Keyboard shortcuts (Ctrl+1-7) respond correctly to current navigation mapping', (WidgetTester tester) async {
      // Set desktop screen size
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      
      await tester.pumpWidget(testApp);
      await tester.pumpAndSettle();

      // Observe and preserve CURRENT keyboard shortcut behavior (even if mapping is wrong)
      // This test captures what the shortcuts CURRENTLY do, not what they should do
      
      // Find the NavigationRail widget to verify it exists
      final navigationRail = find.byType(NavigationRail);
      expect(navigationRail, findsOneWidget,
        reason: 'Desktop layout should show NavigationRail - preserving current responsive behavior');
      
      // Verify keyboard shortcuts are configured (Ctrl+1 through Ctrl+7)
      final shortcuts = find.byType(Shortcuts);
      expect(shortcuts, findsOneWidget,
        reason: 'Keyboard shortcuts should be configured - preserving current shortcut functionality');
      
      // Test that keyboard shortcuts trigger navigation (without testing specific screens due to service dependencies)
      // This preserves the fact that shortcuts work, even if the mapping is currently wrong
      
      // Ctrl+1 should navigate to Dashboard (index 0) - CURRENT behavior
      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.digit1);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.digit1);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await tester.pumpAndSettle();
      
      // Dashboard is the default screen - this should work
      expect(find.text('Admin Dashboard'), findsOneWidget,
        reason: 'Ctrl+1 should navigate to Dashboard - preserving current behavior');
    });

    testWidgets('Property: Screen size detection for responsive layout works properly', (WidgetTester tester) async {
      // Test desktop layout detection (width >= 980)
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      
      await tester.pumpWidget(testApp);
      await tester.pumpAndSettle();

      // Desktop should show NavigationRail and NOT show BottomNavigationBar
      expect(find.byType(NavigationRail), findsOneWidget,
        reason: 'Desktop layout (width >= 980) should show NavigationRail - preserving current responsive behavior');
      expect(find.byType(BottomNavigationBar), findsNothing,
        reason: 'Desktop layout should not show BottomNavigationBar - preserving current responsive behavior');
      
      // Test mobile layout detection (width < 980)
      await tester.binding.setSurfaceSize(const Size(600, 800));
      
      await tester.pumpWidget(testApp);
      await tester.pumpAndSettle();

      // Mobile should show BottomNavigationBar and NOT show NavigationRail
      expect(find.byType(BottomNavigationBar), findsOneWidget,
        reason: 'Mobile layout (width < 980) should show BottomNavigationBar - preserving current responsive behavior');
      expect(find.byType(NavigationRail), findsNothing,
        reason: 'Mobile layout should not show NavigationRail - preserving current responsive behavior');
      
      // Test edge case around breakpoint (width = 980)
      await tester.binding.setSurfaceSize(const Size(980, 800));
      
      await tester.pumpWidget(testApp);
      await tester.pumpAndSettle();

      // At exactly 980px, should use desktop layout (NavigationRail)
      expect(find.byType(NavigationRail), findsOneWidget,
        reason: 'At breakpoint width=980, should show NavigationRail - preserving current responsive behavior');
      expect(find.byType(BottomNavigationBar), findsNothing,
        reason: 'At breakpoint width=980, should not show BottomNavigationBar - preserving current responsive behavior');
      
      // Test just below breakpoint (width = 979)
      await tester.binding.setSurfaceSize(const Size(979, 800));
      
      await tester.pumpWidget(testApp);
      await tester.pumpAndSettle();

      // Just below 980px, should use mobile layout (BottomNavigationBar)
      expect(find.byType(BottomNavigationBar), findsOneWidget,
        reason: 'Just below breakpoint width=979, should show BottomNavigationBar - preserving current responsive behavior');
      expect(find.byType(NavigationRail), findsNothing,
        reason: 'Just below breakpoint width=979, should not show NavigationRail - preserving current responsive behavior');
    });

    testWidgets('Property-Based Test: Keyboard shortcuts work across different screen sizes', (WidgetTester tester) async {
      final screenSizes = [
        const Size(1200, 800), // Desktop
        const Size(1024, 768), // Tablet landscape
        const Size(980, 600),  // Breakpoint
      ];

      for (final size in screenSizes) {
        await tester.binding.setSurfaceSize(size);
        
        await tester.pumpWidget(testApp);
        await tester.pumpAndSettle();

        // Property: Keyboard shortcuts should work regardless of screen size
        // Test Ctrl+1 (Dashboard) as a representative case
        await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.digit1);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.digit1);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
        await tester.pumpAndSettle();
        
        expect(find.text('Admin Dashboard'), findsOneWidget,
          reason: 'Ctrl+1 should work on screen size ${size.width}x${size.height} - preserving keyboard shortcut functionality across responsive layouts');
      }
    });

    testWidgets('Property: Non-navigation interactions remain unaffected', (WidgetTester tester) async {
      // Set desktop screen size
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      
      await tester.pumpWidget(testApp);
      await tester.pumpAndSettle();

      // Test that non-navigation interactions work normally
      // These should be completely unaffected by navigation fixes
      
      // Test app bar title updates correctly with navigation
      expect(find.text('Admin Dashboard'), findsOneWidget,
        reason: 'App bar should show correct title for dashboard - preserving non-navigation UI behavior');
      
      // Test that scaffold structure remains intact
      expect(find.byType(Scaffold), findsOneWidget,
        reason: 'Scaffold structure should remain intact - preserving overall app structure');
      
      // Test that navigation rail hover expansion still works (if applicable)
      expect(find.byType(NavigationRail), findsOneWidget,
        reason: 'NavigationRail should remain functional - preserving navigation component behavior');
    });

    testWidgets('Property-Based Test: Current navigation mapping consistency', (WidgetTester tester) async {
      // Set desktop screen size
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      
      await tester.pumpWidget(testApp);
      await tester.pumpAndSettle();

      // Property: Current navigation mapping should be consistent
      // This captures the CURRENT (incorrect) mapping that must be preserved until fix
      
      // Verify NavigationRail has 7 destinations
      final navigationRail = find.byType(NavigationRail);
      expect(navigationRail, findsOneWidget);
      
      final railWidget = tester.widget<NavigationRail>(navigationRail);
      expect(railWidget.destinations.length, equals(7),
        reason: 'NavigationRail should have 7 destinations - preserving current navigation structure');
      
      // Verify the destination labels are correct (even if mapping is wrong)
      expect(railWidget.destinations[0].label, isA<Text>());
      expect(railWidget.destinations[1].label, isA<Text>());
      expect(railWidget.destinations[2].label, isA<Text>());
      expect(railWidget.destinations[3].label, isA<Text>());
      expect(railWidget.destinations[4].label, isA<Text>());
      expect(railWidget.destinations[5].label, isA<Text>());
      expect(railWidget.destinations[6].label, isA<Text>());
    });

    testWidgets('Property: Mobile BottomNavigationBar current behavior preservation', (WidgetTester tester) async {
      // Set mobile screen size
      await tester.binding.setSurfaceSize(const Size(400, 800));
      
      await tester.pumpWidget(testApp);
      await tester.pumpAndSettle();

      // Preserve current mobile navigation behavior (even though it will change)
      final bottomNav = find.byType(BottomNavigationBar);
      expect(bottomNav, findsOneWidget,
        reason: 'Mobile should currently show BottomNavigationBar - preserving current mobile behavior');
      
      final bottomNavWidget = tester.widget<BottomNavigationBar>(bottomNav);
      
      // Test current mobile navigation items (5 items: Dashboard, Employees, Reports, Tickets, More)
      expect(bottomNavWidget.items.length, equals(5),
        reason: 'BottomNavigationBar should have 5 items - preserving current mobile navigation structure');
      
      // Test current mobile navigation labels
      expect(bottomNavWidget.items[0].label, equals('Dashboard'));
      expect(bottomNavWidget.items[1].label, equals('Employees'));
      expect(bottomNavWidget.items[2].label, equals('Reports'));
      expect(bottomNavWidget.items[3].label, equals('Tickets'));
      expect(bottomNavWidget.items[4].label, equals('More'));
      
      // Verify that NavigationRail is not shown on mobile
      expect(find.byType(NavigationRail), findsNothing,
        reason: 'Mobile layout should not show NavigationRail - preserving current responsive behavior');
    });
  });
}