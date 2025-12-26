// ignore_for_file: library_private_types_in_public_api
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:field_check/providers/auth_provider.dart';
import 'package:field_check/screens/login_screen.dart';
import 'package:field_check/screens/splash_screen.dart';
import 'package:field_check/services/realtime_service.dart';
import 'package:field_check/services/autosave_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:field_check/services/sync_service.dart';
import 'package:field_check/screens/dashboard_screen.dart';
import 'package:field_check/screens/registration_screen.dart';
import 'package:field_check/screens/forgot_password_screen.dart';
import 'package:field_check/screens/reset_password_screen.dart';
import 'package:field_check/screens/admin_dashboard_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:field_check/utils/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize only essential services immediately
  final syncService = SyncService();
  final autosaveService = AutosaveService();
  
  // Initialize essential services only
  await autosaveService.initialize();
  
  runApp(MyApp(
    syncService: syncService,
    realtimeService: RealtimeService(), // Don't initialize yet
    autosaveService: autosaveService,
  ));
}

class MyApp extends StatefulWidget {
  final SyncService syncService;
  final RealtimeService realtimeService;
  final AutosaveService autosaveService;
  const MyApp({
    super.key, 
    required this.syncService,
    required this.realtimeService,
    required this.autosaveService,
  });

  static MyAppState? of(BuildContext context) =>
      context.findAncestorStateOfType<MyAppState>();

  @override
  State<MyApp> createState() => MyAppState();
}

class MyAppState extends State<MyApp> {
  late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;
  ThemeMode _themeMode = ThemeMode.light;

  ThemeData _lightTheme() => AppTheme.lightTheme;

  ThemeData _darkTheme() => AppTheme.darkTheme;

  Future<void> _loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('user.themeMode');
    ThemeMode mode;
    switch (saved) {
      case 'dark':
        mode = ThemeMode.dark;
        break;
      case 'light':
        mode = ThemeMode.light;
        break;
      case 'system':
        mode = ThemeMode.system;
        break;
      default:
        mode = ThemeMode.light;
    }
    if (mounted) {
      setState(() => _themeMode = mode);
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user.themeMode', mode.toString().split('.').last);
    if (mounted) {
      setState(() => _themeMode = mode);
    }
  }

  void toggleTheme() {
    final next = _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    setThemeMode(next);
  }

  ThemeMode get themeMode => _themeMode;

  @override
  void initState() {
    super.initState();
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(_updateConnectionStatus);
    _loadThemeMode();
  }

  Future<void> _updateConnectionStatus(List<ConnectivityResult> results) async {
    final isOnline = results.isNotEmpty && !results.contains(ConnectivityResult.none);
    if (isOnline) {
      // Initialize realtime service only when online and needed
      if (!widget.realtimeService.isConnected) {
        await widget.realtimeService.initialize();
      }
      widget.syncService.syncOfflineData();
    }
  }

  @override
  void dispose() {
    _connectivitySubscription.cancel();
    widget.realtimeService.dispose();
    widget.autosaveService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'FieldCheck',
        theme: _lightTheme(),
        darkTheme: _darkTheme(),
        themeMode: _themeMode,
        home: const SplashScreen(),
        routes: {
          '/login': (context) => const LoginScreen(),
          '/register': (context) => const RegistrationScreen(),
          '/forgot-password': (context) => const ForgotPasswordScreen(),
          '/reset-password': (context) => const ResetPasswordScreen(),
          '/admin-dashboard': (context) => const AdminDashboardScreen(),
        },
        onGenerateRoute: (settings) {
          if (settings.name == '/dashboard') {
            final int? initialIndex = settings.arguments as int?;
            return MaterialPageRoute(
              builder: (context) => DashboardScreen(initialIndex: initialIndex),
            );
          }
          return null;
        },
      ),
    );
  }
}
