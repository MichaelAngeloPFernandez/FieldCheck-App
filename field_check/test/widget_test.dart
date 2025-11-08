import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:field_check/main.dart';
import 'package:field_check/services/sync_service.dart';
import 'package:field_check/services/realtime_service.dart';
import 'package:field_check/services/autosave_service.dart';
import 'package:field_check/screens/login_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Routes to Login when no auth token', (WidgetTester tester) async {
    // Ensure SharedPreferences has no token
    SharedPreferences.setMockInitialValues(<String, Object>{});

    // Pump the app with all required services
    await tester.pumpWidget(MyApp(
      syncService: SyncService(),
      realtimeService: RealtimeService(),
      autosaveService: AutosaveService(),
    ));

    // Allow routing decisions to settle
    await tester.pumpAndSettle();

    // Verify Login screen is shown
    expect(find.byType(LoginScreen), findsOneWidget);
  });
}
