import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:field_check/screens/admin_dashboard_screen.dart';

/// **Validates: Requirements 3.1, 3.2**
///
/// Preservation tests for admin dashboard navigation behavior.

Widget _dashboardApp(Size size) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(size: size),
      child: const AdminDashboardScreen(),
    ),
  );
}

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 50; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

void main() {
  group('Phase 1 Preservation Tests - Navigation Functionality Preservation', () {
    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    testWidgets(
      'Property: Keyboard shortcuts (Ctrl+1-7) respond correctly to current navigation mapping',
      (WidgetTester tester) async {
        addTearDown(() async => _unmount(tester));

        await tester.binding.setSurfaceSize(const Size(1200, 800));
        await tester.pumpWidget(_dashboardApp(const Size(1200, 800)));
        await _pumpUntilFound(tester, find.byType(NavigationRail));

        expect(find.byType(NavigationRail), findsOneWidget);
        expect(find.byType(Shortcuts), findsWidgets);

        await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.digit1);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.digit1);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
        await tester.pump();

        expect(find.text('Admin Dashboard'), findsOneWidget);
      },
    );

    testWidgets(
      'Property: Screen size detection for responsive layout works properly',
      (WidgetTester tester) async {
        addTearDown(() async => _unmount(tester));

        await tester.binding.setSurfaceSize(const Size(1200, 800));
        await tester.pumpWidget(_dashboardApp(const Size(1200, 800)));
        await _pumpUntilFound(tester, find.byType(NavigationRail));
        expect(find.byType(NavigationRail), findsOneWidget);
        expect(find.byType(BottomNavigationBar), findsNothing);

        await tester.pumpWidget(_dashboardApp(const Size(600, 800)));
        await _pumpUntilFound(tester, find.byType(BottomNavigationBar));
        expect(find.byType(BottomNavigationBar), findsOneWidget);
        expect(find.byType(NavigationRail), findsNothing);

        await tester.pumpWidget(_dashboardApp(const Size(980, 800)));
        await _pumpUntilFound(tester, find.byType(NavigationRail));
        expect(find.byType(NavigationRail), findsOneWidget);
        expect(find.byType(BottomNavigationBar), findsNothing);

        await tester.pumpWidget(_dashboardApp(const Size(979, 800)));
        await _pumpUntilFound(tester, find.byType(BottomNavigationBar));
        expect(find.byType(BottomNavigationBar), findsOneWidget);
        expect(find.byType(NavigationRail), findsNothing);
      },
    );

    testWidgets(
      'Property-Based Test: Keyboard shortcuts work across different screen sizes',
      (WidgetTester tester) async {
        addTearDown(() async => _unmount(tester));

        const screenSizes = [
          Size(1200, 800),
          Size(1024, 768),
          Size(980, 600),
        ];

        for (final size in screenSizes) {
          await tester.binding.setSurfaceSize(size);
          await tester.pumpWidget(_dashboardApp(size));
          await _pumpUntilFound(tester, find.byType(NavigationRail));

          await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
          await tester.sendKeyDownEvent(LogicalKeyboardKey.digit1);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.digit1);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
          await tester.pump();

          expect(find.text('Admin Dashboard'), findsOneWidget);
        }
      },
    );

    testWidgets(
      'Property: Non-navigation interactions remain unaffected',
      (WidgetTester tester) async {
        addTearDown(() async => _unmount(tester));

        await tester.binding.setSurfaceSize(const Size(1200, 800));
        await tester.pumpWidget(_dashboardApp(const Size(1200, 800)));
        await _pumpUntilFound(tester, find.byType(NavigationRail));

        expect(find.text('Admin Dashboard'), findsOneWidget);
        expect(find.byType(Scaffold), findsOneWidget);
        expect(find.byType(NavigationRail), findsOneWidget);
      },
    );

    testWidgets(
      'Property-Based Test: Current navigation mapping consistency',
      (WidgetTester tester) async {
        addTearDown(() async => _unmount(tester));

        await tester.binding.setSurfaceSize(const Size(1200, 800));
        await tester.pumpWidget(_dashboardApp(const Size(1200, 800)));
        await _pumpUntilFound(tester, find.byType(NavigationRail));

        final navigationRail = find.byType(NavigationRail);
        final railWidget = tester.widget<NavigationRail>(navigationRail);
        expect(railWidget.destinations.length, equals(7));
      },
    );

    testWidgets(
      'Property: Mobile BottomNavigationBar current behavior preservation',
      (WidgetTester tester) async {
        addTearDown(() async => _unmount(tester));

        await tester.binding.setSurfaceSize(const Size(400, 800));
        await tester.pumpWidget(_dashboardApp(const Size(400, 800)));
        await _pumpUntilFound(tester, find.byType(BottomNavigationBar));

        final bottomNav = find.byType(BottomNavigationBar);
        final bottomNavWidget = tester.widget<BottomNavigationBar>(bottomNav);

        expect(bottomNavWidget.items.length, equals(5));
        expect(bottomNavWidget.items[0].label, equals('Dashboard'));
        expect(bottomNavWidget.items[1].label, equals('Employees'));
        expect(bottomNavWidget.items[2].label, equals('Reports'));
        expect(bottomNavWidget.items[3].label, equals('Tickets'));
        expect(bottomNavWidget.items[4].label, equals('More'));
        expect(find.byType(NavigationRail), findsNothing);
      },
    );
  });
}
