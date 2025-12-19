// ignore_for_file: use_build_context_synchronously, deprecated_member_use
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:field_check/screens/admin_geofence_screen.dart';
import 'package:field_check/screens/admin_reports_screen.dart';
import 'package:field_check/screens/admin_settings_screen.dart';
import 'package:field_check/screens/admin_task_management_screen.dart';
import 'package:field_check/screens/manage_employees_screen.dart';
import 'package:field_check/screens/manage_admins_screen.dart';
import 'package:field_check/screens/login_screen.dart';
import 'package:field_check/services/user_service.dart';
import 'package:field_check/services/dashboard_service.dart';
import 'package:field_check/services/realtime_service.dart';
import 'package:field_check/services/employee_location_service.dart';
import 'package:field_check/services/report_service.dart';
import 'package:field_check/models/dashboard_model.dart';
import 'package:field_check/models/user_model.dart';
import 'package:field_check/models/report_model.dart';
import 'package:intl/intl.dart';

// Notification model for dashboard alerts
class DashboardNotification {
  final String id;
  final String title;
  final String message;
  final String type; // 'employee', 'task', 'attendance', 'geofence'
  final DateTime timestamp;
  bool isRead;
  final Map<String, dynamic>? data;
  final String? reportId;

  DashboardNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    required this.timestamp,
    this.isRead = false,
    this.data,
    this.reportId,
  });
}

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
  final EmployeeLocationService _locationService = EmployeeLocationService();

  DashboardStats? _dashboardStats;
  RealtimeUpdates? _realtimeUpdates;
  bool _isLoading = true;
  Timer? _refreshTimer;
  bool _isFetchingRealtime = false;

  // Map data
  final Map<String, UserModel> _employees = {};
  final Map<String, LatLng> _liveLocations = {};
  final Map<String, List<LatLng>> _trails = {};
  final Map<String, EmployeeLocation> _employeeLocations = {};
  static const LatLng _defaultCenter = LatLng(14.5995, 120.9842); // Manila
  bool _showNoEmployeesPopup = true;

  // Notification system
  final List<DashboardNotification> _notifications = [];

  List<Widget> get _screens => [
    _buildDashboardOverview(),
    const ManageEmployeesScreen(),
    const ManageAdminsScreen(),
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
    _initMapData();
    _initLocationService();
    _startRefreshTimer();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _locationService.dispose();
    super.dispose();
  }

  Future<void> _initLocationService() async {
    try {
      await _locationService.initialize();
      _locationService.employeeLocationsStream.listen((locations) {
        if (mounted) {
          setState(() {
            _employeeLocations.clear();
            for (final loc in locations) {
              _employeeLocations[loc.employeeId] = loc;
            }
          });
        }
      });
    } catch (e) {
      debugPrint('Error initializing location service: $e');
    }
  }

  Future<void> _initRealtimeService() async {
    await _realtimeService.initialize();

    // Listen for real-time updates
    _realtimeService.attendanceStream.listen((event) {
      if (mounted) {
        _loadDashboardData();
      }
    });

    _realtimeService.taskStream.listen((event) {
      if (mounted) {
        _loadDashboardData();
      }
    });

    _realtimeService.onlineCountStream.listen((count) {
      // Socket-level online count is currently unused; HTTP realtime
      // endpoint provides authoritative employee online counts.
      if (!mounted) {
        return;
      }
    });

    _realtimeService.eventStream.listen((event) {
      if (!mounted) {
        return;
      }

      final type = event['type'] as String? ?? '';
      final action = event['action'] as String? ?? '';
      final Map<String, dynamic>? eventData =
          event['data'] is Map<String, dynamic>
          ? (event['data'] as Map<String, dynamic>)
          : null;

      String title;
      String message;
      String notifType;
      String? reportId;

      // Handle rich adminNotification events
      if (type == 'notification') {
        final data = event['data'] as Map<String, dynamic>? ?? {};
        final srcType = (data['type'] as String? ?? '').toLowerCase();
        final act = (data['action'] as String? ?? action).toLowerCase();
        final employeeName = data['employeeName'] as String? ?? 'Employee';

        notifType = srcType.isNotEmpty ? srcType : 'notification';

        if (srcType == 'presence') {
          if (act == 'login') {
            title = 'Employee logged in';
            message = '$employeeName just logged in.';
          } else if (act == 'online') {
            title = 'Employee online';
            message = '$employeeName is now online.';
          } else if (act == 'logout' || act == 'offline') {
            title = 'Employee offline';
            message = '$employeeName went offline.';
          } else {
            title = 'Presence update';
            message = '$employeeName status changed.';
          }

          // Show a modal dialog for presence events so admin cannot miss them
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(title),
              content: Text(message),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        } else if (srcType == 'attendance') {
          if (act == 'check-in') {
            title = 'Check-in';
            message = '$employeeName checked in.';
          } else if (act == 'check-out') {
            title = 'Check-out';
            message = '$employeeName checked out.';
          } else {
            title = 'Attendance activity';
            message = data['message']?.toString() ?? 'Attendance updated.';
          }
        } else if (srcType == 'task') {
          if (act == 'created') {
            title = 'New task created';
            message = data['message']?.toString() ?? 'A new task was created.';
          } else if (act == 'accepted') {
            title = 'Task accepted';
            message = '$employeeName accepted a task.';
          } else if (act == 'completed') {
            title = 'Task completed';
            message = '$employeeName completed a task.';
          } else {
            title = 'Task updated';
            message = data['message']?.toString() ?? 'Task activity detected.';
          }
        } else if (srcType == 'report') {
          title = 'Report activity';
          message = data['message']?.toString() ?? 'Report activity detected.';
          reportId =
              data['_id']?.toString() ??
              data['id']?.toString() ??
              data['reportId']?.toString();
        } else {
          title = 'Notification';
          message = data['message']?.toString() ?? 'New notification received.';
        }
      } else if (type == 'attendance' || type == 'report') {
        // Backwards-compatible path for legacy events
        notifType = type;
        if (type == 'attendance') {
          if (action == 'new') {
            title = 'Employee check-in';
            message = 'A new check-in was recorded.';
          } else if (action == 'updated') {
            title = 'Employee check-out';
            message = 'An attendance record was updated.';
          } else {
            title = 'Attendance activity';
            message = 'Attendance activity detected.';
          }
        } else {
          if (action == 'new') {
            title = 'New report submitted';
            message = 'A new report was created.';
          } else if (action == 'updated') {
            title = 'Report updated';
            message = 'A report was updated.';
          } else {
            title = 'Report activity';
            message = 'Report activity detected.';
          }

          // Try to capture report id from payload if present
          reportId =
              eventData?['_id']?.toString() ??
              eventData?['id']?.toString() ??
              eventData?['reportId']?.toString();
        }
      } else {
        // Ignore unrelated event types
        return;
      }

      setState(() {
        _notifications.insert(
          0,
          DashboardNotification(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            title: title,
            message: message,
            type: notifType,
            timestamp: DateTime.now(),
            data: eventData,
            reportId: reportId,
          ),
        );
        if (_notifications.length > 50) {
          _notifications.removeLast();
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$title - $message'),
          duration: const Duration(seconds: 4),
        ),
      );
    });
  }

  void _openNotification(DashboardNotification notif) {
    setState(() {
      notif.isRead = true;
    });

    if (notif.type == 'report') {
      final String? reportId = notif.reportId;
      final Map<String, dynamic>? raw = notif.data;

      Future<ReportModel?> resolve() async {
        if (raw != null) {
          try {
            return ReportModel.fromJson(raw);
          } catch (_) {
            // ignore
          }
        }
        if (reportId != null && reportId.isNotEmpty) {
          try {
            return await ReportService().getReportById(reportId);
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Failed to load report: $e')),
              );
            }
          }
        }
        return null;
      }

      resolve().then((model) {
        if (!mounted || model == null) {
          // Fall back: open the reports screen.
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const AdminReportsScreen()));
          return;
        }

        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(model.taskTitle ?? 'Report Details'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDetailRow(
                    'Employee:',
                    (model.employeeName != null &&
                            model.employeeName!.trim().isNotEmpty)
                        ? model.employeeName!
                        : 'Unknown employee',
                  ),
                  if (model.employeeId.trim().isNotEmpty)
                    _buildDetailRow('Employee ID:', model.employeeId),
                  if (model.taskTitle != null)
                    _buildDetailRow('Task:', model.taskTitle!),
                  _buildDetailRow('Status:', model.status),
                  _buildDetailRow(
                    'Submitted:',
                    DateFormat(
                      'yyyy-MM-dd HH:mm',
                    ).format(model.submittedAt.toLocal()),
                  ),
                  if (model.content.isNotEmpty)
                    _buildDetailRow('Content:', model.content),
                  if (model.attachments.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'Attachments:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: model.attachments
                          .map(
                            (path) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: SelectableText(
                                path,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.blueGrey,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const AdminReportsScreen(),
                    ),
                  );
                },
                child: const Text('Open Reports'),
              ),
            ],
          ),
        );
      });

      return;
    }

    // Non-report notifications: keep existing behavior for now.
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
            ? BackButton(
                onPressed: () {
                  setState(() {
                    _selectedIndex = 0;
                  });
                },
              )
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
              try {
                await _userService.markOffline();
              } catch (_) {}

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
      body: IndexedStack(index: _selectedIndex, children: _screens),
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
          BottomNavigationBarItem(icon: Icon(Icons.people), label: 'Employees'),
          BottomNavigationBarItem(
            icon: Icon(Icons.admin_panel_settings),
            label: 'Admins',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Geofences'),
          BottomNavigationBarItem(
            icon: Icon(Icons.assessment),
            label: 'Reports',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.task), label: 'Tasks'),
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
        return 'Manage Employees';
      case 2:
        return 'Manage Administrators';
      case 3:
        return 'Geofence Management';
      case 4:
        return 'Reports & Analytics';
      case 5:
        return 'System Settings';
      case 6:
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

            const SizedBox(height: 12),

            // World Map - Live Employee Tracking
            _buildWorldMapSection(),

            const SizedBox(height: 24),

            // Statistics Cards
            _buildStatsGrid(),

            const SizedBox(height: 24),

            // Recent Activities
            _buildRecentActivities(),

            const SizedBox(height: 24),

            // Quick Actions
            _buildQuickActions(),

            const SizedBox(height: 24),

            // Real-time Notifications
            _buildNotificationsPanel(),
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
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.4,
      children: [
        GestureDetector(
          onTap: _showEmployeeAvailabilityDialog,
          child: _buildStatCard(
            title: 'Total Employees',
            value: _dashboardStats!.users.totalEmployees.toString(),
            icon: Icons.people,
            color: Colors.blue,
            subtitle: '${_dashboardStats!.users.activeEmployees} active',
          ),
        ),
        GestureDetector(
          onTap: _showGeofenceDetailsDialog,
          child: _buildStatCard(
            title: 'Geofences',
            value: _dashboardStats!.geofences.total.toString(),
            icon: Icons.location_on,
            color: Colors.green,
            subtitle: '${_dashboardStats!.geofences.active} active',
          ),
        ),
        GestureDetector(
          onTap: _showTasksDialog,
          child: _buildStatCard(
            title: 'Tasks',
            value: _dashboardStats!.tasks.total.toString(),
            icon: Icons.task,
            color: Colors.orange,
            subtitle: '${_dashboardStats!.tasks.pending} pending',
          ),
        ),
        GestureDetector(
          onTap: _showAttendanceDialog,
          child: _buildStatCard(
            title: 'Today\'s Attendance',
            value: _dashboardStats!.attendance.today.toString(),
            icon: Icons.check_circle,
            color: Colors.purple,
            subtitle: '${_dashboardStats!.attendance.todayCheckIns} check-ins',
          ),
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, color: color, size: 22),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              title,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
              ...(_dashboardStats!.recentActivities.attendances
                  .take(3)
                  .map(
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
              ...(_dashboardStats!.recentActivities.tasks
                  .take(3)
                  .map(
                    (task) => ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        radius: 16,
                        backgroundColor: _getTaskStatusColor(task.status),
                        child: const Icon(
                          Icons.task,
                          size: 16,
                          color: Colors.white,
                        ),
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
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildQuickActionButton(
                    icon: Icons.people,
                    label: 'Manage Employees',
                    color: Colors.blue,
                    onTap: () {
                      setState(() {
                        _selectedIndex = 1; // Employees tab
                      });
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildQuickActionButton(
                    icon: Icons.admin_panel_settings,
                    label: 'Manage Admins',
                    color: Colors.red,
                    onTap: () {
                      setState(() {
                        _selectedIndex = 2; // Admins tab
                      });
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _buildQuickActionButton(
                    icon: Icons.location_on,
                    label: 'Add Geofence',
                    color: Colors.green,
                    onTap: () {
                      setState(() {
                        _selectedIndex = 3; // Geofences tab
                      });
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildQuickActionButton(
                    icon: Icons.task,
                    label: 'Create Task',
                    color: Colors.orange,
                    onTap: () {
                      setState(() {
                        _selectedIndex = 6; // Tasks tab
                      });
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _buildQuickActionButton(
                    icon: Icons.assessment,
                    label: 'View Reports',
                    color: Colors.purple,
                    onTap: () {
                      setState(() {
                        _selectedIndex = 4; // Reports tab
                      });
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildQuickActionButton(
                    icon: Icons.settings,
                    label: 'Settings',
                    color: Colors.teal,
                    onTap: () {
                      setState(() {
                        _selectedIndex = 5; // Settings tab
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
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w500,
                fontSize: 11,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWorldMapSection() {
    return Card(
      elevation: 4,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Live Employee Tracking',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Online: ${_liveLocations.length} employees',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          Container(
            height: 400,
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: Colors.grey.shade300)),
            ),
            child: Stack(
              children: [
                FlutterMap(
                  options: MapOptions(
                    initialCenter: _defaultCenter,
                    initialZoom: 3,
                    maxZoom: 18,
                    minZoom: 2,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.all,
                    ),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                      subdomains: const ['a', 'b', 'c'],
                    ),
                    PolylineLayer(
                      polylines: _trails.entries.map((e) {
                        return Polyline(
                          points: e.value,
                          strokeWidth: 2,
                          color: Colors.blue.withValues(alpha: 0.5),
                        );
                      }).toList(),
                    ),
                    MarkerLayer(
                      markers: _liveLocations.entries
                          .where(
                            (entry) => _employees[entry.key]?.isOnline == true,
                          )
                          .map((entry) {
                            final user = _employees[entry.key];
                            final empLocation = _employeeLocations[entry.key];

                            // Determine marker color based on employee status
                            Color markerColor = Colors.green;
                            IconData markerIcon = Icons.check_circle;

                            if (empLocation != null) {
                              switch (empLocation.status) {
                                case EmployeeStatus.available:
                                  markerColor = Colors.green;
                                  markerIcon = Icons.check_circle;
                                  break;
                                case EmployeeStatus.moving:
                                  markerColor = Colors.blue;
                                  markerIcon = Icons.directions_run;
                                  break;
                                case EmployeeStatus.busy:
                                  markerColor = Colors.red;
                                  markerIcon = Icons.schedule;
                                  break;
                                case EmployeeStatus.offline:
                                  markerColor = Colors.grey;
                                  markerIcon = Icons.cloud_off;
                                  break;
                              }
                            }

                            return Marker(
                              point: entry.value,
                              width: 40,
                              height: 40,
                              child: GestureDetector(
                                onTap: () {
                                  _showEmployeeDetails(entry.key, user);
                                },
                                child: Tooltip(
                                  message: user?.name ?? entry.key,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: markerColor,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 2,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: markerColor.withValues(
                                            alpha: 0.5,
                                          ),
                                          blurRadius: 8,
                                          spreadRadius: 2,
                                        ),
                                      ],
                                    ),
                                    padding: const EdgeInsets.all(6),
                                    child: Icon(
                                      markerIcon,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          })
                          .toList(),
                    ),
                  ],
                ),
                // Floating employee indicators at map edges
                _buildFloatingEmployeeIndicators(),
                if (_liveLocations.isEmpty && _showNoEmployeesPopup)
                  Align(
                    alignment: Alignment.center,
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _showNoEmployeesPopup = false;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.98),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 12,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.location_off,
                              size: 48,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'No online employees',
                              style: TextStyle(
                                color: Colors.black87,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Employees will appear here once they log in',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 13,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: Colors.grey.shade200)),
              color: Colors.grey.shade50,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Drag to pan • Scroll to zoom',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                if (_liveLocations.isNotEmpty)
                  Text(
                    '${_trails.length} trails',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showEmployeeDetails(String userId, UserModel? user) {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(user?.name ?? 'Employee'),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(ctx),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: DefaultTabController(
              length: 2,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TabBar(
                    tabs: const [
                      Tab(text: 'Details'),
                      Tab(text: 'Status'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: TabBarView(
                      children: [
                        // Details Tab
                        SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildDetailRow('Name', user?.name ?? 'N/A'),
                              _buildDetailRow('Email', user?.email ?? 'N/A'),
                              _buildDetailRow('Phone', user?.phone ?? 'N/A'),
                              _buildDetailRow('Role', user?.role ?? 'N/A'),
                              const SizedBox(height: 16),
                              const Text(
                                'Location',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 8),
                              if (_liveLocations.containsKey(userId))
                                Text(
                                  'Lat: ${_liveLocations[userId]!.latitude.toStringAsFixed(4)}\nLng: ${_liveLocations[userId]!.longitude.toStringAsFixed(4)}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade700,
                                  ),
                                )
                              else
                                Text(
                                  'Location not available',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        // Status Tab
                        SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildStatusRow(
                                'Online Status',
                                user?.isOnline == true ? 'Online' : 'Offline',
                                user?.isOnline == true
                                    ? Colors.green
                                    : Colors.grey,
                              ),
                              _buildStatusRow(
                                'Active Tasks',
                                '${user?.activeTaskCount ?? 0}',
                                Colors.blue,
                              ),
                              _buildStatusRow(
                                'Workload',
                                _getWorkloadStatus(user?.workloadWeight ?? 0.0),
                                _getWorkloadColor(user?.workloadWeight ?? 0.0),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'Availability',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 8),
                              _buildAvailabilityInfo(userId),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  String _getWorkloadStatus(double workload) {
    if (workload >= 0.8) return 'Overloaded';
    if (workload >= 0.5) return 'Busy';
    return 'Available';
  }

  Color _getWorkloadColor(double workload) {
    if (workload >= 0.8) return Colors.red;
    if (workload >= 0.5) return Colors.orange;
    return Colors.green;
  }

  Widget _buildAvailabilityInfo(String userId) {
    // Check if employee is in live locations (online)
    final isOnline = _liveLocations.containsKey(userId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStatusRow(
          'Current Status',
          isOnline ? 'Online' : 'Offline',
          isOnline ? Colors.green : Colors.grey,
        ),
        if (isOnline) ...[
          _buildStatusRow('Vacancy', 'Available', Colors.green),
          _buildStatusRow('Distance to Tasks', 'Checking...', Colors.blue),
        ] else
          _buildStatusRow('Last Seen', 'Offline', Colors.grey),
      ],
    );
  }

  Widget _buildStatusRow(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: valueColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: valueColor.withValues(alpha: 0.3)),
            ),
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                color: valueColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingEmployeeIndicators() {
    // Get online employees only
    final onlineEmployees = _liveLocations.entries
        .where((entry) => _employees[entry.key]?.isOnline == true)
        .toList();

    if (onlineEmployees.isEmpty) return const SizedBox.shrink();

    // Calculate rough map bounds (simplified for viewport)
    // Assuming map is roughly 400px height and 3x zoom level
    const double mapHeightDegrees = 10.0; // Approximate degrees visible
    const double mapWidthDegrees = 15.0;

    // Filter employees outside visible bounds
    final outOfBoundsEmployees = onlineEmployees.where((entry) {
      final empLat = entry.value.latitude;
      final empLng = entry.value.longitude;
      // Simple bounds check - in production, use actual map controller bounds
      return empLat < (_defaultCenter.latitude - mapHeightDegrees / 2) ||
          empLat > (_defaultCenter.latitude + mapHeightDegrees / 2) ||
          empLng < (_defaultCenter.longitude - mapWidthDegrees / 2) ||
          empLng > (_defaultCenter.longitude + mapWidthDegrees / 2);
    }).toList();

    if (outOfBoundsEmployees.isEmpty) return const SizedBox.shrink();

    return Positioned.fill(
      child: Stack(
        children: [
          // Top edge indicators
          if (outOfBoundsEmployees.any(
            (e) => e.value.latitude > _defaultCenter.latitude + 4,
          ))
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 50,
              child: Container(
                color: Colors.black.withValues(alpha: 0.02),
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: outOfBoundsEmployees.length,
                  itemBuilder: (context, index) {
                    final entry = outOfBoundsEmployees[index];
                    final user = _employees[entry.key];
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 4,
                      ),
                      child: GestureDetector(
                        onTap: () => _autoPanToEmployee(entry.key, entry.value),
                        child: Tooltip(
                          message: '${user?.name ?? "Employee"}\nClick to pan',
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.green,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.3),
                                  blurRadius: 4,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.person,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          // Right edge indicators
          if (outOfBoundsEmployees.any(
            (e) => e.value.longitude > _defaultCenter.longitude + 6,
          ))
            Positioned(
              right: 0,
              top: 50,
              bottom: 0,
              width: 50,
              child: Container(
                color: Colors.black.withValues(alpha: 0.02),
                child: ListView.builder(
                  scrollDirection: Axis.vertical,
                  itemCount: outOfBoundsEmployees.length,
                  itemBuilder: (context, index) {
                    final entry = outOfBoundsEmployees[index];
                    final user = _employees[entry.key];
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 4,
                      ),
                      child: GestureDetector(
                        onTap: () => _autoPanToEmployee(entry.key, entry.value),
                        child: Tooltip(
                          message: '${user?.name ?? "Employee"}\nClick to pan',
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.blue,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.3),
                                  blurRadius: 4,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.person,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          // Bottom edge indicators
          if (outOfBoundsEmployees.any(
            (e) => e.value.latitude < _defaultCenter.latitude - 4,
          ))
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: 50,
              child: Container(
                color: Colors.black.withValues(alpha: 0.02),
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: outOfBoundsEmployees.length,
                  itemBuilder: (context, index) {
                    final entry = outOfBoundsEmployees[index];
                    final user = _employees[entry.key];
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 4,
                      ),
                      child: GestureDetector(
                        onTap: () => _autoPanToEmployee(entry.key, entry.value),
                        child: Tooltip(
                          message: '${user?.name ?? "Employee"}\nClick to pan',
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.orange,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.3),
                                  blurRadius: 4,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.person,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          // Left edge indicators
          if (outOfBoundsEmployees.any(
            (e) => e.value.longitude < _defaultCenter.longitude - 7.5,
          ))
            Positioned(
              left: 0,
              top: 50,
              bottom: 0,
              width: 50,
              child: Container(
                color: Colors.black.withValues(alpha: 0.02),
                child: ListView.builder(
                  scrollDirection: Axis.vertical,
                  itemCount: outOfBoundsEmployees.length,
                  itemBuilder: (context, index) {
                    final entry = outOfBoundsEmployees[index];
                    final user = _employees[entry.key];
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 4,
                      ),
                      child: GestureDetector(
                        onTap: () => _autoPanToEmployee(entry.key, entry.value),
                        child: Tooltip(
                          message: '${user?.name ?? "Employee"}\nClick to pan',
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.purple,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.3),
                                  blurRadius: 4,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.person,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _autoPanToEmployee(String userId, LatLng location) {
    _showEmployeeDetails(userId, _employees[userId]);
  }

  void _showEmployeeAvailabilityDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Employee Availability'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Online Employees',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              if (_employees.isEmpty)
                Center(
                  child: Text(
                    'No employees',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                )
              else
                SizedBox(
                  height: 250,
                  child: ListView.builder(
                    itemCount: _employees.length,
                    itemBuilder: (context, index) {
                      final entry = _employees.entries.toList()[index];
                      final employee = entry.value;
                      final isOnline = _liveLocations.containsKey(entry.key);

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: isOnline ? Colors.green : Colors.grey,
                                borderRadius: BorderRadius.circular(5),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    employee.name,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    employee.email,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              isOnline ? 'Online' : 'Offline',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: isOnline ? Colors.green : Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showGeofenceDetailsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Geofence Details'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Total: ${_dashboardStats!.geofences.total}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Active: ${_dashboardStats!.geofences.active}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  setState(() => _selectedIndex = 3);
                },
                child: const Text('Manage Geofences'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showTasksDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Task Summary'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Total: ${_dashboardStats!.tasks.total}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Pending: ${_dashboardStats!.tasks.pending}',
                style: TextStyle(fontSize: 12, color: Colors.orange),
              ),
              const SizedBox(height: 8),
              Text(
                'Completed: ${_dashboardStats!.tasks.completed}',
                style: TextStyle(fontSize: 12, color: Colors.green),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  setState(() => _selectedIndex = 6);
                },
                child: const Text('Manage Tasks'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showAttendanceDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Today\'s Attendance'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Check-ins: ${_dashboardStats!.attendance.todayCheckIns}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Present: ${_dashboardStats!.attendance.today}',
                style: TextStyle(fontSize: 12, color: Colors.green),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  setState(() => _selectedIndex = 4);
                },
                child: const Text('View Reports'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationsPanel() {
    final unreadCount = _notifications.where((n) => !n.isRead).length;

    if (_notifications.isEmpty) {
      return Card(
        elevation: 4,
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: Text(
              'No new notifications',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ),
        ),
      );
    }

    return Card(
      elevation: 4,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Text(
                      'Real-time Alerts',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    if (unreadCount > 0) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '$unreadCount new',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      for (final notif in _notifications) {
                        notif.isRead = true;
                      }
                    });
                  },
                  icon: const Icon(Icons.done_all, size: 18),
                  label: const Text('Mark all read'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 150,
              child: ListView.builder(
                itemCount: _notifications.length,
                itemBuilder: (context, index) {
                  final notif = _notifications[index];
                  return _buildNotificationItem(notif);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationItem(DashboardNotification notif) {
    Color typeColor;
    IconData typeIcon;

    switch (notif.type) {
      case 'employee':
        typeColor = Colors.blue;
        typeIcon = Icons.people;
        break;
      case 'task':
        typeColor = Colors.orange;
        typeIcon = Icons.task;
        break;
      case 'attendance':
        typeColor = Colors.purple;
        typeIcon = Icons.check_circle;
        break;
      case 'geofence':
        typeColor = Colors.green;
        typeIcon = Icons.location_on;
        break;
      default:
        typeColor = Colors.grey;
        typeIcon = Icons.notifications;
    }

    return InkWell(
      onTap: () => _openNotification(notif),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: notif.isRead ? Colors.grey.shade50 : Colors.blue.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: notif.isRead
                ? Colors.grey.shade200
                : typeColor.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            if (!notif.isRead)
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(4),
                ),
                margin: const EdgeInsets.only(right: 8),
              ),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: typeColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(typeIcon, color: typeColor, size: 16),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notif.title,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    notif.message,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                setState(() {
                  _notifications.remove(notif);
                });
              },
              child: Icon(Icons.close, size: 16, color: Colors.grey.shade400),
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

  Future<void> _initMapData() async {
    await _loadEmployeesForMap();
    await _loadOnlineEmployeeLocations();
    _subscribeToLocations();
  }

  Future<void> _loadEmployeesForMap() async {
    try {
      final employees = await _userService.fetchEmployees();
      if (mounted) {
        setState(() {
          for (final emp in employees) {
            _employees[emp.id] = emp;
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading employees for map: $e');
    }
  }

  Future<void> _loadOnlineEmployeeLocations() async {
    try {
      // Fetch all online employees' locations from backend
      final response = await _userService.getOnlineEmployees();
      if (mounted && response != null) {
        debugPrint(
          '📍 Loaded ${response.length} online employees from backend',
        );
        setState(() {
          for (final emp in response) {
            final userId = emp['userId'] ?? emp['employeeId'] ?? '';
            final lat = (emp['latitude'] as num?)?.toDouble();
            final lng = (emp['longitude'] as num?)?.toDouble();
            final name = emp['name'] ?? 'Unknown';

            // Only add if we have valid userId and coordinates
            if (userId.isNotEmpty && lat != null && lng != null) {
              _liveLocations[userId] = LatLng(lat, lng);
              debugPrint('✅ Added employee $name ($userId) at ($lat, $lng)');
            } else {
              debugPrint(
                '⚠️ Skipped employee $name - missing location data: lat=$lat, lng=$lng',
              );
            }
          }
          debugPrint('📊 Total locations on map: ${_liveLocations.length}');
        });

        // When admin opens dashboard and there are online employees,
        // show a one-time modal summarizing who is currently online.
        if (_showNoEmployeesPopup && _liveLocations.isNotEmpty) {
          _showNoEmployeesPopup = false;
          final names = response
              .map((e) => (e['name'] ?? e['email'] ?? 'Employee').toString())
              .toList();
          // Delay slightly to ensure context is ready
          await Future.delayed(const Duration(milliseconds: 300));
          if (!mounted) return;
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Employees Online'),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'The following employees are currently online:',
                      style: const TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 12),
                    ...names.map(
                      (n) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text('• $n'),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close'),
                ),
              ],
            ),
          );
        }
      } else {
        debugPrint('⚠️ No response from getOnlineEmployees');
      }
    } catch (e) {
      debugPrint('❌ Error loading online employee locations: $e');
    }
  }

  void _subscribeToLocations() {
    _realtimeService.locationStream.listen((event) {
      final userId = event['userId']?.toString();
      final lat = (event['latitude'] as num?)?.toDouble();
      final lng = (event['longitude'] as num?)?.toDouble();
      if (userId == null || lat == null || lng == null) return;

      final pos = LatLng(lat, lng);
      if (!mounted) return;
      setState(() {
        final wasEmpty = _liveLocations.isEmpty;
        _liveLocations[userId] = pos;
        final trail = _trails[userId] ?? <LatLng>[];
        trail.add(pos);
        if (trail.length > 50) {
          trail.removeRange(0, trail.length - 50);
        }
        _trails[userId] = trail;
        if (wasEmpty && _liveLocations.isNotEmpty) {
          _showNoEmployeesPopup = false;
        }
      });
    });
  }
}
