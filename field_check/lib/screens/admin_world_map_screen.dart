// ignore_for_file: use_build_context_synchronously

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'package:field_check/models/user_model.dart';
import 'package:field_check/services/user_service.dart';
import 'package:field_check/services/task_service.dart';
import 'package:field_check/models/task_model.dart';
import 'package:field_check/services/availability_service.dart';
import 'package:field_check/services/employee_location_service.dart';
import 'package:field_check/services/geofence_service.dart';
import 'package:field_check/services/realtime_service.dart';
import 'package:field_check/widgets/app_widgets.dart';
import 'package:field_check/models/geofence_model.dart';

class AdminWorldMapScreen extends StatefulWidget {
  const AdminWorldMapScreen({super.key});

  @override
  State<AdminWorldMapScreen> createState() => _AdminWorldMapScreenState();
}

class _AdminWorldMapScreenState extends State<AdminWorldMapScreen> {
  final UserService _userService = UserService();
  final TaskService _taskService = TaskService();
  final AvailabilityService _availabilityService = AvailabilityService();
  final EmployeeLocationService _locationService = EmployeeLocationService();
  final GeofenceService _geofenceService = GeofenceService();
  final RealtimeService _realtimeService = RealtimeService();
  final MapController _mapController = MapController();

  final Map<String, UserModel> _employees = {};
  final Map<String, LatLng> _liveLocations = {};
  final Map<String, List<LatLng>> _trails = {};
  final List<EmployeeLocation> _employeeLocations = [];

  final Map<String, _WorldAvailability> _availability = {};

  StreamSubscription<List<EmployeeLocation>>? _employeeLocationSub;
  StreamSubscription<Map<String, dynamic>>? _adminNearbySub;
  bool _loadingUsers = true;
  String? _selectedUserId;
  List<Task> _selectedUserTasks = const [];
  bool _loadingTasks = false;
  bool _loadingAvailability = false;
  DateTime? _availabilityUpdatedAt;
  bool _didInitialFit = false;

  bool _filterAvailable = true;
  bool _filterBusy = true;
  bool _filterOverloaded = true;

  bool _isFullscreen = false;

  Timer? _snapshotRefreshTimer;

  String _adminNearbyMode = 'off';
  LatLng? _adminNearbyLatLng;
  double _adminNearbyRadiusMeters = 2000;

  List<Geofence> _geofences = const [];

  static const LatLng _defaultCenter = LatLng(14.5995, 120.9842); // Manila

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _locationService.initialize();
    _subscribeToLocations();
    // Seed any cached snapshot immediately so the screen doesn't start empty
    // while waiting for the next socket event.
    _applyLocations(_locationService.getAllLocations());
    await _initAdminNearby();
    await _loadGeofences();
    await _loadEmployees();
    await _refreshAvailability();

