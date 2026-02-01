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
import '../utils/app_theme.dart';
import '../utils/http_util.dart';
import '../widgets/app_page.dart';
import '../widgets/app_widgets.dart';

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
  String? _loadError;
  String? _coldStartHint;
  bool _heavyWidgetsReady = false;
  String? _backendCommit;
  Timer? _coldStartTimer;
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
    _loadBackendBuildInfo();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _heavyWidgetsReady = true;
      });
    });
    // Auto-refresh every 5 seconds for real-time updates
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
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
      if (mounted) {
        setState(() {
          _loadError = null;
          _coldStartHint = null;
        });
      }

      _coldStartTimer?.cancel();
      _coldStartTimer = Timer(const Duration(seconds: 8), () {
        if (!mounted) return;
        if (_employees.isNotEmpty) return;
        if (_loadError != null) return;
        setState(() {
          _coldStartHint =
              'Backend may be waking up (Render cold start). Please wait…';
        });
      });

      await _locationService.initialize().timeout(const Duration(seconds: 25));
      _locationsSub?.cancel();
      _locationsSub = _locationService.employeeLocationsStream.listen((
        locations,
      ) {
        if (mounted) {
          setState(() {
            _employees = locations;
            _coldStartHint = null;
          });
        }
      });
    } catch (e) {
      debugPrint('Error initializing location service: $e');
      if (mounted) {
        setState(() {
          _loadError = 'Failed to initialize live employee tracking.';
        });
      }
    }
  }

  Future<void> _loadBackendBuildInfo() async {
    try {
      final res = await HttpUtil().get('/api/health');
      if (res.statusCode != 200) return;
      final body = res.body;
      final match = RegExp(r'"gitCommit"\s*:\s*"([^"]*)"').firstMatch(body);
      final commit = match?.group(1);
      if (!mounted) return;
      setState(() {
        _backendCommit = commit;
      });
    } catch (_) {}
  }

  Future<void> _refreshAll() async {
    if (!mounted) return;
    setState(() {
      _loadError = null;
      _coldStartHint = null;
    });

    await _initializeLocationService();
    await _loadTaskStatistics();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _coldStartTimer?.cancel();
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
        AppWidgets.showWarningSnackbar(
          context,
          'Warning: ${warning.employeeName} will be auto-checked out in '
          '${warning.minutesRemaining} minutes.',
        );
      });

      _autoCheckoutSub = _checkoutService.checkoutStream.listen((autoEvent) {
        if (!mounted) return;
        AppWidgets.showErrorSnackbar(
          context,
          '${autoEvent.employeeName} was auto-checked out (attendance voided).',
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

          if (notificationType == 'attendance') {
            if (action == 'check-in') {
              AppWidgets.showSuccessSnackbar(context, message);
            } else {
              AppWidgets.showWarningSnackbar(context, message);
            }
          } else if (notificationType == 'report') {
            AppWidgets.showWarningSnackbar(context, message);
          } else {
            AppWidgets.showSuccessSnackbar(context, message);
          }
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
    final theme = Theme.of(context);
    final onlineCount = _employees.where((e) => e.isOnline).length;

    return AppPage(
      appBarTitle: 'Admin Dashboard',
      actions: [
        if (_backendCommit != null && _backendCommit!.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(right: AppTheme.sm),
            child: Center(
              child: Text(
                'v ${_backendCommit!.trim().length > 7 ? _backendCommit!.trim().substring(0, 7) : _backendCommit!.trim()}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        Stack(
          children: [
            IconButton(
              tooltip: 'Notifications',
              icon: const Icon(Icons.notifications),
              onPressed: _clearNotificationBadge,
            ),
            if (_notificationBadgeCount > 0)
              Positioned(
                right: AppTheme.sm,
                top: AppTheme.sm,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.error,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 20,
                    minHeight: 20,
                  ),
                  child: Text(
                    _notificationBadgeCount.toString(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onError,
                      fontWeight: FontWeight.w800,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        ),
        IconButton(
          tooltip: 'Refresh',
          icon: const Icon(Icons.refresh),
          onPressed: _refreshAll,
        ),
      ],
      padding: const EdgeInsets.fromLTRB(
        AppTheme.lg,
        AppTheme.lg,
        AppTheme.lg,
        AppTheme.xl,
      ),
      child: (_loadError != null
          ? AppWidgets.errorMessage(message: _loadError!, onRetry: _refreshAll)
          : Column(
              children: [
                if (_isLoading)
                  AppWidgets.loadingIndicator(
                    message: 'Loading admin dashboard...',
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: _buildStatCard(
                          'Employees',
                          _employees.length.toString(),
                          Icons.people,
                          theme.colorScheme.primary,
                          onTap: () => _showTotalEmployeesView(context),
                          notificationCount: _attendanceNotificationCount,
                        ),
                      ),
                      const SizedBox(width: AppTheme.md),
                      Expanded(
                        child: _buildStatCard(
                          'Online',
                          onlineCount.toString(),
                          Icons.cloud_done,
                          Colors.green,
                        ),
                      ),
                      const SizedBox(width: AppTheme.md),
                      Expanded(
                        child: _buildStatCard(
                          'Busy',
                          _employees
                              .where((e) => e.status == EmployeeStatus.busy)
                              .length
                              .toString(),
                          Icons.schedule,
                          theme.colorScheme.error,
                        ),
                      ),
                    ],
                  ),
                if (_taskStatistics != null) ...[
                  const SizedBox(height: AppTheme.md),
                  Row(
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
                      const SizedBox(width: AppTheme.md),
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
                ],
                const SizedBox(height: AppTheme.lg),
                Row(
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
                      theme.colorScheme.error,
                    ),
                    _buildStatusBadge(
                      '⚫ Offline',
                      _employees
                          .where((e) => e.status == EmployeeStatus.offline)
                          .length,
                      theme.colorScheme.onSurface.withValues(alpha: 0.55),
                    ),
                  ],
                ),
                const SizedBox(height: AppTheme.lg),
                Container(
                  padding: const EdgeInsets.all(AppTheme.md),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    border: Border.all(
                      color: theme.colorScheme.primary.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _employees.isNotEmpty
                              ? Colors.green
                              : (_loadError != null
                                    ? theme.colorScheme.error
                                    : Colors.orange),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: AppTheme.sm),
                      Expanded(
                        child: Text(
                          _employees.isNotEmpty
                              ? 'Real-time location tracking active'
                              : (_coldStartHint ??
                                    'Connecting to live tracking…'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.primary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: AppTheme.sm),
                      Text(
                        '$onlineCount online',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppTheme.lg),
                const Divider(),
                if (_employeeTaskLoad.isNotEmpty) ...[
                  const SizedBox(height: AppTheme.lg),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Top Employees by Task Load',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppTheme.md),
                  ..._buildTopEmployeesList(),
                  const SizedBox(height: AppTheme.lg),
                  const Divider(),
                ],
                const SizedBox(height: AppTheme.lg),
                if (_heavyWidgetsReady)
                  LiveEmployeeMap(
                    employees: _employees,
                    height: 300,
                    onStatusChange: (employeeId, newStatus) {
                      _locationService.requestStatusUpdate(
                        employeeId,
                        newStatus,
                      );
                    },
                    onRefresh: _refreshAll,
                  )
                else
                  SizedBox(
                    height: 300,
                    child: AppWidgets.loadingIndicator(
                      message: 'Preparing map…',
                    ),
                  ),
                const SizedBox(height: AppTheme.lg),
                const Divider(),
                SizedBox(
                  height: 420,
                  child: _heavyWidgetsReady
                      ? EmployeeStatusView(
                          employees: _employees,
                          onStatusChange: (employeeId, newStatus) {
                            _locationService.requestStatusUpdate(
                              employeeId,
                              newStatus,
                            );
                            AppWidgets.showSuccessSnackbar(
                              context,
                              'Status updated for $employeeId',
                            );
                          },
                        )
                      : AppWidgets.loadingIndicator(
                          message: 'Preparing employee list…',
                        ),
                ),
              ],
            )),
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
            padding: const EdgeInsets.all(AppTheme.lg),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: Column(
              children: [
                Icon(icon, color: color, size: 24),
                const SizedBox(height: AppTheme.sm),
                Text(
                  value,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
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
                  color: Theme.of(context).colorScheme.error,
                  borderRadius: BorderRadius.circular(10),
                ),
                constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                child: Text(
                  notificationCount.toString(),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onError,
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
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.md,
            vertical: AppTheme.sm,
          ),
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
        padding: const EdgeInsets.only(bottom: AppTheme.sm),
        child: Container(
          padding: const EdgeInsets.all(AppTheme.md),
          decoration: BoxDecoration(
            color: loadColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            border: Border.all(color: loadColor.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  employee.name,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.md,
                  vertical: AppTheme.sm,
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
