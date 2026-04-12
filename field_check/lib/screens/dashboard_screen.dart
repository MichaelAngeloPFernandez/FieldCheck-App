// ignore_for_file: use_build_context_synchronously
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:field_check/screens/enhanced_attendance_screen.dart';
import 'package:field_check/screens/history_screen.dart';
import 'package:field_check/screens/map_screen.dart';
import 'package:field_check/screens/settings_screen.dart';
import 'package:field_check/screens/employee_task_list_screen.dart';
import 'package:field_check/screens/employee_profile_screen.dart';
import 'package:field_check/screens/employee_task_details_screen.dart';
import 'package:field_check/providers/auth_provider.dart';
import 'package:field_check/services/user_service.dart';
import 'package:field_check/services/realtime_service.dart';
import 'package:field_check/services/task_service.dart';
import 'package:field_check/services/location_sync_service.dart';
import 'package:field_check/services/autosave_service.dart';
import 'package:field_check/services/checkout_notification_service.dart';
import 'package:field_check/utils/logger.dart';
import 'package:field_check/utils/manila_time.dart';
import 'package:field_check/utils/app_theme.dart';
import 'package:field_check/widgets/app_widgets.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  final LocationSyncService _locationSyncService = LocationSyncService();
  final CheckoutNotificationService _checkoutService =
      CheckoutNotificationService();

  Timer? _greetingTimer;

  StreamSubscription<CheckoutWarning>? _checkoutWarningSub;
  StreamSubscription<AutoCheckoutEvent>? _autoCheckoutSub;
  StreamSubscription<Map<String, dynamic>>? _taskEventsSub;
  StreamSubscription<Map<String, dynamic>>? _unreadCountsSub;
  StreamSubscription<Map<String, dynamic>>? _notificationSub;
  Timer? _taskBadgeDebounce;
  String? _userModelId;
  bool _loadingUserId = true;
  bool _isTrackingLocation = true;

  int _tasksBadgeCount = 0;
  int _notificationsBadgeCount = 0;

  @override
  void initState() {
    super.initState();
    // Set initial index if provided (from drawer navigation)
    if (widget.initialIndex != null) {
      _selectedIndex = widget.initialIndex!;
    }
    _loadUserId();
    _initServices();

    _greetingTimer?.cancel();
    _greetingTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  String _buildGreetingTitle() {
    final user = _userService.currentUser;
    final name = (user?.username ?? '').trim().isNotEmpty
        ? (user?.username ?? '').trim()
        : (user?.name ?? '').trim();
    final code = (user?.employeeId ?? '').trim();
    final idLabel = code.isNotEmpty
        ? code
        : ((user?.id ?? '').trim().isNotEmpty
              ? (user!.id.substring(0, 8))
              : '');
    final greeting = greetingManila();
    final who = name.isNotEmpty ? name : 'User';
    final suffix = idLabel.isNotEmpty ? ' • $idLabel' : '';
    return '$greeting, $who$suffix';
  }

  Future<void> _initServices() async {
    await _realtimeService.initialize();
    await _autosaveService.initialize();
    // Initialize socket for optional continuous location tracking
    await _locationSyncService.initializeSocket();

    // Load persisted preference for continuous tracking that powers
    // admin maps (Employees / World Map)
    bool enabled = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      enabled = prefs.getBool('user.locationTrackingEnabled') ?? true;
    } catch (_) {}

    if (mounted) {
      setState(() {
        _isTrackingLocation = enabled;
      });
    }

    if (enabled) {
      _locationSyncService.startSharing();
    }

    // Note: Location tracking will start when employee manually checks in
    // Do NOT call startTracking() here - it should only happen on manual check-in

    // Initialize auto-checkout notifications (warnings + events)
    await _checkoutService.initialize();
    _checkoutWarningSub = _checkoutService.warningStream.listen(
      _handleCheckoutWarning,
    );
    _autoCheckoutSub = _checkoutService.checkoutStream.listen(
      _handleAutoCheckoutEvent,
    );

    _subscribeToTaskEvents();
    _subscribeToUnreadCounts();
    _subscribeToEmployeeNotifications();
  }

  void _subscribeToUnreadCounts() {
    _unreadCountsSub?.cancel();
    _unreadCountsSub = _realtimeService.unreadCountsStream.listen((counts) {
      final rawTasks = counts['tasks'];
      final nextTasks = rawTasks is int
          ? rawTasks
          : rawTasks is num
          ? rawTasks.toInt()
          : int.tryParse(rawTasks?.toString() ?? '') ?? 0;

      final rawTotal = counts['total'];
      final nextTotal = rawTotal is int
          ? rawTotal
          : rawTotal is num
          ? rawTotal.toInt()
          : int.tryParse(rawTotal?.toString() ?? '') ?? 0;

      if (!mounted) return;
      setState(() {
        _tasksBadgeCount = nextTasks;
        _notificationsBadgeCount = nextTotal;
      });
    });
  }

  void _subscribeToEmployeeNotifications() {
    _notificationSub?.cancel();
    _notificationSub = _realtimeService.notificationStream.listen((data) {
      if (!mounted) return;
      
      final action = (data['action'] ?? '').toString();
      final title = (data['title'] ?? '').toString();
      final message = (data['message'] ?? '').toString();

      if (action == 'taskGraded') {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.green.shade600,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(message),
              ],
            ),
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'VIEW',
              textColor: Colors.white,
              onPressed: () {
                final payload = data['payload'] ?? {};
                final taskId = payload['taskId']?.toString() ?? '';
                if (taskId.isNotEmpty) {
                  // Navigate to the task list and then perhaps details?
                  // For now, staying on dashboard but notifying is good.
                  _selectTab(5); // Go to tasks tab
                }
              },
            ),
          ),
        );
      }
    });
  }

  Future<void> _refreshNotificationsBadge() async {
    try {
      final total = await TaskService().fetchTotalUnreadCount();
      if (!mounted) return;
      setState(() {
        _notificationsBadgeCount = total;
      });
    } catch (_) {}
  }

  void _openNotificationsInbox() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: _EmployeeNotificationsSheet(
              taskService: TaskService(),
              onChanged: _refreshNotificationsBadge,
            ),
          ),
        );
      },
    );
  }

  void _subscribeToTaskEvents() {
    _taskEventsSub?.cancel();
    _taskEventsSub = _realtimeService.taskStream.listen((event) {
      // Always recompute badge on task events (new/update/delete/status change)
      _taskBadgeDebounce?.cancel();
      _taskBadgeDebounce = Timer(const Duration(milliseconds: 350), () {
        _refreshTasksBadge(showSnackIfNew: true, event: event);
      });
    });
  }

  Future<void> _refreshTasksBadge({
    bool showSnackIfNew = false,
    Map<String, dynamic>? event,
  }) async {
    final userId = _userModelId;
    if (userId == null) {
      return;
    }

    int oldCount = _tasksBadgeCount;

    try {
      final count = await TaskService().fetchTasksUnreadCount();

      if (!mounted) return;
      setState(() {
        _tasksBadgeCount = count;
      });

      if (!showSnackIfNew) return;

      final isNewTaskEvent = (event?['type'] as String?) == 'new';
      if (!isNewTaskEvent) return;

      // Only show snackbar if user is not already on Tasks tab
      if (_selectedIndex == 5) return;

      // Guard: only notify if the badge count increased
      if (count <= oldCount) return;

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('New task assigned. Check your Tasks tab.'),
          duration: Duration(seconds: 3),
        ),
      );
    } catch (_) {
      // Ignore badge refresh errors
    }
  }

  Future<void> _clearTasksBadge() async {
    try {
      await TaskService().markTasksScopeRead();
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _tasksBadgeCount = 0;
    });
  }

  Future<void> _toggleLocationTracking() async {
    final newValue = !_isTrackingLocation;

    setState(() {
      _isTrackingLocation = newValue;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('user.locationTrackingEnabled', newValue);
    } catch (_) {}

    if (newValue) {
      _locationSyncService.startSharing();
    } else {
      _locationSyncService.stopSharing();
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          newValue
              ? 'Live location sharing enabled. Admin can see your live location.'
              : 'Live location sharing disabled. Admin will no longer see your live location.',
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  String _formatTime(DateTime time) {
    return formatManilaTimeOfDay(context, time);
  }

  void _handleCheckoutWarning(CheckoutWarning warning) {
    if (!mounted) return;
    // Only show to the current employee
    if (_userModelId != null && warning.employeeId != _userModelId) {
      return;
    }

    setState(() {
      // Ensure user sees Attendance tab when warning arrives
      _selectedIndex = 0;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Auto-checkout warning: You will be auto-checked out in '
          '${warning.minutesRemaining} minutes if you don\'t check out.',
        ),
        duration: const Duration(seconds: 5),
        backgroundColor: Colors.orange[700],
      ),
    );
  }

  void _handleAutoCheckoutEvent(AutoCheckoutEvent event) {
    if (!mounted) return;
    // Only show to the current employee
    if (_userModelId != null && event.employeeId != _userModelId) {
      return;
    }

    setState(() {
      // After auto-checkout, direct user attention to History tab
      _selectedIndex = 3; // History
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'You have been auto-checked out. Your attendance was marked void '
          'and recorded in the reports.',
        ),
        duration: const Duration(seconds: 6),
        backgroundColor: Colors.red[700],
      ),
    );
  }

  @override
  void dispose() {
    _greetingTimer?.cancel();
    _locationSyncService.stopTracking();
    _locationSyncService.dispose();
    _checkoutWarningSub?.cancel();
    _autoCheckoutSub?.cancel();
    _taskBadgeDebounce?.cancel();
    _taskEventsSub?.cancel();
    _unreadCountsSub?.cancel();
    _notificationSub?.cancel();
    super.dispose();
  }

  Future<void> _loadUserId() async {
    try {
      AppLogger.info(AppLogger.tagUI, 'Loading user profile...');

      final authUser = context.read<AuthProvider>().user;
      if (authUser != null) {
        if (!mounted) return;
        setState(() {
          _userModelId = authUser.id;
          _loadingUserId = false;
        });
        _refreshTasksBadge();
        AppLogger.success(
          AppLogger.tagUI,
          'User profile loaded from auth provider: ${authUser.id}',
        );
        return;
      }

      final profile = await _userService.getProfile();

      if (!mounted) return;
      setState(() {
        _userModelId = profile.id;
        _loadingUserId = false;
      });
      _refreshTasksBadge();
      AppLogger.success(AppLogger.tagUI, 'User profile loaded: ${profile.id}');
    } catch (e) {
      AppLogger.error(AppLogger.tagUI, 'Failed to load user profile', e);
      if (!mounted) return;
      setState(() {
        _loadingUserId = false;
      });
    }
  }

  Widget _buildBadge({required Widget child, required int count}) {
    if (count <= 0) return child;
    final text = count > 99 ? '99+' : '$count';
    final theme = Theme.of(context);
    final badgeColor = theme.colorScheme.error;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          right: -8,
          top: -6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: badgeColor,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: theme.colorScheme.surface, width: 1),
              boxShadow: [
                BoxShadow(
                  color: badgeColor.withValues(alpha: 0.3),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              text,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onError,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAppBarIconButton({
    required String tooltip,
    required IconData icon,
    required VoidCallback onPressed,
    Color? color,
  }) {
    final theme = Theme.of(context);
    final foreground =
        color ??
        (theme.appBarTheme.foregroundColor ?? theme.colorScheme.onPrimary);
    return Container(
      margin: const EdgeInsets.only(right: 6),
      decoration: BoxDecoration(
        color: foreground.withValues(alpha: 0.12),
        shape: BoxShape.circle,
        border: Border.all(color: foreground.withValues(alpha: 0.35)),
      ),
      child: IconButton(
        tooltip: tooltip,
        icon: Icon(icon, color: foreground),
        onPressed: onPressed,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints.tightFor(width: 38, height: 38),
      ),
    );
  }

  Widget _buildAppBarPill({
    required IconData icon,
    required String label,
    Color? color,
  }) {
    final theme = Theme.of(context);
    final foreground =
        color ??
        (theme.appBarTheme.foregroundColor ?? theme.colorScheme.onPrimary);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: foreground.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: foreground.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: foreground),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            child: Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: foreground,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _performLogout() async {
    AppLogger.info(AppLogger.tagAuth, 'User logout initiated');
    try {
      await _userService.markOffline();
    } catch (e) {
      AppLogger.warning(
        AppLogger.tagAuth,
        'Mark offline error (non-critical)',
        e,
      );
    }

    try {
      _locationSyncService.stopTracking();
      _locationSyncService.dispose();
    } catch (_) {}

    try {
      RealtimeService().reset();
    } catch (_) {}

    try {
      await _userService.logout();
    } catch (e) {
      AppLogger.warning(AppLogger.tagAuth, 'Logout error (non-critical)', e);
    }

    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/landing', (route) => false);
  }

  Future<void> _logout() async {
    final confirmed = await AppWidgets.confirmLogout(context);
    if (!confirmed) return;
    await _performLogout();
  }

  Widget _buildDrawerNavItem({
    required int index,
    required IconData icon,
    required String label,
    Widget? leading,
  }) {
    final selected = _selectedIndex == index;
    return ListTile(
      leading: leading ?? Icon(icon),
      title: Text(label),
      selected: selected,
      onTap: () {
        Navigator.pop(context);
        setState(() {
          _selectedIndex = index;
        });
        if (index == 5) {
          _clearTasksBadge();
        }
      },
    );
  }

  Drawer _buildEmployeeDrawer() {
    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Text(
                'Menu',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ),
            _buildDrawerNavItem(
              index: 0,
              icon: Icons.location_on,
              label: 'Attendance',
            ),
            _buildDrawerNavItem(index: 1, icon: Icons.person, label: 'Profile'),
            _buildDrawerNavItem(
              index: 2,
              icon: Icons.history,
              label: 'History',
            ),
            _buildDrawerNavItem(
              index: 3,
              icon: Icons.map_outlined,
              label: 'Map',
            ),
            _buildDrawerNavItem(
              index: 4,
              icon: Icons.settings,
              label: 'Settings',
            ),
            _buildDrawerNavItem(
              index: 5,
              icon: Icons.task,
              label: 'Tasks',
              leading: _buildBadge(
                child: const Icon(Icons.task),
                count: _tasksBadgeCount,
              ),
            ),
            const Divider(),
            SwitchListTile(
              title: const Text('Share live location with admin'),
              value: _isTrackingLocation,
              secondary: Icon(
                _isTrackingLocation
                    ? Icons.location_searching
                    : Icons.location_disabled,
              ),
              onChanged: (_) async {
                Navigator.pop(context);
                await _toggleLocationTracking();
              },
            ),
            ValueListenableBuilder<DateTime?>(
              valueListenable: _locationSyncService.lastSharedListenable,
              builder: (context, value, _) {
                final text = value == null
                    ? 'Last shared: Never'
                    : 'Last shared: ${_formatTime(value)}';
                return ListTile(
                  leading: const Icon(Icons.schedule),
                  title: Text(text),
                );
              },
            ),
            ValueListenableBuilder<String?>(
              valueListenable: _locationSyncService.lastErrorListenable,
              builder: (context, value, _) {
                final err = (value ?? '').trim();
                if (err.isEmpty) return const SizedBox.shrink();
                return ListTile(
                  leading: const Icon(Icons.warning_amber_rounded),
                  title: Text('Location sharing issue: $err'),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Logout'),
              onTap: () async {
                Navigator.pop(context);
                await _logout();
              },
            ),
          ],
        ),
      ),
    );
  }

  // Navigation labels for better debugging
  static const List<String> _navLabels = [
    'Attendance',
    'Profile',
    'History',
    'Map',
    'Settings',
    'Tasks',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMobile =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    final appBarForeground =
        theme.appBarTheme.foregroundColor ?? theme.colorScheme.onPrimary;
    final List<Widget> screens = [
      const EnhancedAttendanceScreen(),
      const EmployeeProfileScreen(),
      const HistoryScreen(),
      const MapScreen(),
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
      drawer: _buildEmployeeDrawer(),
      appBar: AppBar(
        elevation: 0,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            tooltip: 'Menu',
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: Text(
          _selectedIndex == 0
              ? _buildGreetingTitle()
              : _navLabels[_selectedIndex],
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: appBarForeground,
          ),
        ),
        actions: isMobile
            ? []
            : [
                Stack(
                  children: [
                    _buildAppBarIconButton(
                      tooltip: 'Notifications',
                      icon: Icons.notifications,
                      onPressed: _openNotificationsInbox,
                      color: appBarForeground,
                    ),
                    if (_notificationsBadgeCount > 0)
                      Positioned(
                        right: 6,
                        top: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.error,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 18,
                            minHeight: 18,
                          ),
                          child: Text(
                            _notificationsBadgeCount > 99
                                ? '99+'
                                : '$_notificationsBadgeCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                _buildAppBarIconButton(
                  tooltip: _isTrackingLocation
                      ? 'Share live location with admin: ON'
                      : 'Share live location with admin: OFF',
                  icon: _isTrackingLocation
                      ? Icons.location_searching
                      : Icons.location_disabled,
                  onPressed: _toggleLocationTracking,
                  color: _isTrackingLocation
                      ? appBarForeground
                      : appBarForeground.withValues(alpha: 0.7),
                ),
                ValueListenableBuilder<DateTime?>(
                  valueListenable: _locationSyncService.lastSharedListenable,
                  builder: (context, value, _) {
                    final text = value == null
                        ? 'Last shared: Never'
                        : 'Last shared: ${_formatTime(value)}';
                    return ValueListenableBuilder<String?>(
                      valueListenable: _locationSyncService.lastErrorListenable,
                      builder: (context, err, _) {
                        final e = (err ?? '').trim();
                        final tooltip = e.isEmpty ? text : '$text\nIssue: $e';
                        return Padding(
                          padding: const EdgeInsets.only(right: AppTheme.sm),
                          child: Tooltip(
                            message: tooltip,
                            child: _buildAppBarPill(
                              icon: Icons.schedule,
                              label: text,
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
                if (_isOfflineMode)
                  Tooltip(
                    message: 'Offline mode - changes will sync when online',
                    child: Padding(
                      padding: const EdgeInsets.only(right: AppTheme.sm),
                      child: _buildAppBarPill(
                        icon: Icons.cloud_off,
                        label: 'Offline',
                        color: Colors.orange.shade200,
                      ),
                    ),
                  ),
                _buildAppBarIconButton(
                  tooltip: 'Logout',
                  icon: Icons.logout,
                  onPressed: _logout,
                ),
              ],
      ),
      body: IndexedStack(index: _selectedIndex, children: screens),
      bottomNavigationBar: isMobile
          ? null
          : BottomNavigationBar(
              currentIndex: _selectedIndex,
              onTap: (index) {
                AppLogger.debug(
                  AppLogger.tagNavigation,
                  'Navigation: ${_navLabels[_selectedIndex]} → ${_navLabels[index]}',
                );
                setState(() {
                  _selectedIndex = index;
                });

                if (index == 5) {
                  // When user opens Tasks tab, refresh and clear badge noise.
                  _clearTasksBadge();
                }
              },
              type: BottomNavigationBarType.fixed,
              items: [
                BottomNavigationBarItem(
                  icon: Icon(Icons.location_on),
                  label: 'Attendance',
                  tooltip: 'Check in/out',
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
                  icon: Icon(Icons.map_outlined),
                  label: 'Map',
                  tooltip: 'Map',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.settings),
                  label: 'Settings',
                  tooltip: 'App settings',
                ),
                BottomNavigationBarItem(
                  icon: _buildBadge(
                    child: const Icon(Icons.task),
                    count: _tasksBadgeCount,
                  ),
                  label: 'Tasks',
                  tooltip: 'Task list',
                ),
              ],
            ),
    );
  }
}

class _EmployeeNotificationsSheet extends StatefulWidget {
  final TaskService taskService;
  final VoidCallback onChanged;

  const _EmployeeNotificationsSheet({
    required this.taskService,
    required this.onChanged,
  });

  @override
  State<_EmployeeNotificationsSheet> createState() =>
      _EmployeeNotificationsSheetState();
}

class _EmployeeNotificationsSheetState
    extends State<_EmployeeNotificationsSheet> {
  bool _loading = true;
  List<Map<String, dynamic>> _items = <Map<String, dynamic>>[];

  bool _selectionMode = false;
  final Set<String> _selectedIds = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final items = await widget.taskService.listAppNotifications(limit: 50);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _items = <Map<String, dynamic>>[];
        _loading = false;
      });
    }
  }

  Future<void> _markRead(String id) async {
    try {
      await widget.taskService.markNotificationIdsRead([id]);
    } catch (_) {}
    await _load();
    widget.onChanged();
  }

  Future<void> _markUnread(String id) async {
    try {
      await widget.taskService.markNotificationIdsUnread([id]);
    } catch (_) {}
    await _load();
    widget.onChanged();
  }

  Future<void> _deleteIds(Set<String> ids) async {
    if (ids.isEmpty) return;
    final count = ids.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete notifications?'),
        content: Text(
          count == 1
              ? 'This will remove it from the inbox.'
              : 'This will remove $count notifications from the inbox.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await widget.taskService.deleteNotificationIds(ids.toList());
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
    await _load();
    widget.onChanged();
  }

  Future<void> _bulkMark({required bool read}) async {
    final ids = _selectedIds.toList();
    if (ids.isEmpty) return;
    try {
      if (read) {
        await widget.taskService.markNotificationIdsRead(ids);
      } else {
        await widget.taskService.markNotificationIdsUnread(ids);
      }
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
    await _load();
    widget.onChanged();
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _toggleSelectAll() {
    setState(() {
      if (_items.isNotEmpty && _selectedIds.length == _items.length) {
        _selectedIds.clear();
      } else {
        _selectedIds
          ..clear()
          ..addAll(
            _items
                .map((e) => (e['id'] ?? '').toString())
                .where((id) => id.length == 24),
          );
      }
    });
  }

  Future<void> _openNotification(Map<String, dynamic> n) async {
    final scope = (n['scope'] ?? '').toString();
    final action = (n['action'] ?? '').toString();
    final payload = n['payload'];

    String readPayload(String key) {
      if (payload is Map) {
        return (payload[key] ?? '').toString();
      }
      return '';
    }

    // Mark read optimistically if needed.
    final id = (n['id'] ?? '').toString();
    final readAt = n['readAt'];
    final isRead = readAt != null && readAt.toString().isNotEmpty;
    if (!isRead && id.length == 24) {
      widget.taskService.markNotificationIdsRead([id]).ignore();
      widget.onChanged();
    }

    if (scope == 'tasks' && action == 'task_assigned') {
      final taskId = readPayload('taskId');
      if (taskId.length == 24) {
        try {
          final task = await TaskService().getTaskById(taskId);
          if (!mounted) return;
          Navigator.of(context).pop();

          final employeeId = (UserService().currentUser?.id ?? '').toString();
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  EmployeeTaskDetailsScreen(task: task, employeeId: employeeId),
            ),
          );
          return;
        } catch (_) {
          // fall through
        }
      }
    }

    if (scope == 'messages' && action == 'chatMessage') {
      final convoId = readPayload('conversationId');
      if (!mounted) return;
      Navigator.of(context).pop();

      final encoded = Uri.encodeComponent(convoId);
      Navigator.of(context).pushNamed('/chat?conversationId=$encoded');
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _selectionMode
                    ? '${_selectedIds.length} selected'
                    : 'Notifications',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (_selectionMode) ...[
              IconButton(
                tooltip: 'Select all',
                onPressed: _loading ? null : _toggleSelectAll,
                icon: const Icon(Icons.select_all),
              ),
              IconButton(
                tooltip: 'Mark read',
                onPressed: _loading || _selectedIds.isEmpty
                    ? null
                    : () => _bulkMark(read: true),
                icon: const Icon(Icons.done_all),
              ),
              IconButton(
                tooltip: 'Mark unread',
                onPressed: _loading || _selectedIds.isEmpty
                    ? null
                    : () => _bulkMark(read: false),
                icon: const Icon(Icons.mark_email_unread_outlined),
              ),
              IconButton(
                tooltip: 'Delete',
                onPressed: _loading || _selectedIds.isEmpty
                    ? null
                    : () => _deleteIds(_selectedIds),
                icon: const Icon(Icons.delete_outline),
              ),
              IconButton(
                tooltip: 'Cancel',
                onPressed: () {
                  setState(() {
                    _selectionMode = false;
                    _selectedIds.clear();
                  });
                },
                icon: const Icon(Icons.close),
              ),
            ] else ...[
              IconButton(
                tooltip: 'Select',
                onPressed: _loading || _items.isEmpty
                    ? null
                    : () {
                        setState(() {
                          _selectionMode = true;
                          _selectedIds.clear();
                        });
                      },
                icon: const Icon(Icons.checklist),
              ),
              IconButton(
                tooltip: 'Refresh',
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_items.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'No notifications yet',
              style: TextStyle(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          )
        else
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: _items.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final n = _items[i];
                final title = (n['title'] ?? 'Notification').toString();
                final message = (n['message'] ?? '').toString();
                final scope = (n['scope'] ?? '').toString();
                final readAt = n['readAt'];
                final isRead = readAt != null && readAt.toString().isNotEmpty;
                final id = (n['id'] ?? '').toString();

                final selected = _selectedIds.contains(id);

                IconData icon = Icons.notifications;
                if (scope == 'tasks') icon = Icons.assignment_turned_in;
                if (scope == 'geofences') icon = Icons.location_on;
                if (scope == 'announcements') icon = Icons.campaign;

                return ListTile(
                  onLongPress: id.length == 24
                      ? () {
                          if (!_selectionMode) {
                            setState(() {
                              _selectionMode = true;
                              _selectedIds.clear();
                              _selectedIds.add(id);
                            });
                          }
                        }
                      : null,
                  onTap: () {
                    if (_selectionMode) {
                      if (id.length == 24) _toggleSelection(id);
                      return;
                    }
                    _openNotification(n);
                  },
                  leading: _selectionMode
                      ? Checkbox(
                          value: selected,
                          onChanged: id.length == 24
                              ? (_) => _toggleSelection(id)
                              : null,
                        )
                      : Icon(icon),
                  title: Text(
                    title,
                    style: TextStyle(
                      fontWeight: isRead ? FontWeight.w600 : FontWeight.w900,
                    ),
                  ),
                  subtitle: message.trim().isEmpty ? null : Text(message),
                  trailing: _selectionMode
                      ? null
                      : (isRead
                            ? TextButton(
                                onPressed: id.length == 24
                                    ? () => _markUnread(id)
                                    : null,
                                child: const Text('Mark unread'),
                              )
                            : TextButton(
                                onPressed: id.length == 24
                                    ? () => _markRead(id)
                                    : null,
                                child: const Text('Mark read'),
                              )),
                );
              },
            ),
          ),
      ],
    );
  }
}
