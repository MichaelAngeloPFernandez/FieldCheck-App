import 'package:flutter/material.dart';
import 'package:field_check/screens/enhanced_attendance_screen.dart';
import 'package:field_check/screens/history_screen.dart';
import 'package:field_check/screens/map_screen.dart';
import 'package:field_check/screens/settings_screen.dart';
import 'package:field_check/screens/employee_task_list_screen.dart';
import 'package:field_check/screens/login_screen.dart';
import 'package:field_check/services/user_service.dart';
import 'package:field_check/services/realtime_service.dart';
import 'package:field_check/services/autosave_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

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
      final profile = await _userService.getProfile();
      if (!mounted) return;
      setState(() {
        _userModelId = profile.id;
        _loadingUserId = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingUserId = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> screens = [
      const EnhancedAttendanceScreen(),
      const MapScreen(),
      const HistoryScreen(),
      const SettingsScreen(),
      _loadingUserId
          ? const Center(child: CircularProgressIndicator())
          : (_userModelId == null
                ? const Center(child: Text('Failed to load user ID'))
                : EmployeeTaskListScreen(userModelId: _userModelId!)),
    ];

    return Scaffold(
      appBar: AppBar(
        leading: _selectedIndex != 0
            ? BackButton(onPressed: () {
                setState(() {
                  _selectedIndex = 0;
                });
              })
            : null,
        title: const Text('FieldCheck'),
        actions: [
          if (_isOfflineMode)
            const Padding(
              padding: EdgeInsets.only(right: 16.0),
              child: Icon(Icons.cloud_off, color: Colors.white),
            ),
          IconButton(
            tooltip: 'Logout',
            icon: const Icon(Icons.logout),
            onPressed: () async {
              try {
                await _userService.logout();
              } catch (_) {}
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
          setState(() {
            _selectedIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.location_on),
            label: 'Attendance',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.map),
            label: 'Map',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history),
            label: 'History',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.task),
            label: 'Tasks',
          ),
        ],
      ),
    );
  }
}