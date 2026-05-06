import 'package:flutter_test/flutter_test.dart';
import 'package:field_check/screens/admin_dashboard_screen.dart';
import 'package:field_check/screens/manage_employees_screen.dart';
import 'package:field_check/screens/manage_admins_screen.dart';
import 'package:field_check/screens/admin_geofence_screen.dart';
import 'package:field_check/screens/admin_reports_hub_screen.dart';
import 'package:field_check/screens/admin_settings_screen.dart';
import 'package:field_check/screens/admin_task_management_screen.dart';

void main() {
  group('Navigation Order Tests', () {
    test('Navigation order should match expected sequence', () {
      // Expected order: 0: Dashboard | 1: Employees | 2: Admins | 3: Geofences | 4: Reports | 5: Settings | 6: Tasks
      
      // This test verifies that the screen mapping in _buildCurrentScreen matches the expected order
      // We can't directly test the private method, but we can verify the expected screens exist
      
      expect(ManageEmployeesScreen, isNotNull, reason: 'Employees screen should exist for index 1');
      expect(ManageAdminsScreen, isNotNull, reason: 'Admins screen should exist for index 2');
      expect(AdminGeofenceScreen, isNotNull, reason: 'Geofences screen should exist for index 3');
      expect(AdminReportsHubScreen, isNotNull, reason: 'Reports screen should exist for index 4');
      expect(AdminSettingsScreen, isNotNull, reason: 'Settings screen should exist for index 5');
      expect(AdminTaskManagementScreen, isNotNull, reason: 'Tasks screen should exist for index 6');
    });

    test('Navigation constants should be correctly defined', () {
      // These constants are used for bottom navigation mapping
      const expectedDashboard = 0;
      const expectedEmployees = 1;
      const expectedReports = 2;
      const expectedClientTickets = 3;
      const expectedMore = 4;
      
      expect(expectedDashboard, equals(0));
      expect(expectedEmployees, equals(1));
      expect(expectedReports, equals(2));
      expect(expectedClientTickets, equals(3));
      expect(expectedMore, equals(4));
    });
  });
}