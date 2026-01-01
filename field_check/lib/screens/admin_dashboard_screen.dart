// ignore_for_file: use_build_context_synchronously, deprecated_member_use
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:field_check/screens/admin_geofence_screen.dart';
import 'package:field_check/screens/admin_reports_hub_screen.dart';
import 'package:field_check/screens/admin_settings_screen.dart';
import 'package:field_check/screens/admin_task_management_screen.dart';
import 'package:field_check/screens/manage_employees_screen.dart';
import 'package:field_check/screens/manage_admins_screen.dart';
import 'package:field_check/screens/login_screen.dart';
import 'package:field_check/services/user_service.dart';
import 'package:field_check/services/dashboard_service.dart';
import 'package:field_check/services/realtime_service.dart';
import 'package:field_check/services/employee_location_service.dart';
import 'package:field_check/services/geofence_service.dart';
import 'package:field_check/models/dashboard_model.dart';
import 'package:field_check/models/user_model.dart';
import 'package:field_check/models/geofence_model.dart';
import 'package:field_check/widgets/admin_info_modal.dart';
import 'package:intl/intl.dart';
import 'package:field_check/theme/app_theme.dart';

// Notification model for dashboard alerts
class DashboardNotification {
  final String id;
  final String title;
  final String message;
  final String type; // 'employee', 'task', 'attendance', 'geofence'
  final DateTime timestamp;
  final Map<String, dynamic>? payload;
  bool isRead;

  DashboardNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    required this.timestamp,
    this.payload,
    this.isRead = false,
  });
}

