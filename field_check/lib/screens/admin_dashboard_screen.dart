// ignore_for_file: use_build_context_synchronously, deprecated_member_use
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:field_check/screens/admin_geofence_screen.dart';
import 'package:field_check/screens/admin_reports_hub_screen.dart';
import 'package:field_check/screens/admin_settings_screen.dart';
import 'package:field_check/screens/admin_task_management_screen.dart';
import 'package:field_check/screens/admin_world_map_screen.dart';
import 'package:field_check/screens/manage_employees_screen.dart';
import 'package:field_check/screens/manage_admins_screen.dart';
import 'package:field_check/screens/login_screen.dart';
import 'package:field_check/widgets/app_widgets.dart';
import 'package:field_check/services/user_service.dart';
import 'package:field_check/services/dashboard_service.dart';
import 'package:field_check/services/realtime_service.dart';
import 'package:field_check/services/employee_location_service.dart';
import 'package:field_check/services/geofence_service.dart';
import 'package:field_check/services/location_service.dart';
import 'package:field_check/models/dashboard_model.dart';
import 'package:field_check/models/user_model.dart';
import 'package:field_check/models/geofence_model.dart';
import 'package:field_check/widgets/admin_info_modal.dart';
import 'package:field_check/utils/manila_time.dart';
import 'package:field_check/utils/app_theme.dart';
import 'package:url_launcher/url_launcher.dart';

class _AdminNavIntent extends Intent {
  final int index;
  const _AdminNavIntent(this.index);
}

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

class _StatMetric {
  final String label;
  final String value;
  final Color? color;

