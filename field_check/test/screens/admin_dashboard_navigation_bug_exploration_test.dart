import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:field_check/screens/admin_dashboard_screen.dart';
import 'package:field_check/screens/manage_employees_screen.dart';
import 'package:field_check/screens/admin_reports_hub_screen.dart';
import 'package:field_check/screens/client_tickets_screen.dart';
import 'package:field_check/screens/manage_admins_screen.dart';
import 'package:field_check/screens/admin_geofence_screen.dart';
import 'package:field_check/screens/admin_settings_screen.dart';
import 'package:field_check/screens/admin_task_management_screen.dart';

/// **Validates: Requirements 1.1, 1.2**
/// 
/// Bug Condition Exploration Test for Phase 1 - Navigation Order and Mobile Menu Issues
/// 
/// **CRITICAL**: This test MUST FAIL on unfixed code - failure confirms the bugs exist
/// **DO NOT attempt to fix the test or the code when it fails**
/// **NOTE**: This test encodes the expected behavior - it will validate the fixes when it passes after implementation
/// **GOAL**: Surface counterexamples that demonstrate navigation order and mobile menu bugs exist
/// 
/// This test demonstrates:
/// 1. Desktop NavigationRail destinations are in incorrect order (current order != [Dashboard, Employees, Admins, Geofences, Reports, Settings, Tasks])
/// 2. Mobile devices show BottomNavigationBar instead of hamburger drawer menu
/// 3. Keyboard shortcuts (Ctrl+1-7) point to wrong destinations due to incorrect order
void main() {
  group('Phase 1 Bug Condition Exploration - Navigation Issues', () {
    late Widget testApp;

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues(<String, Object>{});
      
      testApp = MaterialApp(
        home: const AdminDashboardScreen(),
      );
    });

    testWidgets('EXPECTED TO FAIL: Desktop NavigationRail destinations are in INCORRECT order', (WidgetTester tester) async {
      // Set desktop screen size (width >= 980)
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      
      await tester.pumpWidget(testApp);
      await tester.pumpAndSettle();

      // Find NavigationRail
      final navigationRail = find.byType(NavigationRail);
      expect(navigationRail, findsOneWidget);

      // Test the EXPECTED navigation order (this should FAIL on unfixed code)
      // Expected order: 0: Dashboard | 1: Employees | 2: Admins | 3: Geofences | 4: Reports | 5: Settings | 6: Tasks
      
      // Test index 2 should show Admins (ManageAdminsScreen) - WILL FAIL because it currently shows Reports
      await tester.tap(find.byType(NavigationRail));
      await tester.pumpAndSettle();
      
      // Simulate clicking the 3rd destination (index 2) - should be Admins but is currently Reports
      final railWidget = tester.widget<NavigationRail>(navigationRail);
      expect(railWidget.destinations.length, equals(7)); // Should have 7 destinations
      
      // Click on index 2 destination (should be Admins)
      railWidget.onDestinationSelected!(2);
      await tester.pumpAndSettle();
      
      // This assertion WILL FAIL on unfixed code because index 2 currently shows AdminReportsHubScreen instead of ManageAdminsScreen
      expect(find.byType(ManageAdminsScreen), findsOneWidget, 
        reason: 'Index 2 should show Admins screen but currently shows Reports screen - this confirms the navigation order bug exists');
      
      // Test index 3 should show Geofences (AdminGeofenceScreen) - WILL FAIL because it currently shows ClientTicketsScreen
      railWidget.onDestinationSelected!(3);
      await tester.pumpAndSettle();
      
      expect(find.byType(AdminGeofenceScreen), findsOneWidget,
        reason: 'Index 3 should show Geofences screen but currently shows Client Tickets screen - this confirms the navigation order bug exists');
      
      // Test index 4 should show Reports (AdminReportsHubScreen) - WILL FAIL because it currently shows ManageAdminsScreen
      railWidget.onDestinationSelected!(4);
      await tester.pumpAndSettle();
      
      expect(find.byType(AdminReportsHubScreen), findsOneWidget,
        reason: 'Index 4 should show Reports screen but currently shows Admins screen - this confirms the navigation order bug exists');
      
      // Test index 5 should show Settings (AdminSettingsScreen) - WILL FAIL because it currently shows AdminGeofenceScreen
      railWidget.onDestinationSelected!(5);
      await tester.pumpAndSettle();
      
      expect(find.byType(AdminSettingsScreen), findsOneWidget,
        reason: 'Index 5 should show Settings screen but currently shows Geofences screen - this confirms the navigation order bug exists');
      
      // Test index 6 should show Tasks (AdminTaskManagementScreen) - WILL FAIL because it currently shows AdminSettingsScreen
      railWidget.onDestinationSelected!(6);
      await tester.pumpAndSettle();
      
      expect(find.byType(AdminTaskManagementScreen), findsOneWidget,
        reason: 'Index 6 should show Tasks screen but currently shows Settings screen - this confirms the navigation order bug exists');
    });

    testWidgets('EXPECTED TO FAIL: Mobile devices show BottomNavigationBar instead of hamburger drawer menu', (WidgetTester tester) async {
      // Set mobile screen size (width < 600)
      await tester.binding.setSurfaceSize(const Size(400, 800));
      
      await tester.pumpWidget(testApp);
      await tester.pumpAndSettle();

      // On mobile, we should have a Drawer (hamburger menu) but currently have BottomNavigationBar
      // This assertion WILL FAIL on unfixed code
      expect(find.byType(Drawer), findsOneWidget,
        reason: 'Mobile layout should show hamburger Drawer but currently shows BottomNavigationBar - this confirms the mobile menu bug exists');
      
      // Verify BottomNavigationBar should NOT exist on mobile (this will PASS, confirming the bug)
      expect(find.byType(BottomNavigationBar), findsNothing,
        reason: 'Mobile layout should NOT show BottomNavigationBar but should show Drawer instead');
      
      // The drawer should contain all 7 navigation items plus logout
      final scaffold = find.byType(Scaffold);
      expect(scaffold, findsOneWidget);
      
      // Try to open drawer (this will FAIL because drawer doesn't exist)
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      
      // Drawer should contain navigation items for all screens
      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.text('Employees'), findsOneWidget);
      expect(find.text('Admins'), findsOneWidget);
      expect(find.text('Geofences'), findsOneWidget);
      expect(find.text('Reports'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Tasks'), findsOneWidget);
      expect(find.text('Logout'), findsOneWidget);
    });

    testWidgets('EXPECTED TO FAIL: Keyboard shortcuts (Ctrl+1-7) point to wrong destinations due to incorrect order', (WidgetTester tester) async {
      // Set desktop screen size
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      
      await tester.pumpWidget(testApp);
      await tester.pumpAndSettle();

      // Test keyboard shortcuts - these should map to the EXPECTED navigation order
      // but will FAIL because the current order is wrong
      
      // Ctrl+3 should navigate to Admins (index 2 in expected order)
      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.digit3);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.digit3);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await tester.pumpAndSettle();
      
      // This WILL FAIL because Ctrl+3 currently goes to index 2 which shows Reports instead of Admins
      expect(find.byType(ManageAdminsScreen), findsOneWidget,
        reason: 'Ctrl+3 should show Admins screen but currently shows Reports screen due to incorrect navigation order');
      
      // Ctrl+4 should navigate to Geofences (index 3 in expected order)
      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.digit4);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.digit4);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await tester.pumpAndSettle();
      
      // This WILL FAIL because Ctrl+4 currently goes to index 3 which shows Client Tickets instead of Geofences
      expect(find.byType(AdminGeofenceScreen), findsOneWidget,
        reason: 'Ctrl+4 should show Geofences screen but currently shows Client Tickets screen due to incorrect navigation order');
      
      // Ctrl+5 should navigate to Reports (index 4 in expected order)
      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.digit5);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.digit5);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await tester.pumpAndSettle();
      
      // This WILL FAIL because Ctrl+5 currently goes to index 4 which shows Admins instead of Reports
      expect(find.byType(AdminReportsHubScreen), findsOneWidget,
        reason: 'Ctrl+5 should show Reports screen but currently shows Admins screen due to incorrect navigation order');
      
      // Ctrl+6 should navigate to Settings (index 5 in expected order)
      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.digit6);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.digit6);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await tester.pumpAndSettle();
      
      // This WILL FAIL because Ctrl+6 currently goes to index 5 which shows Geofences instead of Settings
      expect(find.byType(AdminSettingsScreen), findsOneWidget,
        reason: 'Ctrl+6 should show Settings screen but currently shows Geofences screen due to incorrect navigation order');
      
      // Ctrl+7 should navigate to Tasks (index 6 in expected order)
      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.digit7);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.digit7);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await tester.pumpAndSettle();
      
      // This WILL FAIL because Ctrl+7 currently goes to index 6 which shows Settings instead of Tasks
      expect(find.byType(AdminTaskManagementScreen), findsOneWidget,
        reason: 'Ctrl+7 should show Tasks screen but currently shows Settings screen due to incorrect navigation order');
    });

    testWidgets('Property-Based Test: Navigation Order Bug Condition', (WidgetTester tester) async {
      // Set desktop screen size
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      
      await tester.pumpWidget(testApp);
      await tester.pumpAndSettle();

      // Property: For desktop navigation, the destination order should be [Dashboard, Employees, Admins, Geofences, Reports, Settings, Tasks]
      final expectedOrder = [
        'Dashboard',     // index 0 - should show _buildDashboardOverview()
        'Employees',     // index 1 - should show ManageEmployeesScreen
        'Admins',        // index 2 - should show ManageAdminsScreen
        'Geofences',     // index 3 - should show AdminGeofenceScreen  
        'Reports',       // index 4 - should show AdminReportsHubScreen
        'Settings',      // index 5 - should show AdminSettingsScreen
        'Tasks',         // index 6 - should show AdminTaskManagementScreen
      ];

      // Test each navigation index to verify it shows the expected screen
      for (int i = 1; i < expectedOrder.length; i++) { // Skip index 0 (Dashboard) as it's the default
        final navigationRail = find.byType(NavigationRail);
        final railWidget = tester.widget<NavigationRail>(navigationRail);
        
        // Navigate to index i
        railWidget.onDestinationSelected!(i);
        await tester.pumpAndSettle();
        
        // Verify the correct screen is shown based on expected order
        switch (i) {
          case 1: // Should be Employees
            expect(find.byType(ManageEmployeesScreen), findsOneWidget,
              reason: 'Index 1 should show Employees screen');
            break;
          case 2: // Should be Admins - WILL FAIL (currently shows Reports)
            expect(find.byType(ManageAdminsScreen), findsOneWidget,
              reason: 'Index 2 should show Admins screen but shows ${_getCurrentScreenType(tester)} - navigation order bug confirmed');
            break;
          case 3: // Should be Geofences - WILL FAIL (currently shows Client Tickets)
            expect(find.byType(AdminGeofenceScreen), findsOneWidget,
              reason: 'Index 3 should show Geofences screen but shows ${_getCurrentScreenType(tester)} - navigation order bug confirmed');
            break;
          case 4: // Should be Reports - WILL FAIL (currently shows Admins)
            expect(find.byType(AdminReportsHubScreen), findsOneWidget,
              reason: 'Index 4 should show Reports screen but shows ${_getCurrentScreenType(tester)} - navigation order bug confirmed');
            break;
          case 5: // Should be Settings - WILL FAIL (currently shows Geofences)
            expect(find.byType(AdminSettingsScreen), findsOneWidget,
              reason: 'Index 5 should show Settings screen but shows ${_getCurrentScreenType(tester)} - navigation order bug confirmed');
            break;
          case 6: // Should be Tasks - WILL FAIL (currently shows Settings)
            expect(find.byType(AdminTaskManagementScreen), findsOneWidget,
              reason: 'Index 6 should show Tasks screen but shows ${_getCurrentScreenType(tester)} - navigation order bug confirmed');
            break;
        }
      }
    });

    testWidgets('Property-Based Test: Mobile Menu Bug Condition', (WidgetTester tester) async {
      // Test various mobile screen sizes
      final mobileSizes = [
        const Size(320, 568), // iPhone SE
        const Size(375, 667), // iPhone 8
        const Size(414, 896), // iPhone 11
        const Size(360, 640), // Android small
        const Size(412, 915), // Android large
      ];

      for (final size in mobileSizes) {
        await tester.binding.setSurfaceSize(size);
        
        await tester.pumpWidget(testApp);
        await tester.pumpAndSettle();

        // Property: For mobile screens (width < 600), should show Drawer instead of BottomNavigationBar
        if (size.width < 600) {
          // This WILL FAIL on unfixed code - mobile should have Drawer but currently has BottomNavigationBar
          expect(find.byType(Drawer), findsOneWidget,
            reason: 'Mobile screen size ${size.width}x${size.height} should show Drawer but shows BottomNavigationBar - mobile menu bug confirmed');
          
          expect(find.byType(BottomNavigationBar), findsNothing,
            reason: 'Mobile screen size ${size.width}x${size.height} should NOT show BottomNavigationBar');
        }
      }
    });
  });
}

/// Helper function to get the current screen type for debugging
String _getCurrentScreenType(WidgetTester tester) {
  if (tester.any(find.byType(ManageEmployeesScreen))) return 'ManageEmployeesScreen';
  if (tester.any(find.byType(AdminReportsHubScreen))) return 'AdminReportsHubScreen';
  if (tester.any(find.byType(ClientTicketsScreen))) return 'ClientTicketsScreen';
  if (tester.any(find.byType(ManageAdminsScreen))) return 'ManageAdminsScreen';
  if (tester.any(find.byType(AdminGeofenceScreen))) return 'AdminGeofenceScreen';
  if (tester.any(find.byType(AdminSettingsScreen))) return 'AdminSettingsScreen';
  if (tester.any(find.byType(AdminTaskManagementScreen))) return 'AdminTaskManagementScreen';
  return 'Unknown';
}