import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:field_check/screens/admin_dashboard_screen.dart';

/// Simple test to verify navigation order without Socket.IO dependencies
void main() {
  group('Simple Navigation Order Test', () {
    late Widget testApp;

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues(<String, Object>{});
      
      testApp = MaterialApp(
        home: const AdminDashboardScreen(),
      );
    });

    testWidgets('Desktop NavigationRail destinations are in correct order', (WidgetTester tester) async {
      // Set desktop screen size (width >= 980)
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      
      await tester.pumpWidget(testApp);
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Find NavigationRail
      final navigationRail = find.byType(NavigationRail);
      expect(navigationRail, findsOneWidget);

      // Get the NavigationRail widget
      final railWidget = tester.widget<NavigationRail>(navigationRail);
      expect(railWidget.destinations.length, equals(7)); // Should have 7 destinations
      
      // Verify the navigation order by checking destination labels
      expect(railWidget.destinations[0].label, isA<Text>());
      expect((railWidget.destinations[0].label as Text).data, equals('Dashboard'));
      
      expect(railWidget.destinations[1].label, isA<Text>());
      expect((railWidget.destinations[1].label as Text).data, equals('Employees'));
      
      expect(railWidget.destinations[2].label, isA<Text>());
      expect((railWidget.destinations[2].label as Text).data, equals('Admins'));
      
      expect(railWidget.destinations[3].label, isA<Text>());
      expect((railWidget.destinations[3].label as Text).data, equals('Geofences'));
      
      expect(railWidget.destinations[4].label, isA<Text>());
      expect((railWidget.destinations[4].label as Text).data, equals('Reports'));
      
      expect(railWidget.destinations[5].label, isA<Text>());
      expect((railWidget.destinations[5].label as Text).data, equals('Settings'));
      
      expect(railWidget.destinations[6].label, isA<Text>());
      expect((railWidget.destinations[6].label as Text).data, equals('Tasks'));
    });

    testWidgets('Mobile devices show Drawer instead of BottomNavigationBar', (WidgetTester tester) async {
      // Set mobile screen size (width < 600)
      await tester.binding.setSurfaceSize(const Size(400, 800));
      
      await tester.pumpWidget(testApp);
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // On mobile, we should have a Drawer
      expect(find.byType(Drawer), findsOneWidget,
        reason: 'Mobile layout should show hamburger Drawer');
      
      // Verify BottomNavigationBar should NOT exist on mobile
      expect(find.byType(BottomNavigationBar), findsNothing,
        reason: 'Mobile layout should NOT show BottomNavigationBar');
    });
  });
}