  const _StatMetric({required this.label, required this.value, this.color});
}

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  int _selectedIndex = 0;

  bool _railHoverExpanded = false;
  final UserService _userService = UserService();
  final DashboardService _dashboardService = DashboardService();
  final RealtimeService _realtimeService = RealtimeService();
  final EmployeeLocationService _locationService = EmployeeLocationService();
  final GeofenceService _geofenceService = GeofenceService();
  final LocationService _deviceLocationService = LocationService();

  static const int _taskLimitPerEmployee = 3;

  static const int _navDashboard = 0;
  static const int _navEmployees = 1;
  static const int _navReports = 2;
  static const int _navMore = 3;

  DashboardStats? _dashboardStats;
  RealtimeUpdates? _realtimeUpdates;
  bool _isLoading = true;
  Timer? _refreshTimer;
  bool _isFetchingRealtime = false;
  bool _isFetchingDashboard = false;
  Timer? _dashboardReloadDebounce;
  bool _dashboardDirty = false;
  Timer? _liveLocationUiThrottle;
  bool _liveLocationDirty = false;
  Timer? _onlineEmployeesReloadDebounce;

  // Map data
  final Map<String, UserModel> _employees = {};
  final Map<String, String> _employeeIdAlias = {};
  final Map<String, LatLng> _liveLocations = {};
  final Map<String, List<LatLng>> _trails = {};

  final Map<String, DateTime> _lastGpsUpdate = {};
  Timer? _gpsSweepTimer;
  static const Duration _gpsOnlineWindow = Duration(minutes: 2);

  final Set<String> _resolvingEmployeeIds = <String>{};

  StreamSubscription<List<EmployeeLocation>>? _employeeLocationsSub;
  StreamSubscription<List<EmployeeLocation>>? _employeeLocationsSnapshotSub;
  StreamSubscription<Map<String, dynamic>>? _liveLocationFallbackSub;
  StreamSubscription<Map<String, dynamic>>? _attendanceStreamSub;
  StreamSubscription<Map<String, dynamic>>? _taskStreamSub;
  StreamSubscription<Map<String, dynamic>>? _eventStreamSub;
  StreamSubscription<int>? _onlineCountSub;
  final Map<String, EmployeeLocation> _employeeLocations = {};
  static const LatLng _defaultCenter = LatLng(14.5995, 120.9842); // Manila
  bool _showNoEmployeesPopup = true;

  LatLng? _adminMarkerLocation;
  bool _adminLocationRequested = false;

  bool _pendingOnlineEmployeeRefresh = false;

  bool _isInspectorCollapsed = true;

  String? _selectedEmployeeId;

  // Employee inspection stack (clicked history)
  final List<String> _inspectionStack = <String>[];
  int _inspectionIndex = -1;

  final MapController _mapController = MapController();
  final TextEditingController _employeeSearchController =
      TextEditingController();
  String _employeeStatusFilter = 'all';
  Timer? _employeeSearchDebounce;

  static final Color _panelBorderBlue = Colors.blue.shade200;
  static const Color _adminMarkerColor = Color(0xFF5C4EF5);
  static const Color _panelTextPrimary = Colors.black87;
  static const double _controlFontSize = 13;

  Widget _maybeTooltip({required String message, required Widget child}) {
    if (kIsWeb) return child;
    return Tooltip(message: message, child: child);
  }

  String _canonicalUserId(String rawId) {
    final id = rawId.trim();
    if (id.isEmpty) return id;
    if (_employees.containsKey(id)) return id;
    final mapped = _employeeIdAlias[id];
    if (mapped != null && mapped.trim().isNotEmpty) {
      return mapped.trim();
    }
    return id;
  }

  String _selectedEmployeeLabel() {
    final selectedId = _inspectedEmployeeId;
    if (selectedId == null) return '(none)';

    final selectedUser = _employees[selectedId];
    final code = (selectedUser?.employeeId ?? '').trim();
    if (code.isNotEmpty) return code;

    final name = (selectedUser?.name ?? '').trim();
    if (name.isNotEmpty) return name;

    final locName = (_employeeLocations[selectedId]?.name ?? '').trim();
    if (locName.isNotEmpty) return locName;

    return selectedId;
  }

  String _adminMarkerLabel() {
    final admin = _userService.currentUser;
    final name = (admin?.name ?? '').trim();
    if (name.isNotEmpty) return name;
    final email = (admin?.email ?? '').trim();
    if (email.isNotEmpty) return email;
    final username = (admin?.username ?? '').trim();
    if (username.isNotEmpty) return username;
    return 'Admin';
  }

  String? _currentAdminId() {
    final id = _userService.currentUser?.id;
    if (id == null) return null;
    final trimmed = id.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  LatLng? _adminLiveLocation() {
    final adminId = _currentAdminId();
    if (adminId == null) return null;
    return _liveLocations[adminId];
  }

  LatLng? _adminLocationFromProfile(UserModel? profile) {
    if (profile == null) return null;
    final lat = profile.lastLatitude;
    final lng = profile.lastLongitude;
    if (lat == null || lng == null) return null;
    return LatLng(lat, lng);
  }

  void _setAdminMarkerLocation(LatLng location) {
    if (!mounted) return;
    if (_adminMarkerLocation == location) return;
    setState(() {
      _adminMarkerLocation = location;
    });
  }

  Future<void> _ensureAdminMarkerLocation() async {
    if (_adminMarkerLocation != null) return;

    final live = _adminLiveLocation();
    if (live != null) {
      _setAdminMarkerLocation(live);
      return;
    }

    final cached = _adminLocationFromProfile(_userService.currentUser);
    if (cached != null) {
      _setAdminMarkerLocation(cached);
      return;
    }

    try {
      final profile = await _userService.getProfile();
      final refreshed = _adminLocationFromProfile(profile);
      if (refreshed != null) {
        _setAdminMarkerLocation(refreshed);
        return;
      }
    } catch (_) {}

    if (_adminLocationRequested) return;
    _adminLocationRequested = true;
    try {
      final pos = await _deviceLocationService.getCurrentLocation();
      _setAdminMarkerLocation(LatLng(pos.latitude, pos.longitude));
    } catch (_) {}
  }

  String _employeeSortLabel(String userId) {
    final user = _employees[userId];
    final code = (user?.employeeId ?? '').trim();
    if (code.isNotEmpty) return code.toLowerCase();
    final name = (user?.name ?? '').trim();
    if (name.isNotEmpty) return name.toLowerCase();
    final locName = (_employeeLocations[userId]?.name ?? '').trim();
    if (locName.isNotEmpty) return locName.toLowerCase();
    return userId.toLowerCase();
  }

  List<String> _availableInspectionIds() {
    final adminId = _currentAdminId();
    final ids = _liveLocations.keys
        .where((id) => adminId == null || id != adminId)
        .where((id) => _passesEmployeeFilters(id))
        .toList();
    ids.sort((a, b) => _employeeSortLabel(a).compareTo(_employeeSortLabel(b)));
    return ids;
  }

  void _setInspectionFromRoster(List<String> roster, int nextIndex) {
    if (roster.isEmpty) return;
    final idx = nextIndex.clamp(0, roster.length - 1);
    final nextId = roster[idx];
    setState(() {
      _inspectionStack
        ..clear()
        ..addAll(roster);
      _inspectionIndex = idx;
      _selectedEmployeeId = nextId;
      _isInspectorCollapsed = false;
    });

    final pos = _liveLocations[nextId];
    if (pos != null) {
      _panTo(pos, zoom: 16);
    }
    _ensureEmployeeLoaded(nextId);
  }

  void _rebuildEmployeeIdAlias() {
    _employeeIdAlias.clear();
    for (final emp in _employees.values) {
      final alt = emp.employeeId;
      if (alt == null) continue;
      final key = alt.trim();
      if (key.isEmpty) continue;
      _employeeIdAlias[key] = emp.id;
    }
  }

  void _normalizeMapsToCanonical() {
    if (_employeeIdAlias.isEmpty) return;

    if (_liveLocations.isNotEmpty) {
      final entries = _liveLocations.entries.toList();
      _liveLocations.clear();
      for (final e in entries) {
        final id = _canonicalUserId(e.key);
        if (id.isEmpty) continue;
        _liveLocations[id] = e.value;
      }
    }

    if (_lastGpsUpdate.isNotEmpty) {
      final entries = _lastGpsUpdate.entries.toList();
      _lastGpsUpdate.clear();
      for (final e in entries) {
        final id = _canonicalUserId(e.key);
        if (id.isEmpty) continue;
        final existing = _lastGpsUpdate[id];
        if (existing == null || e.value.isAfter(existing)) {
          _lastGpsUpdate[id] = e.value;
        }
      }
    }

    if (_employeeLocations.isNotEmpty) {
      final entries = _employeeLocations.entries.toList();
      _employeeLocations.clear();
      for (final e in entries) {
        final id = _canonicalUserId(e.key);
        if (id.isEmpty) continue;
        _employeeLocations[id] = e.value;
      }
    }

    if (_trails.isNotEmpty) {
      final entries = _trails.entries.toList();
      _trails.clear();
      for (final e in entries) {
        final id = _canonicalUserId(e.key);
        if (id.isEmpty) continue;
        final merged = _trails[id] ?? <LatLng>[];
        merged.addAll(e.value);
        if (merged.length > 50) {
          merged.removeRange(0, merged.length - 50);
        }
        _trails[id] = merged;
      }
    }
  }

  bool _isGpsOnline(String userId) {
    final ts = _lastGpsUpdate[userId];
    if (ts == null) return false;
    return DateTime.now().difference(ts) <= _gpsOnlineWindow;
  }

  bool _isEmployeeOnline(String userId) {
    final loc = _employeeLocations[userId];
    if (loc != null) {
      return loc.isOnline;
    }
    final user = _employees[userId];
    if (user?.isOnline == true) {
      return true;
    }
    return _isGpsOnline(userId);
  }

  int get _gpsOnlineCount {
    final cutoff = DateTime.now().subtract(_gpsOnlineWindow);
    return _lastGpsUpdate.values.where((ts) => ts.isAfter(cutoff)).length;
  }

  void _startGpsSweepTimer() {
    _gpsSweepTimer?.cancel();
    _gpsSweepTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted) return;
      if (_selectedIndex != 0) return;

      final cutoff = DateTime.now().subtract(_gpsOnlineWindow);
      final staleIds = _lastGpsUpdate.entries
          .where((e) {
            final id = e.key;
            final loc = _employeeLocations[id];
            final isEmployeeOnline = loc?.isOnline ?? false;
            return !isEmployeeOnline && e.value.isBefore(cutoff);
          })
          .map((e) => e.key)
          .toList();

      if (staleIds.isEmpty) return;

      for (final id in staleIds) {
        _lastGpsUpdate.remove(id);
        _liveLocations.remove(id);
      }

      _liveLocationDirty = true;
      _scheduleLiveLocationUiUpdate();
    });
  }

  bool get _isInspecting =>
      _inspectionIndex >= 0 && _inspectionIndex < _inspectionStack.length;

  String? get _inspectedEmployeeId =>
      _isInspecting ? _inspectionStack[_inspectionIndex] : null;

  void _clearInspection() {
    setState(() {
      _inspectionStack.clear();
      _inspectionIndex = -1;
      _selectedEmployeeId = null;
      _isInspectorCollapsed = true;
    });
  }

  void _exitInspection({BuildContext? sheetContext}) {
    if (sheetContext != null) {
      Navigator.of(sheetContext).pop();
    }
    _clearInspection();
  }

  void _pushInspection(String userId) {
    final canonical = _canonicalUserId(userId);
    if (canonical.trim().isEmpty) return;

    final roster = _availableInspectionIds();
    final rosterIndex = roster.indexOf(canonical);
    if (rosterIndex >= 0) {
      _setInspectionFromRoster(roster, rosterIndex);
      return;
    }

    final existingIdx = _inspectionStack.indexOf(canonical);
    setState(() {
      if (existingIdx >= 0) {
        _inspectionIndex = existingIdx;
      } else {
        _inspectionStack.add(canonical);
        _inspectionIndex = _inspectionStack.length - 1;
      }
      _selectedEmployeeId = canonical;
      _isInspectorCollapsed = false;
    });

    _ensureEmployeeLoaded(canonical);
  }

  void _toggleInspectorCollapsed() {
    setState(() {
      _isInspectorCollapsed = !_isInspectorCollapsed;
    });
  }

  void _inspectPrev() {
    final roster = _availableInspectionIds();
    if (roster.isEmpty) return;
    final currentId = _inspectedEmployeeId ?? _selectedEmployeeId;
    final currentIndex = currentId == null ? -1 : roster.indexOf(currentId);
    final nextIndex = currentIndex < 0
        ? roster.length - 1
        : (currentIndex - 1 + roster.length) % roster.length;
    _setInspectionFromRoster(roster, nextIndex);
  }

  void _inspectNext() {
    final roster = _availableInspectionIds();
    if (roster.isEmpty) return;
    final currentId = _inspectedEmployeeId ?? _selectedEmployeeId;
    final currentIndex = currentId == null ? -1 : roster.indexOf(currentId);
    final nextIndex = currentIndex < 0 ? 0 : (currentIndex + 1) % roster.length;
    _setInspectionFromRoster(roster, nextIndex);
  }

  Future<void> _ensureEmployeeLoaded(String rawId) async {
    final id = _canonicalUserId(rawId);
    if (id.trim().isEmpty) return;
    if (_employees.containsKey(id)) return;
    if (_resolvingEmployeeIds.contains(id)) return;
    _resolvingEmployeeIds.add(id);

    try {
      final employees = await _userService.fetchEmployees();
      if (!mounted) return;
      setState(() {
        for (final emp in employees) {
          _employees[emp.id] = emp;
        }
        _rebuildEmployeeIdAlias();
        _normalizeMapsToCanonical();
      });
    } catch (e) {
      debugPrint('Error resolving employee profile for $id: $e');
    } finally {
      _resolvingEmployeeIds.remove(id);
    }
  }

  Future<void> _copyToClipboard({
    required String label,
    required String value,
  }) async {
    final v = value.trim();
    if (v.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: v));
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied'),
        duration: const Duration(milliseconds: 900),
      ),
    );
  }

  Marker _buildAdminMarker(LatLng location) {
    final label = _adminMarkerLabel();
    return Marker(
      point: location,
      width: 46,
      height: 46,
      child: _maybeTooltip(
        message: 'Admin: $label',
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _adminMarkerColor,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                color: _adminMarkerColor.withValues(alpha: 0.45),
                blurRadius: 10,
                spreadRadius: 2,
              ),
            ],
          ),
          child: const Icon(
            Icons.admin_panel_settings,
            color: Colors.white,
            size: 22,
          ),
        ),
      ),
    );
  }

  Future<void> _launchExternalUri(Uri uri) async {
    try {
      final ok = await canLaunchUrl(uri);
      if (!ok) {
        debugPrint('Cannot launch uri: $uri');
        return;
      }
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Error launching uri $uri: $e');
    }
  }

  void _openInspectionSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.6,
            minChildSize: 0.35,
            maxChildSize: 0.92,
            builder: (context, controller) {
              return SingleChildScrollView(
                controller: controller,
                padding: const EdgeInsets.all(16),
                child: _buildEmployeeInspectorContent(
                  onExit: () => _exitInspection(sheetContext: ctx),
                  onPrev: _inspectPrev,
                  onNext: _inspectNext,
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildEmployeeInspectorHeader({
    required VoidCallback onExit,
    required VoidCallback onPrev,
    required VoidCallback onNext,
  }) {
    final idx = _inspectionIndex;
    final total = _inspectionStack.length;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Employee Inspector',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 2),
              Text(
                total > 0 ? '${idx + 1} / $total' : '0 / 0',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.75),
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Previous',
          onPressed: idx > 0 ? onPrev : null,
          icon: const Icon(Icons.chevron_left),
        ),
        IconButton(
          tooltip: 'Next',
          onPressed: idx >= 0 && idx < total - 1 ? onNext : null,
          icon: const Icon(Icons.chevron_right),
        ),
        const SizedBox(width: 8),
        FilledButton.tonalIcon(
          onPressed: onExit,
          icon: const Icon(Icons.close),
          label: const Text('Exit'),
        ),
      ],
    );
  }

  Widget _buildStatMetricPill(
    _StatMetric metric, {
    required Color fallbackColor,
    bool compact = false,
  }) {
    final theme = Theme.of(context);
    final color = metric.color ?? fallbackColor;
    final isDark = theme.brightness == Brightness.dark;
    final textStyle = theme.textTheme.labelSmall?.copyWith(
      fontWeight: FontWeight.w700,
      color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
      fontSize: compact ? 11 : null,
    );

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 6 : 8,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.22 : 0.14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: metric.value,
              style: textStyle?.copyWith(
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.onSurface,
              ),
            ),
            TextSpan(text: ' ${metric.label}', style: textStyle),
          ],
        ),
      ),
    );
  }

  Widget _buildStatDialogContent({
    required IconData icon,
    required Color color,
    String? description,
    required List<_StatMetric> metrics,
    String? footer,
  }) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.18),
                shape: BoxShape.circle,
                border: Border.all(color: color.withValues(alpha: 0.35)),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                description ?? 'Summary',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: metrics
              .map(
                (metric) => _buildStatMetricPill(
                  metric,
                  fallbackColor: color,
                  compact: true,
                ),
              )
              .toList(),
        ),
        if (footer != null) ...[
          const SizedBox(height: 12),
          Text(
            footer,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildEmployeeInspectorContent({
    required VoidCallback onExit,
    required VoidCallback onPrev,
    required VoidCallback onNext,
  }) {
    final id = _inspectedEmployeeId;

    if (id == null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildEmployeeInspectorHeader(
            onExit: onExit,
            onPrev: onPrev,
            onNext: onNext,
          ),
          const SizedBox(height: 12),
          const Text('Tap an employee marker to inspect.'),
        ],
      );
    }

    final user = _employees[id];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildEmployeeInspectorHeader(
          onExit: onExit,
          onPrev: onPrev,
          onNext: onNext,
        ),
        const SizedBox(height: 12),
        _buildEmployeeDetailsContent(id, user),
      ],
    );
  }

  void _subscribeToLiveLocationFallback() {
    _liveLocationFallbackSub?.cancel();
    _liveLocationFallbackSub = _realtimeService.locationStream.listen((data) {
      try {
        final String rawId = (data['employeeId'] ?? data['userId'] ?? '')
            .toString();
        final employeeId = _canonicalUserId(rawId);
        if (employeeId.trim().isEmpty) return;
        final num? latN = data['latitude'] as num?;
        final num? lngN = data['longitude'] as num?;
        if (latN == null || lngN == null) {
          return;
        }

        final pos = LatLng(latN.toDouble(), lngN.toDouble());
        final adminId = _currentAdminId();
        if (adminId != null && employeeId == adminId) {
          _setAdminMarkerLocation(pos);
        }
        if (!mounted) return;
        _liveLocations[employeeId] = pos;
        final tsRaw = data['timestamp']?.toString();
        final ts = tsRaw == null ? null : DateTime.tryParse(tsRaw);
        _lastGpsUpdate[employeeId] = ts ?? DateTime.now();
        _liveLocationDirty = true;
        _scheduleLiveLocationUiUpdate();
      } catch (_) {}
    });
  }

  void _scheduleLiveLocationUiUpdate() {
    if (_liveLocationUiThrottle != null) return;
    _liveLocationUiThrottle = Timer(const Duration(milliseconds: 250), () {
      _liveLocationUiThrottle = null;
      if (!mounted) return;
      if (!_liveLocationDirty) return;
      _liveLocationDirty = false;
      setState(() {});
    });
  }

  void _scheduleDashboardReload() {
    _dashboardReloadDebounce?.cancel();
    _dashboardReloadDebounce = Timer(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      _dashboardDirty = true;
      if (_selectedIndex != 0) return;
      _loadDashboardData();
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

  Widget _buildCurrentScreen() {
    switch (_selectedIndex) {
      case 0:
        return _buildDashboardOverview();
      case 1:
        return const ManageEmployeesScreen();
      case 2:
        return const ManageAdminsScreen();
      case 3:
        return const AdminGeofenceScreen();
      case 4:
        return const AdminReportsHubScreen(embedded: true);
      case 5:
        return const AdminSettingsScreen();
      case 6:
        return const AdminTaskManagementScreen(embedded: true);
      default:
        return _buildDashboardOverview();
    }
  }

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
    _initRealtimeService();
    _initMapData();
    _initLocationService();
    _startGpsSweepTimer();
    _startRefreshTimer();
  }

  Widget _buildNotificationItem(DashboardNotification notif) {
    final theme = Theme.of(context);
    final color = _notificationTypeColor(notif.type);
    final ts = formatManila(notif.timestamp, 'MMM d, HH:mm');
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: theme.colorScheme.surface,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        onTap: () async {
          setState(() {
            notif.isRead = true;
          });
          await _showNotificationDetails(notif);
        },
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
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
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: notif.isRead ? FontWeight.w600 : FontWeight.w800,
            color: theme.colorScheme.onSurface,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              notif.message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  Icons.schedule,
                  size: 12,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
                const SizedBox(width: 4),
                Text(
                  ts,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ],
        ),
        trailing: notif.isRead
            ? null
            : Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: Colors.red.shade400,
                  shape: BoxShape.circle,
                ),
              ),
      ),
    );
  }

  Future<void> _showNotificationDetails(DashboardNotification notif) async {
    final payload = notif.payload ?? const <String, dynamic>{};
    final ts = formatManila(notif.timestamp, 'yyyy-MM-dd HH:mm:ss');

    String? employeeName;
    String? employeeId;
    String? action;

    String? userId;

    Map<String, dynamic>? employeeObj;
    try {
      final raw = payload['employee'];
      if (raw is Map<String, dynamic>) {
        employeeObj = raw;
      } else if (raw is Map) {
        employeeObj = Map<String, dynamic>.from(raw);
      } else if (raw != null) {
        userId = raw.toString();
      }
    } catch (_) {
      employeeObj = null;
    }

    try {
      if (userId == null) {
        final rawId = employeeObj?['_id'] ?? employeeObj?['id'];
        userId = rawId?.toString();
      }
    } catch (_) {
      userId = userId;
    }

    try {
      employeeName = (payload['name'] ?? payload['employeeName']) as String?;
    } catch (_) {
      employeeName = null;
    }

    employeeName ??= employeeObj?['name'] as String?;

    String? employeeCode;
    try {
      employeeCode = payload['employeeId'] as String?;
    } catch (_) {
      employeeCode = null;
    }
    employeeCode ??= employeeObj?['employeeId']?.toString();

    final uid = userId;
    final canonicalId = uid == null ? null : _canonicalUserId(uid);
    if ((employeeName == null || employeeName.trim().isEmpty) &&
        canonicalId != null &&
        canonicalId.trim().isNotEmpty) {
      await _ensureEmployeeLoaded(canonicalId);
    }

    final resolved = canonicalId == null ? null : _employees[canonicalId];
    employeeName ??= resolved?.name;
    employeeCode ??= resolved?.employeeId;

    try {
      employeeId = (payload['userId'] ?? payload['employeeUserId']) as String?;
    } catch (_) {
      employeeId = null;
    }

    if (employeeId == null) {
      try {
        employeeId = canonicalId;
      } catch (_) {
        employeeId = null;
      }
    }

    // Prefer displaying the employee's readable employeeId/code if available.
    employeeId = employeeCode ?? employeeId;
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
          if (notif.type == 'report')
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                setState(() {
                  _selectedIndex = 4;
                });
                AdminReportsHubScreen.selectInitialTab(1);
              },
              icon: const Icon(Icons.insights),
              label: const Text('Analytics'),
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader(
              title: 'Notifications',
              subtitle: 'Latest admin alerts and updates',
              badge: unread > 0
                  ? _buildNotificationBadge(unread)
                  : const SizedBox(),
              action: TextButton(
                onPressed: _showNotificationsInbox,
                child: const Text('Open'),
              ),
            ),
            const SizedBox(height: 12),
            if (items.isEmpty)
              Text(
                'No notifications yet',
                style: TextStyle(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.7),
                ),
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
      return _adminLiveLocation() ?? _adminMarkerLocation;
    }

    return null;
  }

  bool _passesEmployeeFilters(String userId) {
    final user = _employees[userId];
    final loc = _employeeLocations[userId];
    final isBusy = loc?.status == EmployeeStatus.busy;
    final isOnline = _isEmployeeOnline(userId);
    final hasLiveLocation = _liveLocations[userId] != null;

    // Allow employees who either have a recent GPS ping or at least a last-known
    // location on the map. This prevents "online" employees from disappearing
    // solely because their last GPS ping is slightly stale.
    if (!isOnline && !hasLiveLocation) return false;

    if (_employeeStatusFilter == 'busy' && !isBusy) return false;
    if (_employeeStatusFilter == 'available' && isBusy) return false;

    final q = _employeeSearchController.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      final name = (user?.name ?? '').toLowerCase();
      final email = (user?.email ?? '').toLowerCase();
      final username = (user?.username ?? '').toLowerCase();
      final employeeCode = (user?.employeeId ?? '').toLowerCase();
      if (!name.contains(q) &&
          !email.contains(q) &&
          !username.contains(q) &&
          !employeeCode.contains(q)) {
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

  LatLngBounds? _boundsForLiveLocations() {
    if (_liveLocations.isEmpty) return null;
    final points = _liveLocations.values.toList();
    final bounds = LatLngBounds(points.first, points.first);
    for (final p in points.skip(1)) {
      bounds.extend(p);
    }
    return bounds;
  }

  void _fitMapToEmployees() {
    final bounds = _boundsForLiveLocations();
    if (bounds == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No employee locations to fit yet'),
            duration: Duration(milliseconds: 1200),
          ),
        );
      }
      return;
    }
    try {
      _mapController.fitCamera(
        CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(48)),
      );
    } catch (_) {
      _panTo(bounds.center, zoom: 4);
    }
  }

  void _focusOnSelectedEmployee() {
    final selectedId = _inspectedEmployeeId ?? _selectedEmployeeId;
    LatLng? target;
    if (selectedId != null) {
      target = _liveLocations[selectedId];
    }
    target ??= _liveLocations.isNotEmpty ? _liveLocations.values.first : null;
    if (target == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No employee selected to focus'),
            duration: Duration(milliseconds: 1200),
          ),
        );
      }
      return;
    }
    _panTo(target, zoom: 15);
  }

  Widget _buildLegendItem({
    required Color color,
    required IconData icon,
    required String label,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 6),
            ],
          ),
          child: Icon(icon, size: 11, color: Colors.white),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _buildMapLegend() {
    final showAdmin = _adminMarkerLocation != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 8),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Status legend',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          _buildLegendItem(
            color: Colors.green,
            icon: Icons.check_circle,
            label: 'Available',
          ),
          const SizedBox(height: 6),
          _buildLegendItem(
            color: Colors.blue,
            icon: Icons.directions_run,
            label: 'Moving',
          ),
          const SizedBox(height: 6),
          _buildLegendItem(
            color: Colors.red,
            icon: Icons.schedule,
            label: 'Busy',
          ),
          if (showAdmin) ...[
            const SizedBox(height: 6),
            _buildLegendItem(
              color: _adminMarkerColor,
              icon: Icons.admin_panel_settings,
              label: 'Admin',
            ),
          ],
        ],
      ),
    );
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
                  if (next == 'admin') {
                    _ensureAdminMarkerLocation();
                  }
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
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.75),
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
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.9),
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
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.75),
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
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w800,
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
        bool selectionMode = false;
        final selectedIds = <String>{};

        Future<bool> confirmDelete(int count) async {
          final ok = await showDialog<bool>(
            context: ctx,
            builder: (dctx) => AlertDialog(
              title: const Text('Delete notifications?'),
              content: Text(
                count == 1
                    ? 'This will remove it from the inbox.'
                    : 'This will remove $count notifications from the inbox.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dctx, false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(dctx, true),
                  child: const Text('Delete'),
                ),
              ],
            ),
          );
          return ok == true;
        }

        void markReadByIds(Set<String> ids, {required bool read}) {
          if (ids.isEmpty) return;
          if (!mounted) return;
          setState(() {
            for (final n in _notifications) {
              if (ids.contains(n.id)) {
                n.isRead = read;
              }
            }
          });
        }

        void deleteByIds(Set<String> ids) {
          if (ids.isEmpty) return;
          if (!mounted) return;
          setState(() {
            _notifications.removeWhere((n) => ids.contains(n.id));
          });
        }

        return SafeArea(
          child: FractionallySizedBox(
            heightFactor: 0.85,
            child: StatefulBuilder(
              builder: (sheetCtx, setSheetState) {
                final theme = Theme.of(context);
                final unreadCount = _notifications
                    .where((n) => !n.isRead)
                    .length;
                final selectedCount = selectedIds.length;
                final allSelected =
                    _notifications.isNotEmpty &&
                    selectedCount == _notifications.length;
                final canBulk = selectionMode && selectedCount > 0;

                void toggleSelected(String id) {
                  setSheetState(() {
                    if (selectedIds.contains(id)) {
                      selectedIds.remove(id);
                    } else {
                      selectedIds.add(id);
                    }
                  });
                }

                void toggleSelectAll() {
                  setSheetState(() {
                    if (allSelected) {
                      selectedIds.clear();
                    } else {
                      selectedIds
                        ..clear()
                        ..addAll(_notifications.map((n) => n.id));
                    }
                  });
                }

                Widget buildInboxItem(DashboardNotification notif) {
                  final color = _notificationTypeColor(notif.type);
                  final ts = formatManila(notif.timestamp, 'MMM d, HH:mm');
                  final isSelected = selectedIds.contains(notif.id);

                  return Card(
                    elevation: 0,
                    margin: const EdgeInsets.only(bottom: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    color: theme.colorScheme.surface,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      onTap: () async {
                        if (selectionMode) {
                          toggleSelected(notif.id);
                          return;
                        }

                        if (!mounted) return;
                        setState(() {
                          notif.isRead = true;
                        });
                        await _showNotificationDetails(notif);
                      },
                      leading: selectionMode
                          ? Checkbox(
                              value: isSelected,
                              onChanged: (_) => toggleSelected(notif.id),
                            )
                          : Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: color.withValues(alpha: 0.35),
                                ),
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
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: notif.isRead
                              ? FontWeight.w600
                              : FontWeight.w800,
                          color: theme.colorScheme.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Text(
                            notif.message,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.75,
                              ),
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                Icons.schedule,
                                size: 12,
                                color: theme.colorScheme.onSurface.withValues(
                                  alpha: 0.6,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  ts,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.6),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      trailing: selectionMode
                          ? null
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (!notif.isRead)
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color: Colors.red.shade400,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                PopupMenuButton<String>(
                                  tooltip: 'Actions',
                                  onSelected: (value) async {
                                    switch (value) {
                                      case 'markRead':
                                        markReadByIds({notif.id}, read: true);
                                        return;
                                      case 'markUnread':
                                        markReadByIds({notif.id}, read: false);
                                        return;
                                      case 'delete':
                                        final ok = await confirmDelete(1);
                                        if (!ok) return;
                                        deleteByIds({notif.id});
                                        setSheetState(() {
                                          selectedIds.remove(notif.id);
                                        });
                                        return;
                                    }
                                  },
                                  itemBuilder: (_) => <PopupMenuEntry<String>>[
                                    PopupMenuItem(
                                      value: notif.isRead
                                          ? 'markUnread'
                                          : 'markRead',
                                      child: Text(
                                        notif.isRead
                                            ? 'Mark unread'
                                            : 'Mark read',
                                      ),
                                    ),
                                    const PopupMenuDivider(),
                                    const PopupMenuItem(
                                      value: 'delete',
                                      child: Text('Delete'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                    ),
                  );
                }

                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    selectionMode
                                        ? 'Select notifications'
                                        : 'Notifications',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (!selectionMode && unreadCount > 0) ...[
                                  const SizedBox(width: 8),
                                  _buildNotificationBadge(unreadCount),
                                ],
                                if (selectionMode && selectedCount > 0) ...[
                                  const SizedBox(width: 8),
                                  _buildNotificationBadge(selectedCount),
                                ],
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              setSheetState(() {
                                selectionMode = !selectionMode;
                                if (!selectionMode) {
                                  selectedIds.clear();
                                }
                              });
                            },
                            child: Text(selectionMode ? 'Done' : 'Select'),
                          ),
                          if (selectionMode)
                            IconButton(
                              tooltip: allSelected
                                  ? 'Clear selection'
                                  : 'Select all',
                              onPressed: _notifications.isEmpty
                                  ? null
                                  : toggleSelectAll,
                              icon: const Icon(Icons.select_all),
                            ),
                          IconButton(
                            tooltip: selectionMode
                                ? 'Mark selected read'
                                : 'Mark all read',
                            onPressed: selectionMode
                                ? (canBulk
                                      ? () {
                                          markReadByIds(
                                            selectedIds,
                                            read: true,
                                          );
                                          setSheetState(() {
                                            selectedIds.clear();
                                            selectionMode = false;
                                          });
                                        }
                                      : null)
                                : (unreadCount > 0
                                      ? () {
                                          markReadByIds(
                                            _notifications
                                                .map((n) => n.id)
                                                .toSet(),
                                            read: true,
                                          );
                                        }
                                      : null),
                            icon: const Icon(Icons.done_all),
                          ),
                          IconButton(
                            tooltip: 'Delete selected',
                            onPressed: canBulk
                                ? () async {
                                    final ok = await confirmDelete(
                                      selectedCount,
                                    );
                                    if (!ok) return;
                                    deleteByIds(selectedIds);
                                    setSheetState(() {
                                      selectedIds.clear();
                                      selectionMode = false;
                                    });
                                  }
                                : null,
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: _notifications.isEmpty
                            ? Center(
                                child: Text(
                                  'No notifications',
                                  style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.7),
                                  ),
                                ),
                              )
                            : ListView.builder(
                                itemCount: _notifications.length,
                                itemBuilder: (context, index) {
                                  final notif = _notifications[index];
                                  return buildInboxItem(notif);
                                },
                              ),
                      ),
                    ],
                  ),
                );
              },
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
        final stats = _dashboardStats;
        final total = stats?.users.totalEmployees ?? 0;
        final active = stats?.users.activeEmployees ?? 0;
        final inactive = (total - active).clamp(0, total);
        final admins = stats?.users.totalAdmins ?? 0;
        return AlertDialog(
          title: const Text('Employee Availability'),
          content: _buildStatDialogContent(
            icon: Icons.people,
            color: Colors.blue,
            description: 'Workforce coverage across active and inactive staff.',
            metrics: [
              _StatMetric(label: 'Total', value: '$total'),
              _StatMetric(
                label: 'Active',
                value: '$active',
                color: Colors.green,
              ),
              _StatMetric(
                label: 'Inactive',
                value: '$inactive',
                color: Colors.redAccent,
              ),
              _StatMetric(
                label: 'Admins',
                value: '$admins',
                color: Colors.deepPurple,
              ),
            ],
          ),
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
        final stats = _dashboardStats;
        final total = stats?.geofences.total ?? 0;
        final active = stats?.geofences.active ?? 0;
        final inactive = (total - active).clamp(0, total);
        return AlertDialog(
          title: const Text('Geofences'),
          content: _buildStatDialogContent(
            icon: Icons.location_on,
            color: Colors.green,
            description: 'Coverage zones across active and inactive sites.',
            metrics: [
              _StatMetric(label: 'Total', value: '$total'),
              _StatMetric(
                label: 'Active',
                value: '$active',
                color: Colors.green,
              ),
              _StatMetric(
                label: 'Inactive',
                value: '$inactive',
                color: Colors.orange,
              ),
            ],
          ),
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
        final stats = _dashboardStats;
        final total = stats?.tasks.total ?? 0;
        final pending = stats?.tasks.pending ?? 0;
        final completed = stats?.tasks.completed ?? 0;
        final inProgress = stats?.tasks.inProgress ?? 0;
        return AlertDialog(
          title: const Text('Tasks'),
          content: _buildStatDialogContent(
            icon: Icons.task,
            color: Colors.orange,
            description: 'Task progress and workload across all assignments.',
            metrics: [
              _StatMetric(label: 'Total', value: '$total'),
              _StatMetric(
                label: 'Pending',
                value: '$pending',
                color: Colors.orange,
              ),
              _StatMetric(
                label: 'In progress',
                value: '$inProgress',
                color: Colors.blueAccent,
              ),
              _StatMetric(
                label: 'Completed',
                value: '$completed',
                color: Colors.green,
              ),
            ],
          ),
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
        final stats = _dashboardStats;
        final today = stats?.attendance.today ?? 0;
        final checkIns = stats?.attendance.todayCheckIns ?? 0;
        final checkOuts = stats?.attendance.todayCheckOuts ?? 0;
        final open = (checkIns - checkOuts).clamp(0, checkIns);
        return AlertDialog(
          title: const Text("Today's Attendance"),
          content: _buildStatDialogContent(
            icon: Icons.check_circle,
            color: Colors.purple,
            description: 'Daily attendance captured in the current period.',
            metrics: [
              _StatMetric(label: 'Records', value: '$today'),
              _StatMetric(
                label: 'Check-ins',
                value: '$checkIns',
                color: Colors.deepPurple,
              ),
              _StatMetric(
                label: 'Check-outs',
                value: '$checkOuts',
                color: Colors.indigo,
              ),
              _StatMetric(
                label: 'Open',
                value: '$open',
                color: Colors.purpleAccent,
              ),
            ],
          ),
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

  Future<void> _initLocationService() async {
    try {
      await _locationService.initialize();
      _employeeLocationsSnapshotSub?.cancel();
      _employeeLocationsSnapshotSub = _locationService.employeeLocationsStream
          .listen((locations) {
            if (!mounted) return;
            _employeeLocations
              ..clear()
              ..addEntries(
                locations.map(
                  (loc) => MapEntry(_canonicalUserId(loc.employeeId), loc),
                ),
              );

            for (final loc in locations) {
              final id = _canonicalUserId(loc.employeeId);
              if (id.isEmpty) continue;
              if (!loc.isOnline) continue;

              _liveLocations[id] = LatLng(loc.latitude, loc.longitude);
              _lastGpsUpdate[id] = loc.timestamp;
            }

            final onlineIds = <String>{
              for (final loc in locations)
                if (loc.isOnline) _canonicalUserId(loc.employeeId),
            }..removeWhere((id) => id.trim().isEmpty);

            // Prune any markers/trails that are no longer online.
            // This prevents "ghost" markers that persist after logout.
            if (_liveLocations.isNotEmpty) {
              final ids = _liveLocations.keys.toList();
              for (final id in ids) {
                if (!onlineIds.contains(id)) {
                  _liveLocations.remove(id);
                  _lastGpsUpdate.remove(id);
                  _trails.remove(id);
                }
              }
            }

            _liveLocationDirty = true;
            _scheduleLiveLocationUiUpdate();
          });

      _subscribeToLocations();
    } catch (_) {}
  }

  void _subscribeToAdminNotifications() {
    _adminNotifSub?.cancel();
    _adminNotifSub = _realtimeService.notificationStream.listen((data) {
      try {
        final action = (data['action'] ?? '') as String;
        if (action == 'employeeOnline') {
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
          return;
        }

        if ((data['type'] == 'attendance') &&
            (action == 'check-in' || action == 'check-out')) {
          final userId = (data['userId'] ?? '').toString();
          final tsRaw = data['timestamp']?.toString() ?? '';
          final key = 'attendance:$action:$userId:$tsRaw';
          if (_snackDedupKeys.contains(key)) return;
          _snackDedupKeys.add(key);

          final message = (data['message'] ?? 'Attendance update').toString();
          final title = action == 'check-in'
              ? 'Employee check-in'
              : 'Employee check-out';

          final parsedTs = DateTime.tryParse(tsRaw);
          final notifTs = parsedTs ?? DateTime.now();

          setState(() {
            _notifications.insert(
              0,
              DashboardNotification(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                title: title,
                message: message,
                type: 'attendance',
                timestamp: notifTs,
                payload: data,
              ),
            );

            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(message),
                duration: const Duration(seconds: 3),
              ),
            );
          });

          Future<void>.delayed(const Duration(seconds: 6)).then((_) {
            if (!mounted) return;
            _snackDedupKeys.remove(key);
          });

          if (mounted) {
            setState(() {});
          }
          return;
        }

        if (action == 'overdue' && (data['type'] == 'task')) {
          final taskTitle = (data['taskTitle'] ?? 'Task') as String;
          final taskId = (data['taskId'] ?? '') as String;
          final key = 'taskOverdue:$taskId';
          if (_snackDedupKeys.contains(key)) return;
          _snackDedupKeys.add(key);

          setState(() {
            _notifications.insert(
              0,
              DashboardNotification(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                title: 'Task overdue',
                message: 'Task "$taskTitle" is now overdue.',
                type: 'task',
                timestamp: DateTime.now(),
                payload: data,
              ),
            );

            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Task "$taskTitle" is now overdue.'),
                duration: const Duration(seconds: 3),
              ),
            );
          });

          if (mounted) {
            setState(() {});
          }
          return;
        }
      } catch (_) {}
    });
  }

  Future<void> _initRealtimeService() async {
    await _realtimeService.initialize();

    _subscribeToAdminNotifications();
    _subscribeToLiveLocationFallback();

    // Listen for real-time updates (debounced to avoid hammering backend/UI)
    _attendanceStreamSub?.cancel();
    _attendanceStreamSub = _realtimeService.attendanceStream.listen((event) {
      if (!mounted) return;
      _scheduleDashboardReload();
    });

    _taskStreamSub?.cancel();
    _taskStreamSub = _realtimeService.taskStream.listen((event) {
      if (!mounted) return;
      try {
        final type = (event['type'] ?? '').toString();
        if (type == 'assigned_multiple' ||
            type == 'unassigned' ||
            type == 'user_task_archived' ||
            type == 'user_task_restored' ||
            type == 'status_updated') {
          if (_selectedIndex == 0) {
            _scheduleOnlineEmployeeRefresh();
          } else {
            // We intentionally avoid hammering the dashboard endpoint while
            // the admin is on other tabs, but we also don't want to miss
            // updates. Mark pending and apply when they return.
            _pendingOnlineEmployeeRefresh = true;
          }
        }
      } catch (_) {}
      _scheduleDashboardReload();
    });

    _onlineCountSub?.cancel();
    _onlineCountSub = _realtimeService.onlineCountStream.listen((count) {
      // Socket-level online count is currently unused; HTTP realtime
      // endpoint provides authoritative employee online counts.
      if (!mounted) {
        return;
      }
    });

    _eventStreamSub?.cancel();
    _eventStreamSub = _realtimeService.eventStream.listen((event) {
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
            payload: (() {
              final raw = event['data'] is Map
                  ? Map<String, dynamic>.from(event['data'] as Map)
                  : <String, dynamic>{};
              raw['action'] = action;
              return raw;
            })(),
          ),
        );
        if (_notifications.length > 50) {
          _notifications.removeLast();
        }
      });

      if (shouldSnackbar) {
        final key =
            snackbarKey ?? '$notifType:${action.isEmpty ? 'event' : action}';
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
      if (_selectedIndex != 0) {
        return;
      }

      // If something changed (socket events) while we were active, refresh full
      // stats so the 4 cards stay accurate.
      if (_dashboardDirty) {
        _loadDashboardData();
        return;
      }

      // Periodic refresh:
      // - Realtime updates every 30s
      // - Full stats refresh every 2 minutes to avoid stale cards even if
      //   socket events are missed.
      if (timer.tick % 4 == 0) {
        _loadDashboardData();
        return;
      }

      if (!_isFetchingRealtime) {
        _loadRealtimeUpdates();
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _gpsSweepTimer?.cancel();
    _dashboardReloadDebounce?.cancel();
    _liveLocationUiThrottle?.cancel();
    _onlineEmployeesReloadDebounce?.cancel();
    _employeeSearchDebounce?.cancel();
    _adminNotifSub?.cancel();
    _attendanceStreamSub?.cancel();
    _taskStreamSub?.cancel();
    _eventStreamSub?.cancel();
    _onlineCountSub?.cancel();
    _employeeLocationsSub?.cancel();
    _employeeLocationsSnapshotSub?.cancel();
    _liveLocationFallbackSub?.cancel();
    _employeeSearchController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _loadDashboardData() async {
    if (_isFetchingDashboard) return;
    _isFetchingDashboard = true;
    try {
      final stats = await _dashboardService.getDashboardStats();
      final realtime = await _dashboardService.getRealtimeUpdates();
      if (mounted) {
        setState(() {
          _dashboardStats = stats;
          _realtimeUpdates = realtime;
          _isLoading = false;
          _dashboardDirty = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading dashboard data: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } finally {
      _isFetchingDashboard = false;
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

    switch (index) {
      case _navDashboard:
        _selectAdminScreen(0);
        break;
      case _navEmployees:
        _selectAdminScreen(1);
        break;
      case _navReports:
        _selectAdminScreen(4);
        break;
      default:
        _selectAdminScreen(0);
    }
  }

  void _selectAdminScreen(int index) {
    if (!mounted) return;
    if (_selectedIndex == index) return;
    setState(() {
      _selectedIndex = index;
    });

    // If we navigated back to the dashboard and stats were marked dirty
    // (or not loaded yet), refresh immediately.
    if (_selectedIndex == 0 && (_dashboardStats == null || _dashboardDirty)) {
      _loadDashboardData();
    }

    // Apply any missed online employee refreshes (e.g. task assigned/unassigned
    // while admin was in Task Management).
    if (_selectedIndex == 0 && _pendingOnlineEmployeeRefresh) {
      _pendingOnlineEmployeeRefresh = false;
      _loadOnlineEmployeeLocations();
    }
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

  Widget _buildEmployeeInspectorDrawer() {
    const double expandedWidth = 380;
    const double collapsedWidth = 44;

    final bool collapsed = _isInspectorCollapsed;
    final bool hasSelection = _inspectedEmployeeId != null;

    return SizedBox(
      height: 400,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        width: collapsed ? collapsedWidth : expandedWidth,
        child: Row(
          children: [
            SizedBox(
              width: collapsedWidth,
              height: double.infinity,
              child: Material(
                color: Colors.transparent,
                child: InkResponse(
                  onTap: _toggleInspectorCollapsed,
                  containedInkWell: true,
                  child: Center(
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Icon(
                          collapsed ? Icons.chevron_left : Icons.chevron_right,
                          color: Theme.of(context).colorScheme.onSurface
                              .withValues(alpha: hasSelection ? 0.85 : 0.6),
                          size: 26,
                        ),
                        if (collapsed && hasSelection)
                          Positioned(
                            right: -2,
                            top: -2,
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: Colors.green.shade600,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 1,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (!collapsed) Expanded(child: _buildEmployeeSidePanel()),
          ],
        ),
      ),
    );
  }

  Widget _buildEmployeeSidePanel() {
    return SizedBox(
      height: 400,
      child: Card(
        elevation: 4,
        color: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildEmployeeInspectorHeader(
                onExit: _exitInspection,
                onPrev: _inspectPrev,
                onNext: _inspectNext,
              ),
              const SizedBox(height: 8),
              Text(
                'Selected: ${_selectedEmployeeLabel()}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.85),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  child: _inspectedEmployeeId == null
                      ? _buildEmployeeEmptyState()
                      : _buildEmployeeDetailsContent(
                          _inspectedEmployeeId!,
                          _employees[_inspectedEmployeeId!],
                        ),
                ),
              ),
            ],
          ),
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
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.75),
          ),
        ),
      ],
    );
  }

  Widget _buildEmployeeDetailsContent(String userId, UserModel? user) {
    final isOnline = _isEmployeeOnline(userId);
    final loc = _employeeLocations[userId];
    final activeTaskCount = loc?.activeTaskCount ?? user?.activeTaskCount ?? 0;
    final isBusy = loc?.status == EmployeeStatus.busy;

    final email = (user?.email ?? '').trim();
    final phone = (user?.phone ?? '').trim();

    return Column(
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
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.75),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.tonalIcon(
              onPressed: email.isEmpty
                  ? null
                  : () => _copyToClipboard(label: 'Email', value: email),
              icon: const Icon(Icons.copy),
              label: const Text('Copy Email'),
            ),
            FilledButton.tonalIcon(
              onPressed: email.isEmpty
                  ? null
                  : () =>
                        _launchExternalUri(Uri(scheme: 'mailto', path: email)),
              icon: const Icon(Icons.email_outlined),
              label: const Text('Email'),
            ),
            FilledButton.tonalIcon(
              onPressed: phone.isEmpty
                  ? null
                  : () => _copyToClipboard(label: 'Phone', value: phone),
              icon: const Icon(Icons.copy),
              label: const Text('Copy Phone'),
            ),
            FilledButton.tonalIcon(
              onPressed: phone.isEmpty
                  ? null
                  : () => _launchExternalUri(Uri(scheme: 'tel', path: phone)),
              icon: const Icon(Icons.call_outlined),
              label: const Text('Call'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildStatusRow(
          'Online Status',
          loc?.status == EmployeeStatus.busy
              ? 'Busy'
              : loc?.status == EmployeeStatus.available
              ? 'Checked In'
              : loc?.status == EmployeeStatus.offline
              ? 'Offline'
              : isOnline
              ? 'Online'
              : 'Offline',
          loc?.status == EmployeeStatus.busy
              ? Colors.red
              : loc?.status == EmployeeStatus.available
              ? Colors.green
              : loc?.status == EmployeeStatus.offline
              ? Colors.grey
              : isOnline
              ? Colors.blue
              : Colors.grey,
        ),
        _buildStatusRow(
          'Task Load',
          '$activeTaskCount / $_taskLimitPerEmployee',
          isBusy ? Colors.red : Colors.blue,
        ),
        const SizedBox(height: 12),
        if (isOnline && _liveLocations.containsKey(userId))
          Text(
            'Lat: ${_liveLocations[userId]!.latitude.toStringAsFixed(4)}\nLng: ${_liveLocations[userId]!.longitude.toStringAsFixed(4)}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.75),
            ),
          )
        else
          Text(
            'Location not available',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.7),
            ),
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
                      Flexible(
                        fit: FlexFit.loose,
                        child: TabBarView(
                          children: [
                            ListView(
                              padding: EdgeInsets.zero,
                              children: [
                                _buildDetailRow('Name', user?.name ?? 'N/A'),
                                _buildDetailRow('Email', user?.email ?? 'N/A'),
                                _buildDetailRow('Phone', user?.phone ?? 'N/A'),
                                _buildDetailRow('Role', user?.role ?? 'N/A'),
                              ],
                            ),
                            ListView(
                              padding: EdgeInsets.zero,
                              children: [
                                _buildStatusRow(
                                  'Online Status',
                                  loc?.status == EmployeeStatus.busy
                                      ? 'Busy'
                                      : loc?.status == EmployeeStatus.available
                                      ? 'Checked In'
                                      : loc?.status == EmployeeStatus.offline
                                      ? 'Offline'
                                      : isOnline
                                      ? 'Online'
                                      : 'Offline',
                                  loc?.status == EmployeeStatus.busy
                                      ? Colors.red
                                      : loc?.status == EmployeeStatus.available
                                      ? Colors.green
                                      : loc?.status == EmployeeStatus.offline
                                      ? Colors.grey
                                      : isOnline
                                      ? Colors.blue
                                      : Colors.grey,
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
    );
  }

  @override
  Widget build(BuildContext context) {
    const brandColor = Color(0xFF2688d4);
    final width = MediaQuery.sizeOf(context).width;
    final useRail = width >= 980;
    return Shortcuts(
      shortcuts: {
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.digit1):
            const _AdminNavIntent(0),
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.digit2):
            const _AdminNavIntent(1),
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.digit3):
            const _AdminNavIntent(2),
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.digit4):
            const _AdminNavIntent(3),
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.digit5):
            const _AdminNavIntent(4),
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.digit6):
            const _AdminNavIntent(5),
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.digit7):
            const _AdminNavIntent(6),
      },
      child: Actions(
        actions: {
          _AdminNavIntent: CallbackAction<_AdminNavIntent>(
            onInvoke: (intent) {
              _selectAdminScreen(intent.index);
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            appBar: AppBar(
              leading: _selectedIndex != 0
                  ? BackButton(
                      onPressed: () {
                        setState(() {
                          _selectedIndex = 0;
                        });

                        if (_dashboardStats == null || _dashboardDirty) {
                          _loadDashboardData();
                        }

                        if (_pendingOnlineEmployeeRefresh) {
                          _pendingOnlineEmployeeRefresh = false;
                          _loadOnlineEmployeeLocations();
                        }
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
                    final confirmed = await AppWidgets.confirmLogout(context);
                    if (!confirmed) return;

                    try {
                      await _userService.markOffline();
                    } catch (_) {}

                    await _userService.logout();
                    if (!mounted) return;
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const LoginScreen(),
                      ),
                      (route) => false,
                    );
                  },
                ),
              ],
            ),
            body: useRail
                ? Row(
                    children: [
                      MouseRegion(
                        onEnter: (_) {
                          if (!mounted) return;
                          setState(() {
                            _railHoverExpanded = true;
                          });
                        },
                        onExit: (_) {
                          if (!mounted) return;
                          setState(() {
                            _railHoverExpanded = false;
                          });
                        },
                        child: NavigationRail(
                          extended: _railHoverExpanded,
                          minWidth: 64,
                          minExtendedWidth: 220,
                          selectedIndex: _selectedIndex,
                          onDestinationSelected: _selectAdminScreen,
                          labelType: _railHoverExpanded
                              ? null
                              : NavigationRailLabelType.none,
                          destinations: [
                            NavigationRailDestination(
                              icon: const Tooltip(
                                message: 'Dashboard (Ctrl+1)',
                                child: Icon(Icons.dashboard_outlined),
                              ),
                              selectedIcon: const Tooltip(
                                message: 'Dashboard (Ctrl+1)',
                                child: Icon(Icons.dashboard),
                              ),
                              label: const Text('Dashboard'),
                            ),
                            NavigationRailDestination(
                              icon: const Tooltip(
                                message: 'Employees (Ctrl+2)',
                                child: Icon(Icons.people_outline),
                              ),
                              selectedIcon: const Tooltip(
                                message: 'Employees (Ctrl+2)',
                                child: Icon(Icons.people),
                              ),
                              label: const Text('Employees'),
                            ),
                            NavigationRailDestination(
                              icon: const Tooltip(
                                message: 'Admins (Ctrl+3)',
                                child: Icon(
                                  Icons.admin_panel_settings_outlined,
                                ),
                              ),
                              selectedIcon: const Tooltip(
                                message: 'Admins (Ctrl+3)',
                                child: Icon(Icons.admin_panel_settings),
                              ),
                              label: const Text('Admins'),
                            ),
                            NavigationRailDestination(
                              icon: const Tooltip(
                                message: 'Geofences (Ctrl+4)',
                                child: Icon(Icons.location_on_outlined),
                              ),
                              selectedIcon: const Tooltip(
                                message: 'Geofences (Ctrl+4)',
                                child: Icon(Icons.location_on),
                              ),
                              label: const Text('Geofences'),
                            ),
                            NavigationRailDestination(
                              icon: const Tooltip(
                                message: 'Reports (Ctrl+5)',
                                child: Icon(Icons.assessment_outlined),
                              ),
                              selectedIcon: const Tooltip(
                                message: 'Reports (Ctrl+5)',
                                child: Icon(Icons.assessment),
                              ),
                              label: const Text('Reports'),
                            ),
                            NavigationRailDestination(
                              icon: const Tooltip(
                                message: 'Settings (Ctrl+6)',
                                child: Icon(Icons.settings_outlined),
                              ),
                              selectedIcon: const Tooltip(
                                message: 'Settings (Ctrl+6)',
                                child: Icon(Icons.settings),
                              ),
                              label: const Text('Settings'),
                            ),
                            NavigationRailDestination(
                              icon: const Tooltip(
                                message: 'Tasks (Ctrl+7)',
                                child: Icon(Icons.task_outlined),
                              ),
                              selectedIcon: const Tooltip(
                                message: 'Tasks (Ctrl+7)',
                                child: Icon(Icons.task),
                              ),
                              label: const Text('Tasks'),
                            ),
                          ],
                        ),
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(child: _buildCurrentScreen()),
                    ],
                  )
                : _buildCurrentScreen(),
            bottomNavigationBar: useRail
                ? null
                : BottomNavigationBar(
                    type: BottomNavigationBarType.fixed,
                    backgroundColor: Theme.of(context).colorScheme.surface,
                    showUnselectedLabels: true,
                    selectedItemColor: brandColor,
                    unselectedItemColor: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.7),
                    selectedLabelStyle: const TextStyle(
                      fontWeight: FontWeight.w600,
                    ),
                    selectedIconTheme: const IconThemeData(
                      color: brandColor,
                      size: 28,
                    ),
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
                      BottomNavigationBarItem(
                        icon: Icon(Icons.more_horiz),
                        label: 'More',
                      ),
                    ],
                    currentIndex: _currentNavIndex(),
                    onTap: _onItemTapped,
                  ),
          ),
        ),
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
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.45),
            ),
            const SizedBox(height: 16),
            Text(
              'Failed to load dashboard data',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.85),
              ),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final theme = Theme.of(context);
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
                      color: Colors.green.withValues(
                        alpha: theme.brightness == Brightness.dark
                            ? 0.22
                            : 0.12,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.green.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.wifi,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Live Updates Active • $_gpsOnlineCount Online',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
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
                      _buildEmployeeInspectorDrawer(),
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final stats = _dashboardStats!;
        final totalEmployees = stats.users.totalEmployees;
        final activeEmployees = stats.users.activeEmployees;
        final inactiveEmployees = (totalEmployees - activeEmployees).clamp(
          0,
          totalEmployees,
        );
        final totalAdmins = stats.users.totalAdmins;

        final totalGeofences = stats.geofences.total;
        final activeGeofences = stats.geofences.active;
        final inactiveGeofences = (totalGeofences - activeGeofences).clamp(
          0,
          totalGeofences,
        );

        final totalTasks = stats.tasks.total;
        final pendingTasks = stats.tasks.pending;
        final inProgressTasks = stats.tasks.inProgress;
        final completedTasks = stats.tasks.completed;

        final checkIns = stats.attendance.todayCheckIns;
        final checkOuts = stats.attendance.todayCheckOuts;
        final openAttendance = (checkIns - checkOuts).clamp(0, checkIns);

        return Column(
          children: [
            _buildStatDrawerCard(
              title: 'Total Employees',
              value: totalEmployees.toString(),
              icon: Icons.people,
              color: Colors.blue,
              subtitle: '$totalAdmins admins',
              metrics: [
                _StatMetric(
                  label: 'Active',
                  value: activeEmployees.toString(),
                  color: Colors.green,
                ),
                _StatMetric(
                  label: 'Inactive',
                  value: inactiveEmployees.toString(),
                  color: Colors.redAccent,
                ),
              ],
              onTap: _showEmployeeAvailabilityDialog,
            ),
            const SizedBox(height: 10),
            _buildStatDrawerCard(
              title: 'Geofences',
              value: totalGeofences.toString(),
              icon: Icons.location_on,
              color: Colors.green,
              subtitle: '$activeGeofences active',
              metrics: [
                _StatMetric(
                  label: 'Active',
                  value: activeGeofences.toString(),
                  color: Colors.green,
                ),
                _StatMetric(
                  label: 'Inactive',
                  value: inactiveGeofences.toString(),
                  color: Colors.orange,
                ),
              ],
              onTap: _showGeofenceDetailsDialog,
            ),
            const SizedBox(height: 10),
            _buildStatDrawerCard(
              title: 'Tasks',
              value: totalTasks.toString(),
              icon: Icons.task,
              color: Colors.orange,
              subtitle: '$completedTasks completed',
              metrics: [
                _StatMetric(
                  label: 'Pending',
                  value: pendingTasks.toString(),
                  color: Colors.orange,
                ),
                _StatMetric(
                  label: 'In progress',
                  value: inProgressTasks.toString(),
                  color: Colors.blueAccent,
                ),
              ],
              onTap: _showTasksDialog,
            ),
            const SizedBox(height: 10),
            _buildStatDrawerCard(
              title: 'Today\'s Attendance',
              value: stats.attendance.today.toString(),
              icon: Icons.check_circle,
              color: Colors.purple,
              subtitle: '$checkIns check-ins',
              metrics: [
                _StatMetric(
                  label: 'Open',
                  value: openAttendance.toString(),
                  color: Colors.deepPurple,
                ),
                _StatMetric(
                  label: 'Checked out',
                  value: checkOuts.toString(),
                  color: Colors.indigo,
                ),
              ],
              onTap: _showAttendanceDialog,
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatDrawerCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    String? subtitle,
    List<_StatMetric> metrics = const [],
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    final surface = theme.colorScheme.surface;
    final onSurface = theme.colorScheme.onSurface;
    final isDark = theme.brightness == Brightness.dark;
    final tint = color.withValues(alpha: isDark ? 0.18 : 0.08);
    final borderColor = theme.colorScheme.outlineVariant.withValues(
      alpha: isDark ? 0.6 : 0.4,
    );

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        color: Color.alphaBlend(tint, surface),
      ),
      child: Theme(
        data: theme.copyWith(
          dividerColor: Colors.transparent,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
        ),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          leading: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: isDark ? 0.26 : 0.16),
              shape: BoxShape.circle,
              border: Border.all(color: color.withValues(alpha: 0.35)),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          title: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: onSurface.withValues(alpha: 0.92),
            ),
          ),
          subtitle: subtitle == null
              ? null
              : Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: onSurface.withValues(alpha: 0.65),
                  ),
                ),
          trailing: Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
              color: onSurface,
            ),
          ),
          children: [
            if (metrics.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: metrics
                      .map(
                        (metric) =>
                            _buildStatMetricPill(metric, fallbackColor: color),
                      )
                      .toList(),
                ),
              ),
            if (onTap != null) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onTap,
                  icon: Icon(Icons.open_in_new, color: color, size: 18),
                  label: Text(
                    'Open details',
                    style: TextStyle(fontWeight: FontWeight.w800, color: color),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader({
    required String title,
    String? subtitle,
    Widget? action,
    Widget? badge,
  }) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  if (badge != null) ...[const SizedBox(width: 8), badge],
                ],
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (action != null) action,
      ],
    );
  }

  Widget _buildRecentActivities() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader(title: 'Recent Activities'),
            const SizedBox(height: 16),
            if (_dashboardStats!.recentActivities.attendances.isNotEmpty) ...[
              const Text(
                'Recent Check-ins',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
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
                        formatManila(attendance.timestamp, 'HH:mm'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  )),
            ],
            if (_dashboardStats!.recentActivities.tasks.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text(
                'Recent Tasks',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
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
                        formatManila(task.createdAt, 'MMM dd'),
                        style: Theme.of(context).textTheme.bodySmall,
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader(title: 'Quick Actions'),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final crossAxisCount = width >= 980
                    ? 3
                    : width >= 640
                    ? 2
                    : 1;

                final actions = <Widget>[
                  _buildQuickActionButton(
                    icon: Icons.people,
                    label: 'Manage Employees',
                    color: Colors.blue,
                    onTap: () {
                      setState(() {
                        _selectedIndex = 1; // Employees tab
                      });
                    },
                  ),
                  _buildQuickActionButton(
                    icon: Icons.admin_panel_settings,
                    label: 'Manage Admins',
                    color: Colors.red,
                    onTap: () {
                      setState(() {
                        _selectedIndex = 2; // Admins tab
                      });
                    },
                  ),
                  _buildQuickActionButton(
                    icon: Icons.location_on,
                    label: 'Add Geofence',
                    color: Colors.green,
                    onTap: () {
                      setState(() {
                        _selectedIndex = 3; // Geofences tab
                      });
                    },
                  ),
                  _buildQuickActionButton(
                    icon: Icons.task,
                    label: 'Create Task',
                    color: Colors.orange,
                    onTap: () {
                      setState(() {
                        _selectedIndex = 6; // Tasks tab
                      });
                    },
                  ),
                  _buildQuickActionButton(
                    icon: Icons.assessment,
                    label: 'View Reports',
                    color: Colors.purple,
                    onTap: () {
                      setState(() {
                        _selectedIndex = 4; // Reports tab
                      });
                    },
                  ),
                  _buildQuickActionButton(
                    icon: Icons.settings,
                    label: 'Settings',
                    color: Colors.teal,
                    onTap: () {
                      setState(() {
                        _selectedIndex = 5; // Settings tab
                      });
                    },
                  ),
                ];

                return GridView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: crossAxisCount == 1 ? 4.2 : 3.4,
                  ),
                  children: actions,
                );
              },
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
    final theme = Theme.of(context);
    final surface = theme.colorScheme.surface;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Color.alphaBlend(
                    color.withValues(alpha: 0.14),
                    surface,
                  ),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: color.withValues(alpha: 0.35)),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w800,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWorldMapSection({required bool isWide}) {
    return Card(
      elevation: 4,
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _panelBorderBlue, width: 1.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: _panelBorderBlue.withValues(alpha: 0.18),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.tune,
                              color: Theme.of(context).colorScheme.primary,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Map Controls',
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.w800,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withValues(alpha: 0.9),
                                      ),
                                ),
                                Text(
                                  'Search, filter, and nearby modes',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withValues(alpha: 0.65),
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildMapControls(),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _buildSectionHeader(
                  title: 'Live Employee Tracking',
                  subtitle: 'Online: $_gpsOnlineCount employees',
                  action: TextButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const AdminWorldMapScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.map, size: 16),
                    label: const Text('Full Map'),
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.primary,
                      textStyle: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            height: 400,
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.12),
                ),
              ),
            ),
            child: Stack(
              children: [
                Container(
                  margin: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(14),
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
                        userAgentPackageName: 'field_check',
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
                        markers: [
                          if (_adminMarkerLocation != null)
                            _buildAdminMarker(_adminMarkerLocation!),
                          ..._liveLocations.entries
                              .where((entry) {
                                final adminId = _currentAdminId();
                                if (adminId != null && entry.key == adminId) {
                                  return false;
                                }
                                return _passesEmployeeFilters(entry.key);
                              })
                              .map((entry) {
                                final user = _employees[entry.key];
                                final empLocation =
                                    _employeeLocations[entry.key];

                                final tooltipText =
                                    (user != null &&
                                        user.name.trim().isNotEmpty)
                                    ? user.name
                                    : ((user != null &&
                                              user.email.trim().isNotEmpty)
                                          ? user.email
                                          : 'Employee');
                                final isBusy =
                                    empLocation?.status == EmployeeStatus.busy;

                                Color markerColor;
                                IconData markerIcon;

                                if (isBusy) {
                                  markerColor = Colors.red;
                                  markerIcon = Icons.schedule;
                                } else if (empLocation?.status ==
                                    EmployeeStatus.available) {
                                  markerColor = Colors.green;
                                  markerIcon = Icons.check_circle;
                                } else {
                                  markerColor = Colors.blue;
                                  markerIcon = Icons.directions_run;
                                }

                                return Marker(
                                  point: entry.value,
                                  width: 40,
                                  height: 40,
                                  child: Material(
                                    type: MaterialType.transparency,
                                    child: InkResponse(
                                      containedInkWell: true,
                                      radius: 24,
                                      highlightShape: BoxShape.circle,
                                      onTap: () {
                                        final id = _canonicalUserId(entry.key);
                                        final selectedUser = _employees[id];
                                        final code =
                                            (selectedUser?.employeeId ?? '')
                                                .trim();
                                        final name = (selectedUser?.name ?? '')
                                            .trim();
                                        final label = code.isNotEmpty
                                            ? code
                                            : (name.isNotEmpty ? name : id);
                                        debugPrint(
                                          '🧭 Marker tapped (map): ${entry.key} -> $id',
                                        );
                                        _pushInspection(id);
                                        _panTo(entry.value, zoom: 16);

                                        if (mounted) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).hideCurrentSnackBar();
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text('Selected $label'),
                                              duration: const Duration(
                                                milliseconds: 900,
                                              ),
                                            ),
                                          );
                                        }

                                        if (!isWide) {
                                          _openInspectionSheet();
                                        }
                                      },
                                      child: _maybeTooltip(
                                        message: tooltipText,
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
                                  ),
                                );
                              }),
                        ],
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: Column(
                    children: [
                      Tooltip(
                        message: 'Fit all employees',
                        child: FloatingActionButton.small(
                          heroTag: 'dashboardFitEmployees',
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black87,
                          onPressed: _fitMapToEmployees,
                          child: const Icon(Icons.center_focus_strong),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Tooltip(
                        message: 'Focus selected employee',
                        child: FloatingActionButton.small(
                          heroTag: 'dashboardFocusSelected',
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black87,
                          onPressed: _focusOnSelectedEmployee,
                          child: const Icon(Icons.my_location),
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(left: 12, bottom: 12, child: _buildMapLegend()),
                // Floating employee indicators at map edges
                if (_liveLocations.isNotEmpty)
                  Positioned.fill(
                    child: IgnorePointer(
                      ignoring: true,
                      child: _buildFloatingEmployeeIndicators(),
                    ),
                  ),
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
                          color: Theme.of(
                            context,
                          ).colorScheme.surface.withValues(alpha: 0.98),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: _panelBorderBlue.withValues(alpha: 0.7),
                            width: 1.5,
                          ),
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
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: _panelBorderBlue.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.location_off,
                                size: 30,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.45),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'No online employees',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Employees will appear here once they log in',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.75),
                                  ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Tap to dismiss',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.6),
                                    fontWeight: FontWeight.w600,
                                  ),
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
              border: Border(
                top: BorderSide(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.10),
                ),
              ),
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.04),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(
                        Icons.pan_tool_alt_outlined,
                        size: 14,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Drag to pan • Scroll to zoom',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.75),
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_liveLocations.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surface.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: Theme.of(
                          context,
                        ).colorScheme.outlineVariant.withValues(alpha: 0.6),
                      ),
                    ),
                    child: Text(
                      '${_trails.length} trails',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.75),
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

  void _autoPanToEmployee(String userId, LatLng location) {
    final id = _canonicalUserId(userId);
    _showEmployeeDetails(id, _employees[id]);
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
                  SizedBox(
                    height: 360,
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
                              if (_isEmployeeOnline(userId) &&
                                  _liveLocations.containsKey(userId))
                                Text(
                                  'Lat: ${_liveLocations[userId]!.latitude.toStringAsFixed(4)}\nLng: ${_liveLocations[userId]!.longitude.toStringAsFixed(4)}',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withValues(alpha: 0.75),
                                      ),
                                )
                              else
                                Text(
                                  'Location not available',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withValues(alpha: 0.7),
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
                                _employeeLocations[userId]?.status ==
                                        EmployeeStatus.busy
                                    ? 'Busy'
                                    : _employeeLocations[userId]?.status ==
                                          EmployeeStatus.available
                                    ? 'Checked In'
                                    : _employeeLocations[userId]?.status ==
                                          EmployeeStatus.offline
                                    ? 'Offline'
                                    : _isEmployeeOnline(userId)
                                    ? 'Online'
                                    : 'Offline',
                                _employeeLocations[userId]?.status ==
                                        EmployeeStatus.busy
                                    ? Colors.red
                                    : _employeeLocations[userId]?.status ==
                                          EmployeeStatus.available
                                    ? Colors.green
                                    : _employeeLocations[userId]?.status ==
                                          EmployeeStatus.offline
                                    ? Colors.grey
                                    : _isEmployeeOnline(userId)
                                    ? Colors.blue
                                    : Colors.grey,
                              ),
                              _buildStatusRow(
                                'Active Tasks',
                                '${_employeeLocations[userId]?.activeTaskCount ?? user?.activeTaskCount ?? 0}',
                                _employeeLocations[userId]?.status ==
                                        EmployeeStatus.busy
                                    ? Colors.red
                                    : Colors.blue,
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
    final user = _employees[userId];
    if (user == null) return const SizedBox.shrink();

    final isOnline = _isEmployeeOnline(userId);
    final loc = _employeeLocations[userId];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStatusRow(
          'Current Status',
          loc?.status == EmployeeStatus.busy
              ? 'Busy'
              : loc?.status == EmployeeStatus.available
              ? 'Checked In'
              : isOnline
              ? 'Online'
              : 'Offline',
          loc?.status == EmployeeStatus.busy
              ? Colors.red
              : loc?.status == EmployeeStatus.available
              ? Colors.green
              : isOnline
              ? Colors.blue
              : Colors.grey,
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
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.85),
            ),
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
                fontSize: 13,
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
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.85),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.75),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingEmployeeIndicators() {
    // Get online employees only
    final adminId = _currentAdminId();
    final onlineEmployees = _liveLocations.entries
        .where((entry) => _isEmployeeOnline(entry.key))
        .where((entry) => adminId == null || entry.key != adminId)
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

    return SizedBox.expand(
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
                        child: _maybeTooltip(
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
                        child: _maybeTooltip(
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
                        child: _maybeTooltip(
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
                        child: _maybeTooltip(
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
    await _ensureAdminMarkerLocation();
  }

  Future<void> _loadEmployeesForMap() async {
    try {
      final employees = await _userService.fetchEmployees();
      if (mounted) {
        setState(() {
          for (final emp in employees) {
            _employees[emp.id] = emp;
          }

          _rebuildEmployeeIdAlias();
          _normalizeMapsToCanonical();
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
          final adminId = _currentAdminId();
          final seenOnlineIds = <String>{};
          for (final emp in response) {
            final rawId =
                (emp['userId'] ?? emp['employeeId'] ?? emp['id'] ?? '')
                    .toString();
            final userId = _canonicalUserId(rawId);
            if (userId.trim().isNotEmpty) {
              seenOnlineIds.add(userId);
            }
            final lat = (emp['latitude'] as num?)?.toDouble();
            final lng = (emp['longitude'] as num?)?.toDouble();
            final name = emp['name'] ?? 'Unknown';

            final nextActiveTaskCount =
                (emp['activeTaskCount'] as num?)?.toInt() ?? 0;

            // Ensure we have a UserModel entry for tooltip/inspector.
            // Sometimes fetchEmployees() may return different ids than the live location feed.
            if (userId.isNotEmpty) {
              final existing = _employees[userId];
              final nextName = (emp['name'] ?? '').toString();
              final nextEmail = (emp['email'] ?? '').toString();
              final nextPhone = (emp['phone'] ?? '').toString();
              final nextRole = (emp['role'] ?? existing?.role ?? 'employee')
                  .toString();
              final nextEmployeeId =
                  (emp['employeeCode'] ?? emp['employeeId'] ?? '').toString();

              if (existing == null) {
                _employees[userId] = UserModel(
                  id: userId,
                  name: nextName,
                  email: nextEmail,
                  phone: nextPhone.trim().isNotEmpty ? nextPhone : null,
                  role: nextRole,
                  employeeId: nextEmployeeId.trim().isNotEmpty
                      ? nextEmployeeId
                      : null,
                  isOnline: true,
                  activeTaskCount: nextActiveTaskCount,
                );
              } else {
                _employees[userId] = UserModel(
                  id: existing.id,
                  name: nextName.trim().isNotEmpty ? nextName : existing.name,
                  email: nextEmail.trim().isNotEmpty
                      ? nextEmail
                      : existing.email,
                  phone: nextPhone.trim().isNotEmpty
                      ? nextPhone
                      : existing.phone,
                  role: nextRole,
                  employeeId: nextEmployeeId.trim().isNotEmpty
                      ? nextEmployeeId
                      : existing.employeeId,
                  avatarUrl: existing.avatarUrl,
                  username: existing.username,
                  isActive: existing.isActive,
                  isVerified: existing.isVerified,
                  lastLatitude: existing.lastLatitude,
                  lastLongitude: existing.lastLongitude,
                  lastLocationUpdate: existing.lastLocationUpdate,
                  isOnline: true,
                  activeTaskCount: nextActiveTaskCount,
                  workloadWeight: existing.workloadWeight,
                );
              }

              final existingLoc = _employeeLocations[userId];
              if (existingLoc != null) {
                _employeeLocations[userId] = EmployeeLocation(
                  employeeId: existingLoc.employeeId,
                  name: existingLoc.name,
                  latitude: existingLoc.latitude,
                  longitude: existingLoc.longitude,
                  accuracy: existingLoc.accuracy,
                  speed: existingLoc.speed,
                  status: existingLoc.status,
                  timestamp: existingLoc.timestamp,
                  activeTaskCount: nextActiveTaskCount,
                  workloadScore: existingLoc.workloadScore,
                  currentGeofence: existingLoc.currentGeofence,
                  distanceToNearestTask: existingLoc.distanceToNearestTask,
                  isOnline: existingLoc.isOnline,
                  batteryLevel: existingLoc.batteryLevel,
                );
              }
            }

            // Only add if we have valid userId and coordinates
            if (userId.isNotEmpty && lat != null && lng != null) {
              if (adminId != null && userId == adminId) {
                _adminMarkerLocation = LatLng(lat, lng);
              }
              _liveLocations[userId] = LatLng(lat, lng);
              _lastGpsUpdate[userId] = DateTime.now();

              final tsRaw = (emp['timestamp'] ?? '').toString();
              final ts = DateTime.tryParse(tsRaw) ?? DateTime.now();
              EmployeeStatus status = EmployeeStatus.moving;
              final statusRaw = (emp['status'] ?? '').toString().trim();
              if (statusRaw.isNotEmpty) {
                status = EmployeeLocation.fromJson({
                  'employeeId': userId,
                  'name': name.toString(),
                  'latitude': lat,
                  'longitude': lng,
                  'accuracy': 0,
                  'status': statusRaw,
                  'timestamp': ts.toIso8601String(),
                  'activeTaskCount': nextActiveTaskCount,
                  'workloadScore': 0,
                  'isOnline': true,
                }).status;
              }

              _employeeLocations[userId] = EmployeeLocation(
                employeeId: userId,
                name: name.toString(),
                latitude: lat,
                longitude: lng,
                accuracy: 0,
                speed: null,
                status: status,
                timestamp: ts,
                activeTaskCount: nextActiveTaskCount,
                workloadScore: 0,
                currentGeofence: null,
                distanceToNearestTask: null,
                isOnline: true,
                batteryLevel: null,
              );

              debugPrint('✅ Added employee $name ($userId) at ($lat, $lng)');
            } else {
              debugPrint(
                '⚠️ Skipped employee $name - missing location data: lat=$lat, lng=$lng',
              );
            }
          }

          // Prune anything not present in the authoritative online list.
          final existingIds = _liveLocations.keys.toList();
          for (final id in existingIds) {
            if (!seenOnlineIds.contains(id)) {
              _liveLocations.remove(id);
              _lastGpsUpdate.remove(id);
              _trails.remove(id);
            }
          }

          final locIds = _employeeLocations.keys.toList();
          for (final id in locIds) {
            final loc = _employeeLocations[id];
            if (loc != null &&
                loc.isOnline == false &&
                !seenOnlineIds.contains(id)) {
              // Keep the offline location object if it helps inspector text,
              // but ensure marker-related maps are cleared above.
              continue;
            }
          }

          _rebuildEmployeeIdAlias();
          _normalizeMapsToCanonical();
          debugPrint('📊 Total locations on map: ${_liveLocations.length}');
        });
      } else {
        debugPrint('⚠️ No response from getOnlineEmployees');
      }
    } catch (e) {
      debugPrint('❌ Error loading online employee locations: $e');
    }
  }

  void _scheduleOnlineEmployeeRefresh() {
    _onlineEmployeesReloadDebounce?.cancel();
    _onlineEmployeesReloadDebounce = Timer(
      const Duration(milliseconds: 600),
      () {
        if (!mounted) return;
        if (_selectedIndex != 0) return;
        _loadOnlineEmployeeLocations();
      },
    );
  }

  void _subscribeToLocations() {
    _employeeLocationsSub?.cancel();
    _employeeLocationsSub = _locationService.employeeLocationsStream.listen((
      locations,
    ) {
      if (!mounted) return;
      setState(() {
        final wasEmpty = _liveLocations.isEmpty;
        final adminId = _currentAdminId();
        for (final empLoc in locations) {
          final pos = LatLng(empLoc.latitude, empLoc.longitude);
          final id = _canonicalUserId(empLoc.employeeId);
          _employeeLocations[id] = empLoc;

          if (adminId != null && id == adminId) {
            _adminMarkerLocation = pos;
          }
          if (empLoc.isOnline) {
            _liveLocations[id] = pos;
            _lastGpsUpdate[id] = DateTime.now();
          } else {
            // Employee logged out / marked offline: remove marker immediately.
            _liveLocations.remove(id);
            _lastGpsUpdate.remove(id);
            _trails.remove(id);
            continue;
          }

          final trail = _trails[id] ?? <LatLng>[];
          if (trail.isEmpty || trail.last != pos) {
            trail.add(pos);
            if (trail.length > 50) {
              trail.removeRange(0, trail.length - 50);
            }
            _trails[id] = trail;
          }
        }

        if (wasEmpty && _liveLocations.isNotEmpty) {
          _showNoEmployeesPopup = false;
        }
      });
    });
  }
}
