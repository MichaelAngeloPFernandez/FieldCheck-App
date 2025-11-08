import 'dart:async';
import 'package:flutter/material.dart';
import 'package:field_check/screens/login_screen.dart';
import 'package:field_check/services/geofence_service.dart';
import 'package:field_check/services/realtime_service.dart';
import 'package:field_check/services/autosave_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:field_check/services/sync_service.dart';
import 'package:field_check/screens/dashboard_screen.dart';
import 'package:field_check/screens/registration_screen.dart';
import 'package:field_check/screens/forgot_password_screen.dart';
import 'package:field_check/screens/admin_dashboard_screen.dart';
import 'package:field_check/services/user_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize services
  GeofenceService();
  final syncService = SyncService();
  final realtimeService = RealtimeService();
  final autosaveService = AutosaveService();
  
  // Initialize services
  await realtimeService.initialize();
  await autosaveService.initialize();
  
  runApp(MyApp(
    syncService: syncService,
    realtimeService: realtimeService,
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

  static _MyAppState? of(BuildContext context) =>
      context.findAncestorStateOfType<_MyAppState>();

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;
  ThemeMode _themeMode = ThemeMode.light;

  ThemeData _lightTheme() {
    const seed = Color(0xFF2688d4);
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light),
      iconTheme: const IconThemeData(color: seed),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: seed,
          foregroundColor: Colors.white,
          elevation: 2,
        ),
      ),
      visualDensity: VisualDensity.adaptivePlatformDensity,
    );
  }

  ThemeData _darkTheme() {
    const seed = Color(0xFF2688d4);
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark),
      iconTheme: const IconThemeData(color: Colors.white70),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: seed,
          foregroundColor: Colors.white,
          elevation: 2,
        ),
      ),
      visualDensity: VisualDensity.adaptivePlatformDensity,
    );
  }

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
      widget.syncService.syncOfflineData();
    }
  }

  @override
  void dispose() {
    _connectivitySubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'FieldCheck',
        theme: _lightTheme(),
        darkTheme: _darkTheme(),
      themeMode: _themeMode,
      home: const StartupRouter(),
      routes: {
        '/register': (context) => const RegistrationScreen(),
        '/forgot-password': (context) => const ForgotPasswordScreen(),
      },
    );
  }
}

class StartupRouter extends StatefulWidget {
  const StartupRouter({super.key});

  @override
  State<StartupRouter> createState() => _StartupRouterState();
}

class _StartupRouterState extends State<StartupRouter> {
  final _userService = UserService();

  @override
  void initState() {
    super.initState();
    _decideRoute();
  }

  Future<void> _decideRoute() async {
    try {
      final token = await _userService.getToken();
      if (token == null) {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
        return;
      }
      final profile = await _userService.getProfile();
      if (!mounted) return;
      final role = profile.role.toLowerCase();
      if (role == 'admin') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const AdminDashboardScreen()),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const DashboardScreen()),
        );
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