    _snapshotRefreshTimer?.cancel();
    _snapshotRefreshTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      if (!mounted) return;
      _applyLocations(_locationService.getAllLocations());
    });
  }

  Future<void> _initAdminNearby() async {
    await _realtimeService.initialize();
    _adminNearbySub?.cancel();
    _adminNearbySub = _realtimeService.adminNearbyStream.listen((data) {
      final mode = (data['mode'] ?? 'off').toString();
      final lat = data['latitude'];
      final lng = data['longitude'];
      final radius = data['radiusMeters'];
      final nextLat = lat is num ? lat.toDouble() : null;
      final nextLng = lng is num ? lng.toDouble() : null;
      final nextRadius = radius is num ? radius.toDouble() : null;

      if (!mounted) return;
      setState(() {
        _adminNearbyMode = mode;
        _adminNearbyLatLng =
            (mode != 'off' && nextLat != null && nextLng != null)
            ? LatLng(nextLat, nextLng)
            : null;
        if (nextRadius != null && nextRadius > 0) {
          _adminNearbyRadiusMeters = nextRadius;
        }
      });
    });
  }

  Future<void> _loadGeofences() async {
    try {
      final fences = await _geofenceService.fetchGeofences();
      if (!mounted) return;
      setState(() {
        _geofences = fences;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _geofences = const [];
      });
    }
  }

  List<CircleMarker> _buildActiveGeofenceCircles() {
    if (_geofences.isEmpty) return const [];
    return _geofences.where((g) => g.isActive).map((g) {
      return CircleMarker(
        point: LatLng(g.latitude, g.longitude),
        useRadiusInMeter: true,
        radius: g.radius,
        color: Colors.green.withValues(alpha: 0.12),
        borderColor: Colors.green.withValues(alpha: 0.65),
        borderStrokeWidth: 2,
      );
    }).toList();
  }

  CircleMarker? _buildAdminNearbyRadiusCircle() {
    if (_adminNearbyMode == 'off') return null;
    final center = _adminNearbyLatLng;
    if (center == null) return null;
    return CircleMarker(
      point: center,
      useRadiusInMeter: true,
      radius: _adminNearbyRadiusMeters,
      color: const Color(0xFF5C4EF5).withValues(alpha: 0.08),
      borderColor: const Color(0xFF5C4EF5).withValues(alpha: 0.55),
      borderStrokeWidth: 2,
    );
  }

  void _applyLocations(List<EmployeeLocation> locations) {
    if (!mounted) return;

    // Only include online employees in the nextIds set
    final nextIds = <String>{};
    for (final loc in locations) {
      if (loc.isOnline && loc.status != EmployeeStatus.offline) {
        nextIds.add(loc.employeeId);
      }
    }

    setState(() {
      _employeeLocations
        ..clear()
        ..addAll(locations);

      // Remove employees that are no longer online.
      if (_liveLocations.isNotEmpty) {
        final existing = _liveLocations.keys.toList();
        for (final id in existing) {
          if (!nextIds.contains(id)) {
            _liveLocations.remove(id);
            _trails.remove(id);
          }
        }
      }

      if (_selectedUserId != null && !nextIds.contains(_selectedUserId)) {
        _selectedUserId = null;
        _selectedUserTasks = const [];
      }

      // Only add live locations for online employees
      for (final empLoc in locations) {
        if (!empLoc.isOnline || empLoc.status == EmployeeStatus.offline) {
          // Don't add to live locations.
          continue;
        }

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
    });

    if (!_didInitialFit && _liveLocations.isNotEmpty) {
      _didInitialFit = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _fitToEmployees();
      });
    }
  }

  Future<void> _loadEmployees() async {
    try {
      final users = await _userService.fetchEmployees();
      if (!mounted) return;
      setState(() {
        for (final u in users) {
          _employees[u.id] = u;
        }
        _loadingUsers = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingUsers = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load employees: $e')));
    }
  }

  Map<String, LatLng> _visibleLiveLocations() {
    final filteredLocations = _employeeLocations.where(_passesFilters).toList();
    final map = <String, LatLng>{};
    for (final loc in filteredLocations) {
      final pos = _liveLocations[loc.employeeId];
      if (pos != null) {
        map[loc.employeeId] = pos;
      }
    }
    return map;
  }

  LatLngBounds? _boundsForEmployees() {
    final visible = _visibleLiveLocations();
    if (visible.isEmpty) return null;
    final points = visible.values.toList();
    final bounds = LatLngBounds(points.first, points.first);
    for (final p in points.skip(1)) {
      bounds.extend(p);
    }
    return bounds;
  }

  void _fitToEmployees() {
    final bounds = _boundsForEmployees();
    if (bounds == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No visible employee locations to fit'),
          duration: Duration(milliseconds: 1200),
        ),
      );
      return;
    }
    try {
      _mapController.fitCamera(
        CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(48)),
      );
    } catch (_) {
      _mapController.move(bounds.center, 4);
    }
  }

  List<String> _visibleEmployeeIds() {
    final filteredLocations = _employeeLocations.where(_passesFilters).toList();
    final ids = <String>[];
    for (final loc in filteredLocations) {
      final pos = _liveLocations[loc.employeeId];
      if (pos != null) {
        ids.add(loc.employeeId);
      }
    }

    ids.sort((a, b) {
      final an = (_employees[a]?.name ?? '').toLowerCase();
      final bn = (_employees[b]?.name ?? '').toLowerCase();
      return an.compareTo(bn);
    });
    return ids;
  }

  void _panToEmployee(String userId) {
    final visible = _visibleLiveLocations();
    final pos = visible[userId];
    if (pos == null) return;
    _mapController.move(pos, 15);
  }

  void _selectPrevEmployee() {
    final ids = _visibleEmployeeIds();
    if (ids.isEmpty) return;

    final currentIndex = _selectedUserId == null
        ? -1
        : ids.indexWhere((id) => id == _selectedUserId);
    final nextIndex = currentIndex <= 0 ? (ids.length - 1) : (currentIndex - 1);
    final nextId = ids[nextIndex];

    setState(() {
      _selectedUserId = nextId;
    });
    _onEmployeeTap(nextId);
    _panToEmployee(nextId);
  }

  void _selectNextEmployee() {
    final ids = _visibleEmployeeIds();
    if (ids.isEmpty) return;

    final currentIndex = _selectedUserId == null
        ? -1
        : ids.indexWhere((id) => id == _selectedUserId);
    final nextIndex = (currentIndex < 0 || currentIndex >= ids.length - 1)
        ? 0
        : (currentIndex + 1);
    final nextId = ids[nextIndex];

    setState(() {
      _selectedUserId = nextId;
    });
    _onEmployeeTap(nextId);
    _panToEmployee(nextId);
  }

  Widget _buildPrevNextControls({required double top}) {
    final ids = _visibleEmployeeIds();
    if (ids.length < 2) return const SizedBox.shrink();

    return Positioned(
      top: top,
      right: 16,
      child: Card(
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Previous employee',
                onPressed: _selectPrevEmployee,
                icon: const Icon(Icons.chevron_left),
              ),
              IconButton(
                tooltip: 'Next employee',
                onPressed: _selectNextEmployee,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _focusOnSelection() {
    final visible = _visibleLiveLocations();
    LatLng? target;
    if (_selectedUserId != null) {
      target = visible[_selectedUserId!];
    }
    target ??= visible.values.isNotEmpty ? visible.values.first : null;
    if (target == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No visible employee to focus'),
          duration: Duration(milliseconds: 1200),
        ),
      );
      return;
    }

    _mapController.move(target, 15);
  }

  Widget _buildLegendItem({
    required Color color,
    required IconData icon,
    required String label,
  }) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icon, size: 12, color: Colors.white),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: onSurface.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegend() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _buildLegendItem(
          color: Colors.green,
          icon: Icons.check_circle,
          label: 'Available',
        ),
        _buildLegendItem(
          color: Colors.blue,
          icon: Icons.directions_run,
          label: 'Moving',
        ),
        _buildLegendItem(
          color: Colors.red,
          icon: Icons.schedule,
          label: 'Busy',
        ),
        _buildLegendItem(
          color: Colors.grey,
          icon: Icons.cloud_off,
          label: 'Offline',
        ),
      ],
    );
  }

  bool _passesFilters(EmployeeLocation loc) {
    // Never show offline employees on the map
    if (loc.status == EmployeeStatus.offline || !loc.isOnline) {
      return false;
    }

    if (loc.status == EmployeeStatus.busy) {
      if (!_filterBusy) return false;
    }

    if (loc.status == EmployeeStatus.available) {
      if (!_filterAvailable) return false;
    }

    final availability = _availability[loc.employeeId];
    final workload = (availability?.workloadStatus ?? '').toLowerCase();
    if (workload == 'overloaded' && !_filterOverloaded) {
      return false;
    }

    return true;
  }

  Color _workloadTagColor(String workload) {
    final w = workload.toLowerCase();
    if (w == 'overloaded') return Colors.deepOrange;
    if (w == 'busy') return Colors.red;
    return Colors.green;
  }

  Widget _workloadTag(String label) {
    final color = _workloadTagColor(label);
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 12,
          color: onSurface.withValues(alpha: 0.85),
        ),
      ),
    );
  }

  Widget _metricBar({
    required String label,
    required int value,
    required int max,
    required Color color,
  }) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final v = value.clamp(0, max);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: onSurface.withValues(alpha: 0.72),
              ),
            ),
            Text(
              '$value',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: onSurface.withValues(alpha: 0.85),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: max <= 0 ? 0 : (v / max).clamp(0.0, 1.0),
            minHeight: 8,
            backgroundColor: Theme.of(
              context,
            ).dividerColor.withValues(alpha: 0.25),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }

  Widget _buildEmployeeDetailsPanel(BoxConstraints constraints) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    final selectedId = _selectedUserId;
    final selectedUser = selectedId != null ? _employees[selectedId] : null;
    final avail = selectedId != null ? _availability[selectedId] : null;

    EmployeeLocation? loc;
    if (selectedId != null) {
      try {
        loc = _employeeLocations.firstWhere((e) => e.employeeId == selectedId);
      } catch (_) {
        loc = null;
      }
    }

    final email = selectedUser?.email ?? '';
    final workloadLabel = (avail?.workloadStatus ?? 'available');

    final tasks = _selectedUserTasks;
    final int assigned = tasks.length;
    final now = DateTime.now();
    final int overdue = tasks.where((t) => t.dueDate.isBefore(now)).length;
    final int active = tasks
        .where((t) => t.status.toLowerCase() != 'completed')
        .length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.35)),
      ),
      child: selectedUser == null
          ? Center(
              child: Text(
                'Select an employee marker to view details',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: onSurface.withValues(alpha: 0.70),
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(
                          alpha: 0.12,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Center(
                        child: AppWidgets.userAvatar(
                          radius: 18,
                          avatarUrl: selectedUser.avatarUrl,
                          initials: selectedUser.name.trim().isNotEmpty
                              ? selectedUser.name.characters.first.toUpperCase()
                              : '?',
                          backgroundColor: theme.colorScheme.primary,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            selectedUser.name,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: onSurface.withValues(alpha: 0.92),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            email,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: onSurface.withValues(alpha: 0.68),
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _workloadTag(workloadLabel),
                              if (loc != null)
                                _workloadTag(
                                  loc.status.name[0].toUpperCase() +
                                      loc.status.name.substring(1),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        setState(() {
                          _selectedUserId = null;
                          _selectedUserTasks = const [];
                        });
                      },
                      icon: const Icon(Icons.close),
                      color: onSurface.withValues(alpha: 0.65),
                      tooltip: 'Clear selection',
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Task Summary',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: onSurface.withValues(alpha: 0.86),
                  ),
                ),
                const SizedBox(height: 12),
                _metricBar(
                  label: 'Assigned',
                  value: assigned,
                  max: (assigned <= 0 ? 1 : (assigned < 12 ? 12 : assigned)),
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 12),
                _metricBar(
                  label: 'Active',
                  value: active,
                  max: (assigned <= 0 ? 1 : (assigned < 12 ? 12 : assigned)),
                  color: Colors.blue,
                ),
                const SizedBox(height: 12),
                _metricBar(
                  label: 'Overdue',
                  value: overdue,
                  max: (assigned <= 0 ? 1 : (assigned < 12 ? 12 : assigned)),
                  color: Colors.red,
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: _loadingTasks
                      ? const Center(child: CircularProgressIndicator())
                      : (tasks.isEmpty
                            ? Center(
                                child: Text(
                                  'No assigned tasks',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: onSurface.withValues(alpha: 0.65),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              )
                            : ListView.separated(
                                itemCount: tasks.length,
                                separatorBuilder: (context, index) => Divider(
                                  height: 16,
                                  color: theme.dividerColor.withValues(
                                    alpha: 0.35,
                                  ),
                                ),
                                itemBuilder: (context, index) {
                                  final t = tasks[index];
                                  final due = t.dueDate;
                                  final isOver = due.isBefore(now);
                                  final title = t.title.trim();
                                  return Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 10,
                                        height: 10,
                                        margin: const EdgeInsets.only(top: 4),
                                        decoration: BoxDecoration(
                                          color: isOver
                                              ? Colors.red
                                              : Colors.blue,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              title,
                                              style: theme.textTheme.bodyMedium
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w700,
                                                    color: onSurface.withValues(
                                                      alpha: 0.88,
                                                    ),
                                                  ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                top: 2,
                                              ),
                                              child: Text(
                                                'Due: ${due.toLocal().toString().split('.').first}',
                                                style: theme.textTheme.bodySmall
                                                    ?.copyWith(
                                                      color: onSurface
                                                          .withValues(
                                                            alpha: 0.62,
                                                          ),
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              )),
                ),
              ],
            ),
    );
  }

  Widget _buildFooterBar() {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    final last = _availabilityUpdatedAt;
    final timeText = last == null
        ? 'Updated: -'
        : 'Updated: ${TimeOfDay.fromDateTime(last).format(context)}';

    final width = MediaQuery.sizeOf(context).width;
    final bool compact = width < 720;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.35)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    timeText,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: onSurface.withValues(alpha: 0.72),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilterChip(
                        selected: _filterAvailable,
                        label: const Text('Available'),
                        onSelected: (v) => setState(() => _filterAvailable = v),
                      ),
                      FilterChip(
                        selected: _filterBusy,
                        label: const Text('Busy'),
                        onSelected: (v) => setState(() => _filterBusy = v),
                      ),
                      FilterChip(
                        selected: _filterOverloaded,
                        label: const Text('Overloaded'),
                        onSelected: (v) =>
                            setState(() => _filterOverloaded = v),
                      ),
                    ],
                  ),
                ],
              )
            : Row(
                children: [
                  Expanded(
                    child: Text(
                      timeText,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: onSurface.withValues(alpha: 0.72),
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilterChip(
                        selected: _filterAvailable,
                        label: const Text('Available'),
                        onSelected: (v) => setState(() => _filterAvailable = v),
                      ),
                      FilterChip(
                        selected: _filterBusy,
                        label: const Text('Busy'),
                        onSelected: (v) => setState(() => _filterBusy = v),
                      ),
                      FilterChip(
                        selected: _filterOverloaded,
                        label: const Text('Overloaded'),
                        onSelected: (v) =>
                            setState(() => _filterOverloaded = v),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  void _subscribeToLocations() {
    // Subscribe to employee locations from EmployeeLocationService for consistency
    _employeeLocationSub = _locationService.employeeLocationsStream.listen((
      locations,
    ) {
      _applyLocations(locations);
    });
  }

  Future<void> _refreshAvailability() async {
    setState(() {
      _loadingAvailability = true;
    });

    try {
      final items = await _availabilityService.getOnlineAvailability();
      if (!mounted) {
        return;
      }

      final map = <String, _WorldAvailability>{};
      for (final item in items) {
        final String userId = (item['userId'] ?? '') as String;
        if (userId.isEmpty) {
          continue;
        }
        final int activeTasksCount = item['activeTasksCount'] is int
            ? item['activeTasksCount'] as int
            : (item['activeTasksCount'] ?? 0) as int;
        final int overdueTasksCount = item['overdueTasksCount'] is int
            ? item['overdueTasksCount'] as int
            : (item['overdueTasksCount'] ?? 0) as int;
        final String workloadStatus =
            (item['workloadStatus'] ?? 'available') as String;
        map[userId] = _WorldAvailability(
          activeTasksCount: activeTasksCount,
          overdueTasksCount: overdueTasksCount,
          workloadStatus: workloadStatus,
        );
      }

      setState(() {
        _availability
          ..clear()
          ..addAll(map);
        _loadingAvailability = false;
        _availabilityUpdatedAt = DateTime.now();
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingAvailability = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load availability: $e')),
      );
    }
  }

  @override
  void dispose() {
    _employeeLocationSub?.cancel();
    _adminNearbySub?.cancel();
    _snapshotRefreshTimer?.cancel();
    super.dispose();
  }

  LatLng _currentCenter() {
    if (_liveLocations.isEmpty) return _defaultCenter;
    // Center on first live employee for simplicity
    return _liveLocations.values.first;
  }

  Future<void> _onEmployeeTap(String userId) async {
    setState(() {
      _selectedUserId = userId;
      _loadingTasks = true;
      _selectedUserTasks = const [];
    });
    try {
      final tasks = await _taskService.fetchAssignedTasks(
        userId,
        archived: false,
      );
      if (!mounted) return;
      setState(() {
        _selectedUserTasks = tasks;
        _loadingTasks = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingTasks = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load tasks: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final center = _currentCenter();

    final topInset = MediaQuery.paddingOf(context).top;
    final overlayTop = topInset + kToolbarHeight + 12;

    final filteredLocations = _employeeLocations.where(_passesFilters).toList();

    // Include both online employees and offline employees in transition period
    final filteredLive = <String, LatLng>{};

    // Add online employees
    for (final loc in filteredLocations) {
      final pos = _liveLocations[loc.employeeId];
      if (pos != null) {
        filteredLive[loc.employeeId] = pos;
      }
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Live Employee Map'),
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1E3A8A), Color(0xFF2563EB)],
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
            ),
            onPressed: () {
              setState(() {
                _isFullscreen = !_isFullscreen;
              });
            },
            tooltip: _isFullscreen ? 'Exit full screen' : 'Full screen',
          ),
          if (_loadingAvailability)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _refreshAvailability,
              tooltip: 'Refresh',
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (_loadingUsers) {
              return Column(
                children: [
                  const Expanded(
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  _buildFooterBar(),
                ],
              );
            }

            final isWide = constraints.maxWidth >= 980;
            final sideWidth = isWide
                ? (constraints.maxWidth * 0.30).clamp(320.0, 420.0)
                : constraints.maxWidth;

            final bodyTopPad = topInset + kToolbarHeight + 12;

            final mapWidget = Container(
              margin: _isFullscreen
                  ? EdgeInsets.fromLTRB(0, bodyTopPad, 0, 0)
                  : EdgeInsets.fromLTRB(16, bodyTopPad, 16, 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: _isFullscreen
                    ? BorderRadius.zero
                    : BorderRadius.circular(18),
                child: Stack(
                  children: [
                    FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: center,
                        initialZoom: 3,
                        maxZoom: 18,
                        minZoom: 2,
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                              'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                          subdomains: const ['a', 'b', 'c'],
                        ),
                        CircleLayer(
                          circles: [
                            ..._buildActiveGeofenceCircles(),
                            if (_buildAdminNearbyRadiusCircle() != null)
                              _buildAdminNearbyRadiusCircle()!,
                          ],
                        ),
                        PolylineLayer(
                          polylines: _trails.entries.map((e) {
                            return Polyline(
                              points: e.value,
                              strokeWidth: 2,
                              color: Colors.green.withValues(alpha: 0.4),
                            );
                          }).toList(),
                        ),
                        MarkerLayer(
                          markers: [
                            if (_adminNearbyMode != 'off' &&
                                _adminNearbyLatLng != null)
                              Marker(
                                point: _adminNearbyLatLng!,
                                width: 52,
                                height: 52,
                                child: Container(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: const Color(
                                      0xFF5C4EF5,
                                    ).withValues(alpha: 0.95),
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 3,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(
                                          0xFF5C4EF5,
                                        ).withValues(alpha: 0.35),
                                        blurRadius: 16,
                                        offset: const Offset(0, 10),
                                      ),
                                    ],
                                  ),
                                  child: const Center(
                                    child: Icon(
                                      Icons.admin_panel_settings,
                                      color: Colors.white,
                                      size: 24,
                                    ),
                                  ),
                                ),
                              ),
                            ...filteredLive.entries.map((entry) {
                              final user = _employees[entry.key];
                              final empLocation = filteredLocations.firstWhere(
                                (e) => e.employeeId == entry.key,
                                orElse: () => EmployeeLocation(
                                  employeeId: entry.key,
                                  name: user?.name ?? 'Unknown',
                                  latitude: entry.value.latitude,
                                  longitude: entry.value.longitude,
                                  accuracy: 0,
                                  status: EmployeeStatus.offline,
                                  timestamp: DateTime.now(),
                                  activeTaskCount: 0,
                                  workloadScore: 0,
                                  isOnline: false,
                                ),
                              );

                              Color markerColor;

                              final IconData markerIcon;

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
                                  markerIcon = Icons.person;
                                  break;
                              }

                              return Marker(
                                point: entry.value,
                                width: 54,
                                height: 54,
                                child: GestureDetector(
                                  onTap: () {
                                    _onEmployeeTap(entry.key);
                                    _panToEmployee(entry.key);
                                  },
                                  child: Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: markerColor,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 3,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: markerColor.withValues(
                                            alpha: 0.35,
                                          ),
                                          blurRadius: 16,
                                          offset: const Offset(0, 10),
                                        ),
                                      ],
                                    ),
                                    child: Center(
                                      child:
                                          (user != null &&
                                              (user.avatarUrl ?? '')
                                                  .trim()
                                                  .isNotEmpty)
                                          ? AppWidgets.userAvatar(
                                              radius: 17,
                                              avatarUrl: user.avatarUrl,
                                              initials:
                                                  user.name.trim().isNotEmpty
                                                  ? user.name.characters.first
                                                        .toUpperCase()
                                                  : '?',
                                              backgroundColor:
                                                  Colors.transparent,
                                              foregroundColor: Colors.white,
                                              fallbackIcon: markerIcon,
                                            )
                                          : Icon(
                                              markerIcon,
                                              color: Colors.white,
                                              size: 24,
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
                    _buildPrevNextControls(top: overlayTop + 108),
                    Positioned(
                      top: overlayTop,
                      right: 14,
                      child: Column(
                        children: [
                          FloatingActionButton.small(
                            heroTag: 'fitEmployees',
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black87,
                            onPressed: _fitToEmployees,
                            child: const Icon(Icons.center_focus_strong),
                          ),
                          const SizedBox(height: 10),
                          FloatingActionButton.small(
                            heroTag: 'focusSelected',
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black87,
                            onPressed: _focusOnSelection,
                            child: const Icon(Icons.my_location),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      left: 14,
                      bottom: 14,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.10),
                              blurRadius: 18,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: _buildLegend(),
                      ),
                    ),
                  ],
                ),
              ),
            );

            final panelWidget = SizedBox(
              width: sideWidth,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  isWide ? 0 : 16,
                  bodyTopPad,
                  16,
                  12,
                ),
                child: _buildEmployeeDetailsPanel(constraints),
              ),
            );

            final content = (isWide && !_isFullscreen)
                ? Row(
                    children: [
                      Expanded(child: mapWidget),
                      panelWidget,
                    ],
                  )
                : (isWide && _isFullscreen)
                ? Row(children: [Expanded(child: mapWidget)])
                : Column(
                    children: [
                      Expanded(child: mapWidget),
                      SizedBox(height: 360, child: panelWidget),
                    ],
                  );

            return Column(
              children: [
                Expanded(child: content),
                if (!_isFullscreen) _buildFooterBar(),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _WorldAvailability {
  final int activeTasksCount;
  final int overdueTasksCount;
  final String workloadStatus;

  const _WorldAvailability({
    required this.activeTasksCount,
    required this.overdueTasksCount,
    required this.workloadStatus,
  });
}
