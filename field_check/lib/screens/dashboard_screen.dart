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
import 'package:field_check/screens/login_screen.dart';
import 'package:field_check/providers/auth_provider.dart';
import 'package:field_check/services/user_service.dart';
import 'package:field_check/services/realtime_service.dart';
import 'package:field_check/services/autosave_service.dart';
import 'package:field_check/services/location_sync_service.dart';
import 'package:field_check/services/checkout_notification_service.dart';
import 'package:field_check/services/task_service.dart';
import 'package:field_check/utils/app_theme.dart';
import 'package:field_check/utils/logger.dart';
import 'package:field_check/utils/manila_time.dart';
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

  StreamSubscription<CheckoutWarning>? _checkoutWarningSub;
  StreamSubscription<AutoCheckoutEvent>? _autoCheckoutSub;
  StreamSubscription<Map<String, dynamic>>? _taskEventsSub;
  StreamSubscription<Map<String, dynamic>>? _unreadCountsSub;
  Timer? _taskBadgeDebounce;
  String? _userModelId;
  bool _loadingUserId = true;
  bool _isTrackingLocation = true;

  int _tasksBadgeCount = 0;

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
  }

  void _subscribeToUnreadCounts() {
    _unreadCountsSub?.cancel();
    _unreadCountsSub = _realtimeService.unreadCountsStream.listen((counts) {
      final raw = counts['tasks'];
      final next = raw is int
          ? raw
          : raw is num
          ? raw.toInt()
          : int.tryParse(raw?.toString() ?? '') ?? 0;

      if (!mounted) return;
      setState(() {
        _tasksBadgeCount = next;
      });
    });
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
    _locationSyncService.stopTracking();
    _locationSyncService.dispose();
    _checkoutWarningSub?.cancel();
    _autoCheckoutSub?.cancel();
    _taskBadgeDebounce?.cancel();
    _taskEventsSub?.cancel();
    _unreadCountsSub?.cancel();
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
            _buildDrawerNavItem(index: 1, icon: Icons.map, label: 'Map'),
            _buildDrawerNavItem(index: 2, icon: Icons.person, label: 'Profile'),
            _buildDrawerNavItem(
              index: 3,
              icon: Icons.history,
              label: 'History',
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
    'Map',
    'Profile',
    'History',
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
      drawer: isMobile ? _buildEmployeeDrawer() : null,
      appBar: AppBar(
        elevation: 0,
        leading: isMobile
            ? Builder(
                builder: (context) => IconButton(
                  icon: const Icon(Icons.menu),
                  tooltip: 'Menu',
                  onPressed: () => Scaffold.of(context).openDrawer(),
                ),
              )
            : (_selectedIndex != 0
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back),
                      tooltip: 'Back to Attendance',
                      onPressed: () {
                        AppLogger.info(
                          AppLogger.tagNavigation,
                          'Navigating back to Attendance',
                        );
                        setState(() {
                          _selectedIndex = 0;
                        });
                      },
                    )
                  : null),
        title: Text(
          _navLabels[_selectedIndex],
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: appBarForeground,
          ),
        ),
        actions: isMobile
            ? []
            : [
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
