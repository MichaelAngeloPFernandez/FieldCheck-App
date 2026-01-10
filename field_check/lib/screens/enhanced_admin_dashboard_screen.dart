import 'package:flutter/material.dart';
import 'dart:async';
import '../services/employee_location_service.dart';
import '../services/checkout_notification_service.dart';
import '../services/task_monitoring_service.dart';
import '../services/task_service.dart';
import '../services/realtime_service.dart';
import '../widgets/employee_status_view.dart';
import '../widgets/live_employee_map.dart';
import '../widgets/employee_management_modal.dart';

class EnhancedAdminDashboardScreen extends StatefulWidget {
  const EnhancedAdminDashboardScreen({super.key});

  @override
  State<EnhancedAdminDashboardScreen> createState() =>
      _EnhancedAdminDashboardScreenState();
}

class _EnhancedAdminDashboardScreenState
    extends State<EnhancedAdminDashboardScreen> {
  final EmployeeLocationService _locationService = EmployeeLocationService();
  final RealtimeService _realtimeService = RealtimeService();
  List<EmployeeLocation> _employees = [];
  bool _isLoading = true;
  Timer? _refreshTimer;
  StreamSubscription<List<EmployeeLocation>>? _locationsSub;
  final CheckoutNotificationService _checkoutService =
      CheckoutNotificationService();
  StreamSubscription<CheckoutWarning>? _warningSub;
  StreamSubscription<AutoCheckoutEvent>? _autoCheckoutSub;
  final TaskMonitoringService _taskMonitoringService = TaskMonitoringService();
  TaskStatistics? _taskStatistics;
  Map<String, double> _employeeTaskLoad = {};

  // Notification tracking
  int _notificationBadgeCount = 0;
  final List<Map<String, dynamic>> _recentNotifications = [];
  StreamSubscription<Map<String, dynamic>>? _notificationSub;
  StreamSubscription<Map<String, dynamic>>? _attendanceSub;

  // Per-box notification counters
  int _attendanceNotificationCount = 0;
  int _taskNotificationCount = 0;
  int _reportNotificationCount = 0;

  @override
  void initState() {
    super.initState();
    // ignore: unnecessary_statements
    _reportNotificationCount;
    _initializeLocationService();
    // Auto-refresh every 5 seconds for real-time updates
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) {
        setState(() {});
      }
    });

    _initCheckoutNotifications();
    _loadTaskStatistics();
    _initNotificationListener();
  }

  Future<void> _initializeLocationService() async {
    try {
      await _locationService.initialize();
      _locationsSub?.cancel();
      _locationsSub = _locationService.employeeLocationsStream.listen((
        locations,
      ) {
        if (mounted) {
          setState(() {
            _employees = locations;
            _isLoading = false;
          });
        }
      });
    } catch (e) {
      debugPrint('Error initializing location service: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _locationService.dispose();
    _locationsSub?.cancel();
    _warningSub?.cancel();
    _autoCheckoutSub?.cancel();
    _attendanceSub?.cancel();
    _notificationSub?.cancel();
    super.dispose();
  }

  Future<void> _initCheckoutNotifications() async {
    try {
      await _checkoutService.initialize();

      _warningSub = _checkoutService.warningStream.listen((warning) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Warning: ${warning.employeeName} will be auto-checked out '
              'in ${warning.minutesRemaining} minutes.',
            ),
            duration: const Duration(seconds: 4),
            backgroundColor: Colors.orange[700],
          ),
        );
      });

      _autoCheckoutSub = _checkoutService.checkoutStream.listen((autoEvent) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${autoEvent.employeeName} was auto-checked out '
              '(attendance voided).',
            ),
            duration: const Duration(seconds: 5),
            backgroundColor: Colors.red[700],
          ),
        );
      });
    } catch (e) {
      debugPrint('Error initializing checkout notifications: $e');
    }
  }

  void _initNotificationListener() {
    try {
      _realtimeService.initialize().then((_) {
        // Listen for attendance updates (check-in/out) and refresh location data
        _attendanceSub = _realtimeService.attendanceStream.listen((event) {
          if (mounted) {
            // Force refresh of location/employee data when attendance changes
            setState(() {});
          }
        });

        _notificationSub = _realtimeService.notificationStream.listen((
          notification,
        ) {
          if (!mounted) return;
          debugPrint('Admin received notification: $notification');

          final notificationType = notification['type'] as String? ?? '';

          setState(() {
            _notificationBadgeCount++;
            _recentNotifications.insert(0, notification);
            // Keep only last 20 notifications
            if (_recentNotifications.length > 20) {
              _recentNotifications.removeLast();
            }

            // Track per-type notification counts
            if (notificationType == 'attendance') {
              _attendanceNotificationCount++;
            } else if (notificationType == 'task') {
              _taskNotificationCount++;
            } else if (notificationType == 'report') {
              _reportNotificationCount++;
            }
          });

          // Show snackbar for all notifications
          final action = notification['action'] ?? 'event';
          final message = notification['message'] ?? 'New notification';

          Color snackbarColor = Colors.blue;
          if (notificationType == 'attendance') {
            snackbarColor = action == 'check-in' ? Colors.green : Colors.orange;
          } else if (notificationType == 'task') {
            snackbarColor = Colors.deepPurple;
          } else if (notificationType == 'report') {
            snackbarColor = Colors.amber;
          }

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              duration: const Duration(seconds: 4),
              backgroundColor: snackbarColor,
            ),
          );
        });
      });
    } catch (e) {
      debugPrint('Error initializing notification listener: $e');
    }
  }

  void _clearNotificationBadge() {
    setState(() {
      _notificationBadgeCount = 0;
      _attendanceNotificationCount = 0;
      _taskNotificationCount = 0;
      _reportNotificationCount = 0;
    });
  }

  Future<void> _loadTaskStatistics() async {
    try {
      final stats = await _taskMonitoringService.getTaskStatistics();
      if (!mounted) return;
      setState(() {
        _taskStatistics = stats;
      });
      await _loadEmployeeTaskLoad();
    } catch (e) {
      debugPrint('Error loading task statistics: $e');
    }
  }

  Future<void> _loadEmployeeTaskLoad() async {
    try {
      final tasks = await TaskService().getCurrentTasks();
      final load = <String, double>{};

      for (final task in tasks) {
        if (task.status == 'completed') continue;

        double weight = 1.0;
        switch (task.difficulty?.toLowerCase() ?? 'medium') {
          case 'easy':
            weight = 1.0;
            break;
          case 'medium':
            weight = 2.0;
            break;
          case 'hard':
            weight = 3.0;
            break;
          case 'critical':
            weight = 5.0;
            break;
          default:
            weight = 2.0;
        }

        for (final assignee in task.assignedToMultiple) {
          final key = assignee.employeeId ?? assignee.id;
          load[key] = (load[key] ?? 0.0) + weight;
        }
      }

      if (!mounted) return;
      setState(() {
        _employeeTaskLoad = load;
      });
    } catch (e) {
      debugPrint('Error loading employee task load: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        elevation: 0,
        actions: [
          // Notification badge
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.notifications),
                onPressed: _clearNotificationBadge,
              ),
              if (_notificationBadgeCount > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 20,
                      minHeight: 20,
                    ),
                    child: Text(
                      _notificationBadgeCount.toString(),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() => _isLoading = true);
              Future.delayed(const Duration(seconds: 1), () {
                if (mounted) setState(() => _isLoading = false);
              });
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Dashboard stats
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildStatCard(
                          'Employees',
                          _employees.length.toString(),
                          Icons.people,
                          Colors.blue,
                          onTap: () => _showTotalEmployeesView(context),
                          notificationCount: _attendanceNotificationCount,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildStatCard(
                          'Online',
                          _employees.where((e) => e.isOnline).length.toString(),
                          Icons.cloud_done,
                          Colors.green,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildStatCard(
                          'Busy',
                          _employees
                              .where((e) => e.status == EmployeeStatus.busy)
                              .length
                              .toString(),
                          Icons.schedule,
                          Colors.red,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_taskStatistics != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: _buildStatCard(
                            'Active Tasks',
                            _taskStatistics!.activeTasks.toString(),
                            Icons.task_alt,
                            Colors.deepPurple,
                            notificationCount: _taskNotificationCount,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildStatCard(
                            'Weighted Load',
                            _taskStatistics!.totalDifficultyWeight
                                .toStringAsFixed(1),
                            Icons.scale,
                            Colors.orange,
                          ),
                        ),
                      ],
                    ),
                  ),
                // Status breakdown
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStatusBadge(
                        '🟢 Available',
                        _employees
                            .where((e) => e.status == EmployeeStatus.available)
                            .length,
                        Colors.green,
                      ),
                      _buildStatusBadge(
                        '🟢 Moving',
                        _employees
                            .where((e) => e.status == EmployeeStatus.moving)
                            .length,
                        Colors.green,
                      ),
                      _buildStatusBadge(
                        '🔴 Busy',
                        _employees
                            .where((e) => e.status == EmployeeStatus.busy)
                            .length,
                        Colors.red,
                      ),
                      _buildStatusBadge(
                        '⚫ Offline',
                        _employees
                            .where((e) => e.status == EmployeeStatus.offline)
                            .length,
                        Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.55),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // Real-time location updates indicator
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Real-time location tracking active',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                        ),
                        const Spacer(),
                        Text(
                          '${_employees.where((e) => e.isOnline).length} online',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(),
                // Per-employee task load breakdown
                if (_employeeTaskLoad.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Top Employees by Task Load',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ..._buildTopEmployeesList(),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                const Divider(),
                // Live employee map
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: LiveEmployeeMap(
                    employees: _employees,
                    height: 300,
                    onStatusChange: (employeeId, newStatus) {
                      _locationService.requestStatusUpdate(
                        employeeId,
                        newStatus,
                      );
                    },
                    onRefresh: () {
                      setState(() => _isLoading = true);
                      Future.delayed(const Duration(seconds: 1), () {
                        if (mounted) setState(() => _isLoading = false);
                      });
                    },
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(),
                // Employee status view
                Expanded(
                  child: EmployeeStatusView(
                    employees: _employees,
                    onStatusChange: (employeeId, newStatus) {
                      _locationService.requestStatusUpdate(
                        employeeId,
                        newStatus,
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Status updated for $employeeId'),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildStatCard(
    String label,
    String value,
    IconData icon,
    Color color, {
    VoidCallback? onTap,
    int notificationCount = 0,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: Column(
              children: [
                Icon(icon, color: color, size: 24),
                const SizedBox(height: 8),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.75),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          // Notification badge
          if (notificationCount > 0)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(10),
                ),
                constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                child: Text(
                  notificationCount.toString(),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String label, int count, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.85),
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            count.toString(),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildTopEmployeesList() {
    final sorted = _employeeTaskLoad.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final top = sorted.take(5).toList();

    return top.map((entry) {
      final employeeId = entry.key;
      final load = entry.value;
      final employee = _employees.firstWhere(
        (e) => e.employeeId == employeeId,
        orElse: () => EmployeeLocation(
          employeeId: employeeId,
          name: 'Unknown Employee',
          latitude: 0,
          longitude: 0,
          accuracy: 0,
          status: EmployeeStatus.offline,
          timestamp: DateTime.now(),
          activeTaskCount: 0,
          workloadScore: 0,
          isOnline: false,
        ),
      );

      final loadColor = load > 8.0
          ? Colors.red
          : load > 5.0
          ? Colors.orange
          : Colors.green;

      return Padding(
        padding: const EdgeInsets.only(bottom: 8.0),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: loadColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: loadColor.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  employee.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: loadColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  load.toStringAsFixed(1),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }).toList();
  }

  void _showTotalEmployeesView(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => EmployeeManagementModal(
        employees: _employees,
        onConfigUpdate: (employeeId, config) {
          debugPrint(
            'Updated config for $employeeId: '
            'checkout=${config.autoCheckoutMinutes}min, '
            'maxTasks=${config.maxTasksPerDay}',
          );
        },
      ),
    );
  }
}
