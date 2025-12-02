// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:field_check/screens/enhanced_attendance_screen.dart';
import 'package:field_check/screens/history_screen.dart';
import 'package:field_check/screens/map_screen.dart';
import 'package:field_check/screens/settings_screen.dart';
import 'package:field_check/screens/employee_task_list_screen.dart';
import 'package:field_check/screens/employee_profile_screen.dart';
import 'package:field_check/screens/login_screen.dart';
import 'package:field_check/services/user_service.dart';
import 'package:field_check/services/realtime_service.dart';
import 'package:field_check/services/autosave_service.dart';
import 'package:field_check/utils/app_theme.dart';
import 'package:field_check/utils/logger.dart';
import 'package:field_check/widgets/app_widgets.dart';

class DashboardScreen extends StatefulWidget {
  final int? initialIndex;
  
  const DashboardScreen({super.key, this.initialIndex});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;
  final bool _isOfflineMode = false;
  final UserService _userService = UserService();
  final RealtimeService _realtimeService = RealtimeService();
  final AutosaveService _autosaveService = AutosaveService();
  String? _userModelId;
  bool _loadingUserId = true;

  @override
  void initState() {
    super.initState();
    // Set initial index if provided (from drawer navigation)
    if (widget.initialIndex != null) {
      _selectedIndex = widget.initialIndex!;
    }
    _loadUserId();
    _initServices();
  }

  Future<void> _initServices() async {
    await _realtimeService.initialize();
    await _autosaveService.initialize();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadUserId() async {
    try {
      AppLogger.info(AppLogger.tagUI, 'Loading user profile...');
      final profile = await _userService.getProfile();
      if (!mounted) return;
      setState(() {
        _userModelId = profile.id;
        _loadingUserId = false;
      });
      AppLogger.success(AppLogger.tagUI, 'User profile loaded: ${profile.id}');
    } catch (e) {
      AppLogger.error(AppLogger.tagUI, 'Failed to load user profile', e);
      if (!mounted) return;
      setState(() {
        _loadingUserId = false;
      });
    }
  }

  // Navigation labels for better debugging
  static const List<String> _navLabels = [
    'Attendance',
    'Map',
    'Profile',
    'History',
    'Settings',
    'Tasks',
  ];

  @override
  Widget build(BuildContext context) {
    final List<Widget> screens = [
      const EnhancedAttendanceScreen(),
      const MapScreen(),
      const EmployeeProfileScreen(),
      const HistoryScreen(),
      const SettingsScreen(),
      _loadingUserId
          ? AppWidgets.loadingIndicator(message: 'Loading tasks...')
          : (_userModelId == null
                ? AppWidgets.emptyState(
                    title: 'Error',
                    message: 'Failed to load user information',
                    icon: Icons.error_outline,
                  )
                : EmployeeTaskListScreen(userModelId: _userModelId!)),
    ];

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        leading: _selectedIndex != 0
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back to Attendance',
                onPressed: () {
                  AppLogger.info(AppLogger.tagNavigation, 'Navigating back to Attendance');
                  setState(() {
                    _selectedIndex = 0;
                  });
                },
              )
            : null,
        title: Text(
          _navLabels[_selectedIndex],
          style: AppTheme.headingSm,
        ),
        actions: [
          if (_isOfflineMode)
            Tooltip(
              message: 'Offline mode - changes will sync when online',
              child: Padding(
                padding: const EdgeInsets.only(right: AppTheme.lg),
                child: Center(
                  child: Row(
                    children: [
                      const Icon(Icons.cloud_off, size: 20),
                      const SizedBox(width: AppTheme.sm),
                      Text(
                        'Offline',
                        style: AppTheme.labelMd.copyWith(color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          IconButton(
            tooltip: 'Logout',
            icon: const Icon(Icons.logout),
            onPressed: () async {
              AppLogger.info(AppLogger.tagAuth, 'User logout initiated');
              try {
                await _userService.logout();
              } catch (e) {
                AppLogger.warning(AppLogger.tagAuth, 'Logout error (non-critical)', e);
              }
              if (!mounted) return;
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
            },
          ),
        ],
      ),
      body: IndexedStack(index: _selectedIndex, children: screens),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          AppLogger.debug(
            AppLogger.tagNavigation,
            'Navigation: ${_navLabels[_selectedIndex]} → ${_navLabels[index]}',
          );
          setState(() {
            _selectedIndex = index;
          });
        },
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.location_on),
            label: 'Attendance',
            tooltip: 'Check in/out',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.map),
            label: 'Map',
            tooltip: 'View geofences',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Profile',
            tooltip: 'User profile',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history),
            label: 'History',
            tooltip: 'Attendance history',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
            tooltip: 'App settings',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.task),
            label: 'Tasks',
            tooltip: 'Task list',
          ),
        ],
      ),
    );
  }
}
