import 'dart:async';
import 'package:flutter/material.dart';
import 'package:field_check/screens/admin_geofence_screen.dart';
import 'package:field_check/screens/admin_reports_screen.dart';
import 'package:field_check/screens/admin_settings_screen.dart';
import 'package:field_check/screens/admin_task_management_screen.dart';
import 'package:field_check/screens/login_screen.dart';
import 'package:field_check/services/user_service.dart';
import 'package:field_check/services/dashboard_service.dart';
import 'package:field_check/services/realtime_service.dart';
import 'package:field_check/models/dashboard_model.dart';
import 'package:intl/intl.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  int _selectedIndex = 0;
  final UserService _userService = UserService();
  final DashboardService _dashboardService = DashboardService();
  final RealtimeService _realtimeService = RealtimeService();
  
  DashboardStats? _dashboardStats;
  RealtimeUpdates? _realtimeUpdates;
  bool _isLoading = true;
  Timer? _refreshTimer;
  bool _isFetchingRealtime = false;

  List<Widget> get _screens => [
    _buildDashboardOverview(),
    const AdminGeofenceScreen(),
    const AdminReportsScreen(),
    const AdminSettingsScreen(),
    const AdminTaskManagementScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
    _initRealtimeService();
    _startRefreshTimer();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _initRealtimeService() async {
    await _realtimeService.initialize();
    
    // Listen for real-time updates
    _realtimeService.attendanceStream.listen((event) {
      if (mounted) {
        _loadRealtimeUpdates();
      }
    });

    _realtimeService.taskStream.listen((event) {
      if (mounted) {
        _loadDashboardData();
      }
    });

    _realtimeService.onlineCountStream.listen((count) {
      if (mounted) {
        final current = _realtimeUpdates;
        setState(() {
          _realtimeUpdates = RealtimeUpdates(
            onlineUsers: count,
            recentCheckIns: current?.recentCheckIns ?? [],
            pendingTasksToday: current?.pendingTasksToday ?? [],
            timestamp: DateTime.now(),
          );
        });
      }
    });
  }

  void _startRefreshTimer() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_selectedIndex == 0 && !_isFetchingRealtime) {
        _loadRealtimeUpdates();
      }
    });
  }

  Future<void> _loadDashboardData() async {
    try {
      final stats = await _dashboardService.getDashboardStats();
      final realtime = await _dashboardService.getRealtimeUpdates();
      setState(() {
        _dashboardStats = stats;
        _realtimeUpdates = realtime;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading dashboard data: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadRealtimeUpdates() async {
    if (_isFetchingRealtime) return;
    _isFetchingRealtime = true;
    try {
      final realtime = await _dashboardService.getRealtimeUpdates();
      if (mounted) {
        setState(() {
          _realtimeUpdates = realtime;
        });
      }
    } catch (e) {
      debugPrint('Error loading realtime updates: $e');
    } finally {
      _isFetchingRealtime = false;
    }
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    const brandColor = Color(0xFF2688d4);
    return Scaffold(
      appBar: AppBar(
        leading: _selectedIndex != 0
            ? BackButton(onPressed: () {
                setState(() {
                  _selectedIndex = 0;
                });
              })
            : null,
        title: Text(_getAppBarTitle()),
        backgroundColor: brandColor,
        actions: [
          if (_selectedIndex == 0)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadDashboardData,
            ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await _userService.logout();
              if (!mounted) return;
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => const LoginScreen()),
                (route) => false,
              );
            },
          ),
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: _screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        backgroundColor: const Color(0xFFF5F7FA),
        showUnselectedLabels: true,
        selectedItemColor: brandColor,
        unselectedItemColor: Colors.grey.shade600,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
        selectedIconTheme: const IconThemeData(color: brandColor, size: 28),
        unselectedIconTheme: const IconThemeData(size: 24),
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.map),
            label: 'Geofences',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.assessment),
            label: 'Reports',
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
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
      ),
    );
  }

  String _getAppBarTitle() {
    switch (_selectedIndex) {
      case 0:
        return 'Admin Dashboard';
      case 1:
        return 'Geofence Management';
      case 2:
        return 'Reports & Analytics';
      case 3:
        return 'System Settings';
      case 4:
        return 'Task Management';
      default:
        return 'Admin Dashboard';
    }
  }

  Widget _buildDashboardOverview() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_dashboardStats == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('Failed to load dashboard data'),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadDashboardData,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Real-time status indicator
            if (_realtimeUpdates != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.wifi, color: Colors.green.shade600),
                    const SizedBox(width: 8),
                    Text(
                      'Live Updates Active • ${_realtimeUpdates!.onlineUsers} Online',
                      style: TextStyle(
                        color: Colors.green.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            
            const SizedBox(height: 20),
            
            // Statistics Cards
            _buildStatsGrid(),
            
            const SizedBox(height: 24),
            
            // Recent Activities
            _buildRecentActivities(),
            
            const SizedBox(height: 24),
            
            // Quick Actions
            _buildQuickActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsGrid() {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      childAspectRatio: 1.5,
      children: [
        _buildStatCard(
          title: 'Total Employees',
          value: _dashboardStats!.users.totalEmployees.toString(),
          icon: Icons.people,
          color: Colors.blue,
          subtitle: '${_dashboardStats!.users.activeEmployees} active',
        ),
        _buildStatCard(
          title: 'Geofences',
          value: _dashboardStats!.geofences.total.toString(),
          icon: Icons.location_on,
          color: Colors.green,
          subtitle: '${_dashboardStats!.geofences.active} active',
        ),
        _buildStatCard(
          title: 'Tasks',
          value: _dashboardStats!.tasks.total.toString(),
          icon: Icons.task,
          color: Colors.orange,
          subtitle: '${_dashboardStats!.tasks.pending} pending',
        ),
        _buildStatCard(
          title: 'Today\'s Attendance',
          value: _dashboardStats!.attendance.today.toString(),
          icon: Icons.check_circle,
          color: Colors.purple,
          subtitle: '${_dashboardStats!.attendance.todayCheckIns} check-ins',
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    String? subtitle,
  }) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, color: color, size: 24),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRecentActivities() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Recent Activities',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            if (_dashboardStats!.recentActivities.attendances.isNotEmpty) ...[
              const Text(
                'Recent Check-ins',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 8),
              ...(_dashboardStats!.recentActivities.attendances.take(3).map(
                (attendance) => ListTile(
                  dense: true,
                  leading: const CircleAvatar(
                    radius: 16,
                    child: Icon(Icons.person, size: 16),
                  ),
                  title: Text(attendance.userName),
                  subtitle: Text(attendance.geofenceName),
                  trailing: Text(
                    DateFormat('HH:mm').format(attendance.timestamp),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              )),
            ],
            if (_dashboardStats!.recentActivities.tasks.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text(
                'Recent Tasks',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 8),
              ...(_dashboardStats!.recentActivities.tasks.take(3).map(
                (task) => ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor: _getTaskStatusColor(task.status),
                    child: const Icon(Icons.task, size: 16, color: Colors.white),
                  ),
                  title: Text(task.title),
                  subtitle: Text(task.assignedToName ?? 'Unassigned'),
                  trailing: Text(
                    DateFormat('MMM dd').format(task.createdAt),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              )),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActions() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Quick Actions',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildQuickActionButton(
                    icon: Icons.person_add,
                    label: 'Add Employee',
                    color: Colors.blue,
                    onTap: () {
                      // Navigate to add employee
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Navigate to Add Employee')),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildQuickActionButton(
                    icon: Icons.location_on,
                    label: 'Add Geofence',
                    color: Colors.green,
                    onTap: () {
                      setState(() {
                        _selectedIndex = 1; // Geofences tab
                      });
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildQuickActionButton(
                    icon: Icons.task,
                    label: 'Create Task',
                    color: Colors.orange,
                    onTap: () {
                      setState(() {
                        _selectedIndex = 4; // Tasks tab
                      });
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildQuickActionButton(
                    icon: Icons.assessment,
                    label: 'View Reports',
                    color: Colors.purple,
                    onTap: () {
                      setState(() {
                        _selectedIndex = 2; // Reports tab
                      });
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w500,
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Color _getTaskStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return Colors.green;
      case 'in_progress':
        return Colors.orange;
      case 'pending':
        return Colors.grey;
      default:
        return Colors.blue;
    }
  }
}