Color _notificationTypeColor(String type) {
  switch (type) {
    case 'attendance':
      return Colors.blue;
    case 'report':
      return Colors.purple;
    case 'task':
      return Colors.orange;
    case 'employee':
      return Colors.teal;
    case 'geofence':
      return Colors.green;
    default:
      return Colors.grey;
  }
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
  final GeofenceService _geofenceService = GeofenceService();

  static const int _taskLimitPerEmployee = 5;

  static const int _navDashboard = 0;
  static const int _navEmployees = 1;
  static const int _navReports = 2;
  static const int _navMore = 3;

  DashboardStats? _dashboardStats;
  RealtimeUpdates? _realtimeUpdates;
  bool _isLoading = true;
  Timer? _refreshTimer;
  bool _isFetchingRealtime = false;

  // Map data
  final Map<String, UserModel> _employees = {};
  final Map<String, LatLng> _liveLocations = {};
  final Map<String, List<LatLng>> _trails = {};

  StreamSubscription<List<EmployeeLocation>>? _employeeLocationsSub;
  StreamSubscription<List<EmployeeLocation>>? _employeeLocationsSnapshotSub;
  StreamSubscription<Map<String, dynamic>>? _liveLocationFallbackSub;
  final Map<String, EmployeeLocation> _employeeLocations = {};
  static const LatLng _defaultCenter = LatLng(14.5995, 120.9842); // Manila
  bool _showNoEmployeesPopup = true;

  String? _selectedEmployeeId;

  final MapController _mapController = MapController();
  final TextEditingController _employeeSearchController = TextEditingController();
  String _employeeStatusFilter = 'all';
  Timer? _employeeSearchDebounce;

  static final Color _panelBorderBlue = Colors.blue.shade200;
  static const Color _panelTextPrimary = Colors.black87;
  static const Color _panelTextSecondary = Colors.black54;
  static const double _controlFontSize = 13;

  void _subscribeToLiveLocationFallback() {
    _liveLocationFallbackSub?.cancel();
    _liveLocationFallbackSub = _realtimeService.locationStream.listen((data) {
      try {
        final String userId =
            (data['employeeId'] ?? data['userId'] ?? '') as String;
        final num? latN = data['latitude'] as num?;
        final num? lngN = data['longitude'] as num?;
        if (userId.isEmpty || latN == null || lngN == null) {
          return;
        }

        final pos = LatLng(latN.toDouble(), lngN.toDouble());
        if (!mounted) return;
        setState(() {
          _liveLocations[userId] = pos;
        });
      } catch (_) {}
    });
  }

  String _nearbyMode = 'off'; // off | admin | geofence
  double _nearbyRadiusMeters = 2000;
  List<Geofence> _geofences = [];
  Geofence? _selectedNearbyGeofence;

  // Notification system
  final List<DashboardNotification> _notifications = [];
  final Set<String> _snackDedupKeys = {};

  StreamSubscription<Map<String, dynamic>>? _adminNotifSub;

  List<Widget> get _screens => [
    _buildDashboardOverview(),
    const ManageEmployeesScreen(),
    const ManageAdminsScreen(),
    const AdminGeofenceScreen(),
    const AdminReportsHubScreen(),
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

  Widget _buildNotificationItem(DashboardNotification notif) {
    final color = _notificationTypeColor(notif.type);
    final ts = DateFormat('MMM d, HH:mm').format(notif.timestamp);
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: () {
          setState(() {
            notif.isRead = true;
          });
          _showNotificationDetails(notif);
        },
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            shape: BoxShape.circle,
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Icon(
            notif.type == 'attendance'
                ? Icons.access_time
                : (notif.type == 'report'
                    ? Icons.description
                    : Icons.notifications),
            color: color,
            size: 18,
          ),
        ),
        title: Text(
          notif.title,
          style: TextStyle(
            fontWeight: notif.isRead ? FontWeight.w500 : FontWeight.w700,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(notif.message),
            const SizedBox(height: 4),
            Text(
              ts,
              style: const TextStyle(
                fontSize: AppTheme.fontSizeSm,
                color: AppTheme.textSecondaryColor,
              ),
            ),
          ],
        ),
        trailing: notif.isRead
            ? null
            : Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
              ),
      ),
    );
  }

  void _showNotificationDetails(DashboardNotification notif) {
    final payload = notif.payload ?? const <String, dynamic>{};
    final ts = DateFormat('yyyy-MM-dd HH:mm:ss').format(notif.timestamp);

    String? employeeName;
    String? employeeId;
    String? action;

    try {
      employeeName = (payload['name'] ?? payload['employeeName']) as String?;
    } catch (_) {
      employeeName = null;
    }
    try {
      employeeId = (payload['employeeId'] ?? payload['userId']) as String?;
    } catch (_) {
      employeeId = null;
    }
    try {
      action = payload['action'] as String?;
    } catch (_) {
      action = null;
    }

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(notif.title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                notif.message,
                style: const TextStyle(
                  fontSize: AppTheme.fontSizeMd,
                  height: 1.35,
                  color: AppTheme.textPrimaryColor,
                ),
              ),
              const SizedBox(height: 12),
              _buildDetailRow('Type:', notif.type),
              _buildDetailRow('Action:', action ?? '-'),
              _buildDetailRow('Employee:', employeeName ?? '-'),
              _buildDetailRow('Employee ID:', employeeId ?? '-'),
              _buildDetailRow('Time:', ts),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          if (notif.type == 'report')
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                setState(() {
                  _selectedIndex = 4;
                });
              },
              icon: const Icon(Icons.description),
              label: const Text('Go to reports'),
            ),
        ],
      ),
    );
  }

  Widget _buildNotificationsPanel() {
    final items = _notifications.take(5).toList();
    final unread = _notifications.where((n) => !n.isRead).length;

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
                Row(
                  children: [
                    const Text(
                      'Notifications',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (unread > 0) ...[
                      const SizedBox(width: 8),
                      _buildNotificationBadge(unread),
                    ],
                  ],
                ),
                TextButton(
                  onPressed: _showNotificationsInbox,
                  child: const Text('Open'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (items.isEmpty)
              Text(
                'No notifications yet',
                style: TextStyle(color: Colors.grey.shade600),
              )
            else
              ...items.map(_buildNotificationItem),
          ],
        ),
      ),
    );
  }

  Future<void> _loadGeofencesForNearby() async {
    try {
      final fences = await _geofenceService.fetchGeofences();
      if (!mounted) return;
      setState(() {
        _geofences = fences;
        if (_selectedNearbyGeofence != null) {
          final stillExists = _geofences.any(
            (g) => g.id != null && g.id == _selectedNearbyGeofence!.id,
          );
          if (!stillExists) {
            _selectedNearbyGeofence = null;
          }
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _geofences = [];
      });
    }
  }

  LatLng? _nearbyCenter() {
    if (_nearbyMode == 'geofence') {
      final g = _selectedNearbyGeofence;
      if (g == null) return null;
      return LatLng(g.latitude, g.longitude);
    }

    if (_nearbyMode == 'admin') {
      final adminId = _userService.currentUser?.id;
      if (adminId == null) return null;
      return _liveLocations[adminId];
    }

    return null;
  }

  bool _passesEmployeeFilters(String userId) {
    final user = _employees[userId];
    final loc = _employeeLocations[userId];
    final activeTaskCount = loc?.activeTaskCount ?? user?.activeTaskCount ?? 0;
    final isBusy = activeTaskCount >= _taskLimitPerEmployee;
    final isOnline = _liveLocations.containsKey(userId);

    if (!isOnline) return false;

    if (_employeeStatusFilter == 'busy' && !isBusy) return false;
    if (_employeeStatusFilter == 'available' && isBusy) return false;

    final q = _employeeSearchController.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      final name = (user?.name ?? '').toLowerCase();
      final email = (user?.email ?? '').toLowerCase();
      if (!name.contains(q) && !email.contains(q)) {
        return false;
      }
    }

    final center = _nearbyCenter();
    if (center != null) {
      final pos = _liveLocations[userId];
      if (pos == null) return false;
      final d = const Distance().as(LengthUnit.Meter, center, pos);
      if (d > _nearbyRadiusMeters) return false;
    }

    return true;
  }

  void _panTo(LatLng center, {double zoom = 14}) {
    try {
      _mapController.move(center, zoom);
    } catch (_) {}
  }

  void _onEmployeeSearchChanged() {
    _employeeSearchDebounce?.cancel();
    _employeeSearchDebounce = Timer(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      setState(() {});
    });
  }

  Widget _buildMapControls() {
    final hasNearbyCenter = _nearbyCenter() != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _employeeSearchController,
          decoration: InputDecoration(
            hintText: 'Search employee…',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _employeeSearchController.text.isEmpty
                ? null
                : IconButton(
                    onPressed: () {
                      setState(() {
                        _employeeSearchController.clear();
                      });
                    },
                    icon: const Icon(Icons.clear),
                  ),
            isDense: true,
            border: const OutlineInputBorder(),
          ),
          style: const TextStyle(
            color: _panelTextPrimary,
            fontSize: _controlFontSize,
          ),
          onChanged: (_) => _onEmployeeSearchChanged(),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: const Text(
                'All',
                style: TextStyle(
                  color: _panelTextPrimary,
                  fontSize: _controlFontSize,
                  fontWeight: FontWeight.w600,
                ),
              ),
              selected: _employeeStatusFilter == 'all',
              onSelected: (_) => setState(() => _employeeStatusFilter = 'all'),
              selectedColor: Colors.blue.shade50,
              shape: StadiumBorder(side: BorderSide(color: _panelBorderBlue)),
            ),
            ChoiceChip(
              label: const Text(
                'Available',
                style: TextStyle(
                  color: _panelTextPrimary,
                  fontSize: _controlFontSize,
                  fontWeight: FontWeight.w600,
                ),
              ),
              selected: _employeeStatusFilter == 'available',
              onSelected: (_) =>
                  setState(() => _employeeStatusFilter = 'available'),
              selectedColor: Colors.blue.shade50,
              shape: StadiumBorder(side: BorderSide(color: _panelBorderBlue)),
            ),
            ChoiceChip(
              label: const Text(
                'Busy',
                style: TextStyle(
                  color: _panelTextPrimary,
                  fontSize: _controlFontSize,
                  fontWeight: FontWeight.w600,
                ),
              ),
              selected: _employeeStatusFilter == 'busy',
              onSelected: (_) => setState(() => _employeeStatusFilter = 'busy'),
              selectedColor: Colors.blue.shade50,
              shape: StadiumBorder(side: BorderSide(color: _panelBorderBlue)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'off', label: Text('Nearby: Off')),
                  ButtonSegment(value: 'admin', label: Text('Admin')),
                  ButtonSegment(value: 'geofence', label: Text('Geofence')),
                ],
                selected: <String>{_nearbyMode},
                onSelectionChanged: (v) {
                  final next = v.isEmpty ? 'off' : v.first;
                  setState(() {
                    _nearbyMode = next;
                  });
                  final center = _nearbyCenter();
                  if (center != null) {
                    _panTo(center, zoom: 14);
                  }
                },
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  _employeeSearchController.clear();
                  _employeeStatusFilter = 'all';
                  _nearbyMode = 'off';
                  _nearbyRadiusMeters = 2000;
                  _selectedNearbyGeofence = null;
                });
              },
              icon: const Icon(Icons.clear_all),
              label: const Text('Reset'),
            ),
          ],
        ),
        if (_nearbyMode == 'geofence') ...[
          const SizedBox(height: 10),
          DropdownButtonFormField<Geofence>(
            value: _selectedNearbyGeofence,
            decoration: const InputDecoration(
              labelText: 'Geofence center',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: _geofences
                .map(
                  (g) => DropdownMenuItem<Geofence>(
                    value: g,
                    child: Text(
                      g.labelLetter == null
                          ? g.name
                          : '${g.name} • ${g.labelLetter}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: (g) {
              setState(() {
                _selectedNearbyGeofence = g;
              });
              final center = _nearbyCenter();
              if (center != null) {
                _panTo(center, zoom: 14);
              }
            },
          ),
          if (_nearbyMode == 'geofence' && _geofences.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'No geofences available',
                style: TextStyle(
                  fontSize: 12,
                  color: _panelTextSecondary,
                ),
              ),
            ),
        ],
        if (_nearbyMode != 'off') ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Slider(
                  min: 250,
                  max: 10000,
                  divisions: 39,
                  label: _nearbyRadiusMeters >= 1000
                      ? '${(_nearbyRadiusMeters / 1000).toStringAsFixed(1)} km'
                      : '${_nearbyRadiusMeters.toStringAsFixed(0)} m',
                  value: _nearbyRadiusMeters,
                  onChanged: (v) {
                    setState(() {
                      _nearbyRadiusMeters = v;
                    });
                  },
                ),
              ),
              const SizedBox(width: 10),
              Text(
                _nearbyRadiusMeters >= 1000
                    ? '${(_nearbyRadiusMeters / 1000).toStringAsFixed(1)} km'
                    : '${_nearbyRadiusMeters.toStringAsFixed(0)} m',
                style: const TextStyle(
                  fontSize: 12,
                  color: _panelTextPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if (!hasNearbyCenter)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _nearbyMode == 'admin'
                    ? 'Admin location not available for Nearby mode.'
                    : 'Select a geofence to enable Nearby mode.',
                style: const TextStyle(
                  fontSize: 12,
                  color: _panelTextSecondary,
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildNotificationBadge(int count) {
    final text = count > 99 ? '99+' : '$count';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.red,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white, width: 1),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  void _showNotificationsInbox() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final unreadCount = _notifications.where((n) => !n.isRead).length;
        return SafeArea(
          child: FractionallySizedBox(
            heightFactor: 0.85,
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
                            'Notifications',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (unreadCount > 0) ...[
                            const SizedBox(width: 8),
                            _buildNotificationBadge(unreadCount),
                          ],
                        ],
                      ),
                      TextButton.icon(
                        onPressed: () {
                          if (!mounted) return;
                          setState(() {
                            for (final n in _notifications) {
                              n.isRead = true;
                            }
                          });
                        },
                        icon: const Icon(Icons.done_all, size: 18),
                        label: const Text('Mark all read'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: _notifications.isEmpty
                        ? Center(
                            child: Text(
                              'No notifications',
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                          )
                        : ListView.builder(
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
          ),
        );
      },
    );
  }

  void _showEmployeeAvailabilityDialog() {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final total = _dashboardStats?.users.totalEmployees ?? 0;
        final active = _dashboardStats?.users.activeEmployees ?? 0;
        final inactive = (total - active).clamp(0, total);
        return AlertDialog(
          title: const Text('Employee Availability'),
          content: Text('Total: $total\nActive: $active\nInactive: $inactive'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  void _showGeofenceDetailsDialog() {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final total = _dashboardStats?.geofences.total ?? 0;
        final active = _dashboardStats?.geofences.active ?? 0;
        final inactive = (total - active).clamp(0, total);
        return AlertDialog(
          title: const Text('Geofences'),
          content: Text('Total: $total\nActive: $active\nInactive: $inactive'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  void _showTasksDialog() {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final total = _dashboardStats?.tasks.total ?? 0;
        final pending = _dashboardStats?.tasks.pending ?? 0;
        final completed = _dashboardStats?.tasks.completed ?? 0;
        return AlertDialog(
          title: const Text('Tasks'),
          content: Text('Total: $total\nPending: $pending\nCompleted: $completed'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  void _showAttendanceDialog() {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final today = _dashboardStats?.attendance.today ?? 0;
        final checkIns = _dashboardStats?.attendance.todayCheckIns ?? 0;
        final checkOuts = _dashboardStats?.attendance.todayCheckOuts ?? 0;
        return AlertDialog(
          title: const Text("Today's Attendance"),
          content: Text('Records: $today\nCheck-ins: $checkIns\nCheck-outs: $checkOuts'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _adminNotifSub?.cancel();
    _liveLocationFallbackSub?.cancel();
    _refreshTimer?.cancel();
    _employeeLocationsSub?.cancel();
    _employeeLocationsSnapshotSub?.cancel();
    _employeeSearchDebounce?.cancel();
    _employeeSearchController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _initLocationService() async {
    try {
      await _locationService.initialize();
      _employeeLocationsSnapshotSub?.cancel();
      _employeeLocationsSnapshotSub = _locationService.employeeLocationsStream.listen((locations) {
        if (mounted) {
          setState(() {
            _employeeLocations.clear();
            for (final loc in locations) {
              _employeeLocations[loc.employeeId] = loc;
            }
          });
        }
      });

      _subscribeToLocations();
    } catch (_) {}
  }

  void _subscribeToAdminNotifications() {
    _adminNotifSub?.cancel();
    _adminNotifSub = _realtimeService.notificationStream.listen((data) {
      try {
        final action = (data['action'] ?? '') as String;
        if (action != 'employeeOnline') {
          return;
        }
        final employeeName = (data['name'] ?? 'Employee') as String;
        final key = 'employeeOnline:$employeeName';
        if (_snackDedupKeys.contains(key)) return;
        _snackDedupKeys.add(key);

        setState(() {
          _notifications.insert(
            0,
            DashboardNotification(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              title: 'Employee Online',
              message: '$employeeName is now online.',
              type: 'employee',
              timestamp: DateTime.now(),
              payload: data,
            ),
          );

          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$employeeName is online'),
              duration: const Duration(seconds: 2),
            ),
          );
        });

        if (mounted) {
          setState(() {});
        }
      } catch (_) {}
    });
  }

  Future<void> _initRealtimeService() async {
    await _realtimeService.initialize();

    _subscribeToAdminNotifications();
    _subscribeToLiveLocationFallback();

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

      if (type != 'attendance' && type != 'report') {
        return;
      }

      String title;
      String message;
      String notifType = type;

      String? snackbarKey;
      bool shouldSnackbar = false;

      if (type == 'attendance') {
        if (action == 'new') {
          title = 'Employee check-in';
          message = 'A new check-in was recorded.';
          shouldSnackbar = true;
          snackbarKey = 'attendance:new';
        } else if (action == 'updated') {
          title = 'Employee check-out';
          message = 'An attendance record was updated.';
          shouldSnackbar = true;
          snackbarKey = 'attendance:updated';
        } else {
          title = 'Attendance activity';
          message = 'Attendance activity detected.';
        }
      } else {
        if (action == 'new') {
          title = 'New report submitted';
          message = 'A new report was created.';
          shouldSnackbar = true;
          snackbarKey = 'report:new';
        } else if (action == 'updated') {
          title = 'Report updated';
          message = 'A report was updated.';
          shouldSnackbar = true;
          snackbarKey = 'report:updated';
        } else {
          title = 'Report activity';
          message = 'Report activity detected.';
        }
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
            payload: event['data'] is Map<String, dynamic>
                ? event['data'] as Map<String, dynamic>
                : null,
          ),
        );
        if (_notifications.length > 50) {
          _notifications.removeLast();
        }
      });

      if (shouldSnackbar) {
        final key = snackbarKey ?? '$notifType:${action.isEmpty ? 'event' : action}';
        final isDup = _snackDedupKeys.contains(key);
        if (!isDup) {
          _snackDedupKeys.add(key);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$title - $message'),
              duration: const Duration(seconds: 4),
            ),
          );

          Future<void>.delayed(const Duration(seconds: 6)).then((_) {
            if (!mounted) return;
            _snackDedupKeys.remove(key);
          });
        }
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
    if (index == _navMore) {
      _showMoreSheet();
      return;
    }

    setState(() {
      switch (index) {
        case _navDashboard:
          _selectedIndex = 0;
          break;
        case _navEmployees:
          _selectedIndex = 1;
          break;
        case _navReports:
          _selectedIndex = 4;
          break;
        default:
          _selectedIndex = 0;
      }
    });
  }

  int _currentNavIndex() {
    switch (_selectedIndex) {
      case 0:
        return _navDashboard;
      case 1:
        return _navEmployees;
      case 4:
        return _navReports;
      case 2:
      case 3:
      case 5:
      case 6:
        return _navMore;
      default:
        return _navDashboard;
    }
  }

  Future<void> _showMoreSheet() async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('Admin Info'),
                onTap: () {
                  Navigator.pop(ctx);
                  if (!mounted) return;
                  showModalBottomSheet<void>(
                    context: context,
                    showDragHandle: true,
                    isScrollControlled: true,
                    builder: (_) {
                      return const FractionallySizedBox(
                        heightFactor: 0.9,
                        child: AdminInfoModal(),
                      );
                    },
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.admin_panel_settings),
                title: const Text('Admins'),
                onTap: () {
                  Navigator.pop(ctx);
                  if (!mounted) return;
                  setState(() {
                    _selectedIndex = 2;
                  });
                },
              ),
              ListTile(
                leading: const Icon(Icons.map),
                title: const Text('Geofences'),
                onTap: () {
                  Navigator.pop(ctx);
                  if (!mounted) return;
                  setState(() {
                    _selectedIndex = 3;
                  });
                },
              ),
              ListTile(
                leading: const Icon(Icons.task),
                title: const Text('Tasks'),
                onTap: () {
                  Navigator.pop(ctx);
                  if (!mounted) return;
                  setState(() {
                    _selectedIndex = 6;
                  });
                },
              ),
              ListTile(
                leading: const Icon(Icons.settings),
                title: const Text('Settings'),
                onTap: () {
                  Navigator.pop(ctx);
                  if (!mounted) return;
                  setState(() {
                    _selectedIndex = 5;
                  });
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _showEmployeeDetailsBottomSheet(String userId, UserModel? user) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _buildEmployeeDetailsContent(userId, user),
          ),
        );
      },
    );
  }

  Widget _buildEmployeeSidePanel() {
    return Card(
      elevation: 4,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: _selectedEmployeeId == null
            ? _buildEmployeeEmptyState()
            : _buildEmployeeDetailsContent(
                _selectedEmployeeId!,
                _employees[_selectedEmployeeId!],
              ),
      ),
    );
  }

  Widget _buildEmployeeEmptyState() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Employee',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'Tap an employee marker to view details.',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
        ),
      ],
    );
  }

  Widget _buildEmployeeDetailsContent(String userId, UserModel? user) {
    final isOnline = _liveLocations.containsKey(userId);
    final loc = _employeeLocations[userId];
    final activeTaskCount = loc?.activeTaskCount ?? user?.activeTaskCount ?? 0;
    final isBusy = activeTaskCount >= _taskLimitPerEmployee;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            user?.name ?? 'Employee',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            user?.email ?? '',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 12),
          _buildStatusRow(
            'Online Status',
            isOnline ? 'Online' : 'Offline',
            isOnline ? Colors.green : Colors.grey,
          ),
          _buildStatusRow(
            'Task Load',
            '$activeTaskCount / $_taskLimitPerEmployee',
            isBusy ? Colors.red : Colors.blue,
          ),
          const SizedBox(height: 12),
          if (_liveLocations.containsKey(userId))
            Text(
              'Lat: ${_liveLocations[userId]!.latitude.toStringAsFixed(4)}\nLng: ${_liveLocations[userId]!.longitude.toStringAsFixed(4)}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            )
          else
            Text(
              'Location not available',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          const SizedBox(height: 8),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(top: 8),
              title: const Text(
                'More details',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              children: [
                SizedBox(
                  height: 220,
                  child: DefaultTabController(
                    length: 2,
                    child: Column(
                      children: [
                        const TabBar(
                          tabs: [
                            Tab(text: 'Details'),
                            Tab(text: 'Status'),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: TabBarView(
                            children: [
                              SingleChildScrollView(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildDetailRow(
                                      'Name',
                                      user?.name ?? 'N/A',
                                    ),
                                    _buildDetailRow(
                                      'Email',
                                      user?.email ?? 'N/A',
                                    ),
                                    _buildDetailRow(
                                      'Phone',
                                      user?.phone ?? 'N/A',
                                    ),
                                    _buildDetailRow(
                                      'Role',
                                      user?.role ?? 'N/A',
                                    ),
                                  ],
                                ),
                              ),
                              SingleChildScrollView(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildStatusRow(
                                      'Online Status',
                                      isOnline ? 'Online' : 'Offline',
                                      isOnline ? Colors.green : Colors.grey,
                                    ),
                                    _buildStatusRow(
                                      'Active Tasks',
                                      '$activeTaskCount',
                                      isBusy ? Colors.red : Colors.blue,
                                    ),
                                    if (loc != null)
                                      _buildStatusRow(
                                        'Workload Score',
                                        loc.workloadScore.toStringAsFixed(2),
                                        _getWorkloadColor(loc.workloadScore),
                                      ),
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
              ],
            ),
          ),
        ],
      ),
    );
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
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.notifications),
                if (_notifications.any((n) => !n.isRead))
                  Positioned(
                    right: -2,
                    top: -2,
                    child: _buildNotificationBadge(
                      _notifications.where((n) => !n.isRead).length,
                    ),
                  ),
              ],
            ),
            onPressed: _showNotificationsInbox,
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
          BottomNavigationBarItem(
            icon: Icon(Icons.people),
            label: 'Employees',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.assessment),
            label: 'Reports',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.more_horiz), label: 'More'),
        ],
        currentIndex: _currentNavIndex(),
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 900;
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
            if (isWide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _buildWorldMapSection(isWide: true)),
                  const SizedBox(width: 12),
                  SizedBox(width: 380, child: _buildEmployeeSidePanel()),
                ],
              )
            else
              _buildWorldMapSection(isWide: false),

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
      },
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

  Widget _buildWorldMapSection({required bool isWide}) {
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
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _panelBorderBlue, width: 1.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Map Controls',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: _panelTextPrimary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _buildMapControls(),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Live Employee Tracking',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: _panelTextPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Online: ${_liveLocations.length} employees',
                  style: const TextStyle(
                    fontSize: 12,
                    color: _panelTextSecondary,
                    fontWeight: FontWeight.w600,
                  ),
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
                Container(
                  margin: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _panelBorderBlue, width: 1.5),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: FlutterMap(
                    mapController: _mapController,
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
                            .where((e) => _passesEmployeeFilters(e.key))
                            .map((entry) {
                              final user = _employees[entry.key];
                              final empLocation = _employeeLocations[entry.key];

                              final activeTaskCount =
                                  empLocation?.activeTaskCount ??
                                  user?.activeTaskCount ??
                                  0;
                              final isBusy =
                                  activeTaskCount >= _taskLimitPerEmployee;

                              Color markerColor;
                              IconData markerIcon;

                              if (isBusy) {
                                markerColor = Colors.red;
                                markerIcon = Icons.schedule;
                              } else {
                                final status = empLocation?.status;
                                if (status == EmployeeStatus.available) {
                                  markerColor = Colors.green;
                                  markerIcon = Icons.check_circle;
                                } else {
                                  markerColor = Colors.blue;
                                  markerIcon = Icons.directions_run;
                                }
                              }

                              return Marker(
                                point: entry.value,
                                width: 40,
                                height: 40,
                                child: GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _selectedEmployeeId = entry.key;
                                    });

                                    _panTo(entry.value, zoom: 16);

                                    if (!isWide) {
                                      _showEmployeeDetailsBottomSheet(
                                        entry.key,
                                        user,
                                      );
                                    }
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
                          border: Border.all(color: _panelBorderBlue, width: 1.5),
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

  void _autoPanToEmployee(String userId, LatLng location) {
    _showEmployeeDetails(userId, _employees[userId]);
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

  Color _getTaskStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return Colors.green;
      case 'in_progress':
        return Colors.orange;
      case 'pending':
        return Colors.blue;
      case 'blocked':
        return Colors.red;
      default:
        return Colors.grey;
    }
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

  Future<void> _initMapData() async {
    await _loadEmployeesForMap();
    await _loadOnlineEmployeeLocations();
    await _loadGeofencesForNearby();
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
      } else {
        debugPrint('⚠️ No response from getOnlineEmployees');
      }
    } catch (e) {
      debugPrint('❌ Error loading online employee locations: $e');
    }
  }

  void _subscribeToLocations() {
    _employeeLocationsSub?.cancel();
    _employeeLocationsSub = _locationService.employeeLocationsStream.listen((locations) {
      if (!mounted) return;
      setState(() {
        final wasEmpty = _liveLocations.isEmpty;
        for (final empLoc in locations) {
          final pos = LatLng(empLoc.latitude, empLoc.longitude);
          _liveLocations[empLoc.employeeId] = pos;

          final trail = _trails[empLoc.employeeId] ?? <LatLng>[];
          if (trail.isEmpty || trail.last != pos) {
            trail.add(pos);
            if (trail.length > 50) {
              trail.removeRange(0, trail.length - 50);
            }
            _trails[empLoc.employeeId] = trail;
          }
        }

        if (wasEmpty && _liveLocations.isNotEmpty) {
          _showNoEmployeesPopup = false;
        }
      });
    });
  }
}
