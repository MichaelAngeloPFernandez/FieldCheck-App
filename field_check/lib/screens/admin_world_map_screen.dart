// ignore_for_file: use_build_context_synchronously

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'package:field_check/models/user_model.dart';
import 'package:field_check/services/user_service.dart';
import 'package:field_check/services/realtime_service.dart';
import 'package:field_check/services/task_service.dart';
import 'package:field_check/models/task_model.dart';
import 'package:field_check/services/availability_service.dart';
import 'package:field_check/services/employee_location_service.dart';

class AdminWorldMapScreen extends StatefulWidget {
  const AdminWorldMapScreen({super.key});

  @override
  State<AdminWorldMapScreen> createState() => _AdminWorldMapScreenState();
}

class _AdminWorldMapScreenState extends State<AdminWorldMapScreen> {
  final RealtimeService _realtimeService = RealtimeService();
  final UserService _userService = UserService();
  final TaskService _taskService = TaskService();
  final AvailabilityService _availabilityService = AvailabilityService();
  final EmployeeLocationService _locationService = EmployeeLocationService();

  final Map<String, UserModel> _employees = {};
  final Map<String, LatLng> _liveLocations = {};
  final Map<String, List<LatLng>> _trails = {};
  List<EmployeeLocation> _employeeLocations = [];

  final Map<String, _WorldAvailability> _availability = {};

  StreamSubscription<Map<String, dynamic>>? _locationSub;
  StreamSubscription<List<EmployeeLocation>>? _employeeLocationSub;
  bool _loadingUsers = true;
  String? _selectedUserId;
  List<Task> _selectedUserTasks = const [];
  bool _loadingTasks = false;
  bool _loadingAvailability = false;
  DateTime? _availabilityUpdatedAt;

  static const LatLng _defaultCenter = LatLng(14.5995, 120.9842); // Manila

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _realtimeService.initialize();
    await _locationService.initialize();
    await _loadEmployees();
    _subscribeToLocations();
    _subscribeToEmployeeLocations();
    await _refreshAvailability();
  }

  void _subscribeToEmployeeLocations() {
    _employeeLocationSub = _locationService.employeeLocationsStream.listen((
      locations,
    ) {
      if (mounted) {
        setState(() {
          _employeeLocations = locations;
          // Update live locations
          for (final emp in locations) {
            final point = LatLng(emp.latitude, emp.longitude);
            _liveLocations[emp.employeeId] = point;

            // Update trails
            final trail = _trails[emp.employeeId] ?? <LatLng>[];
            if (trail.isEmpty || trail.last != point) {
              trail.add(point);
              if (trail.length > 50) {
                trail.removeRange(0, trail.length - 50);
              }
              _trails[emp.employeeId] = trail;
            }
          }
        });
      }
    });
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

  void _subscribeToLocations() {
    _locationSub = _realtimeService.locationStream.listen((event) {
      final userId = event['userId']?.toString();
      final lat = (event['latitude'] as num?)?.toDouble();
      final lng = (event['longitude'] as num?)?.toDouble();
      if (userId == null || lat == null || lng == null) return;

      final pos = LatLng(lat, lng);
      setState(() {
        _liveLocations[userId] = pos;
        final trail = _trails[userId] ?? <LatLng>[];
        trail.add(pos);
        // Keep only last 50 points per employee to avoid memory bloat
        if (trail.length > 50) {
          trail.removeRange(0, trail.length - 50);
        }
        _trails[userId] = trail;
      });
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
    _locationSub?.cancel();
    _employeeLocationSub?.cancel();
    _locationService.dispose();
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
      final tasks = await _taskService.fetchAssignedTasks(userId);
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('World Map - Live Employees'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshAvailability,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 3,
            child: FlutterMap(
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
                PolylineLayer(
                  polylines: _trails.entries.map((e) {
                    return Polyline(
                      points: e.value,
                      strokeWidth: 2,
                      color: Colors.green.withValues(alpha: 0.5),
                    );
                  }).toList(),
                ),
                MarkerLayer(
                  markers: _liveLocations.entries.map((entry) {
                    final user = _employees[entry.key];
                    final empLocation = _employeeLocations.firstWhere(
                      (e) => e.employeeId == entry.key,
                      orElse: () => _employeeLocations.isNotEmpty
                          ? _employeeLocations.first
                          : EmployeeLocation(
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

                    // Get color based on EmployeeStatus (green for available/moving, red for busy)
                    Color markerColor;
                    IconData markerIcon;
                    switch (empLocation.status) {
                      case EmployeeStatus.available:
                        markerColor = Colors.green;
                        markerIcon = Icons.check_circle;
                        break;
                      case EmployeeStatus.moving:
                        markerColor = Colors.green;
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

                    return Marker(
                      point: entry.value,
                      width: 50,
                      height: 50,
                      child: GestureDetector(
                        onTap: () => _onEmployeeTap(entry.key),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: markerColor,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: markerColor.withValues(alpha: 0.5),
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
                            const SizedBox(height: 2),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(3),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.1),
                                    blurRadius: 2,
                                  ),
                                ],
                              ),
                              child: Text(
                                user?.name.split(' ').first ?? 'Emp',
                                style: const TextStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          Container(
            height: 220,
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              color: Color(0xFFF5F7FA),
              border: Border(top: BorderSide(color: Colors.black12)),
            ),
            child: _buildBottomPanel(),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomPanel() {
    if (_loadingUsers) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_liveLocations.isEmpty) {
      return const Center(
        child: Text(
          'No online employees with live location.\nEmployees will appear here once they are checked in and sharing GPS.',
          textAlign: TextAlign.center,
        ),
      );
    }

    final selectedUser = _selectedUserId != null
        ? _employees[_selectedUserId!]
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Online employees: ${_liveLocations.length}',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            if (selectedUser != null)
              Text(
                selectedUser.name,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        if (_loadingAvailability)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else
          Text(
            _availability.isEmpty
                ? 'Workload data not available for online employees.'
                : _buildWorkloadSummary(),
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
        const SizedBox(height: 8),
        Expanded(
          child: _selectedUserId == null
              ? _buildEmployeeList()
              : _buildSelectedEmployeeDetails(selectedUser),
        ),
      ],
    );
  }

  String _buildWorkloadSummary() {
    if (_availability.isEmpty) {
      return 'Workload data not available for online employees.';
    }

    int available = 0;
    int busy = 0;
    int overloaded = 0;
    int totalActive = 0;
    int totalOverdue = 0;

    _availability.forEach((_, info) {
      switch (info.workloadStatus) {
        case 'overloaded':
          overloaded++;
          break;
        case 'busy':
          busy++;
          break;
        default:
          available++;
      }
      totalActive += info.activeTasksCount;
      totalOverdue += info.overdueTasksCount;
    });

    final parts = <String>[
      'Available: $available',
      'Busy: $busy',
      'Overloaded: $overloaded',
      'Active tasks: $totalActive',
    ];

    if (totalOverdue > 0) {
      parts.add('Overdue: $totalOverdue');
    }

    if (_availabilityUpdatedAt != null) {
      final time = TimeOfDay.fromDateTime(_availabilityUpdatedAt!);
      parts.add('Updated: ${time.format(context)}');
    }

    return parts.join(' · ');
  }

  Widget _buildEmployeeList() {
    final entries = _liveLocations.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        final user = _employees[entry.key];
        final info = _availability[entry.key];
        Color iconColor;
        if (info == null) {
          iconColor = Colors.blueGrey;
        } else {
          switch (info.workloadStatus) {
            case 'overloaded':
              iconColor = Colors.redAccent;
              break;
            case 'busy':
              iconColor = Colors.orange;
              break;
            default:
              iconColor = Colors.green;
          }
        }

        String subtitle =
            'Lat: ${entry.value.latitude.toStringAsFixed(4)}, Lng: ${entry.value.longitude.toStringAsFixed(4)}';
        if (info != null) {
          final parts = <String>[];
          parts.add(info.workloadStatus);
          if (info.activeTasksCount > 0) {
            parts.add('${info.activeTasksCount} active');
          }
          if (info.overdueTasksCount > 0) {
            parts.add('${info.overdueTasksCount} overdue');
          }
          subtitle = '$subtitle · ${parts.join(' · ')}';
        }
        return ListTile(
          leading: Icon(Icons.person_pin_circle, color: iconColor),
          title: Text(user?.name ?? entry.key),
          subtitle: Text(subtitle),
          onTap: () => _onEmployeeTap(entry.key),
        );
      },
    );
  }

  Widget _buildSelectedEmployeeDetails(UserModel? user) {
    if (user == null) {
      return const Center(child: Text('Employee details not available'));
    }

    if (_loadingTasks) {
      return const Center(child: CircularProgressIndicator());
    }

    final info = _availability[user.id];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              user.name,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                setState(() {
                  _selectedUserId = null;
                  _selectedUserTasks = const [];
                });
              },
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          user.email,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        if (info != null) ...[
          const SizedBox(height: 4),
          Text(
            'Workload: ${info.workloadStatus} · Active: ${info.activeTasksCount}, Overdue: ${info.overdueTasksCount}',
            style: const TextStyle(fontSize: 12, color: Colors.black87),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          'Assigned tasks: ${_selectedUserTasks.length}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: _selectedUserTasks.isEmpty
              ? const Center(child: Text('No active tasks for this employee'))
              : ListView.builder(
                  itemCount: _selectedUserTasks.length,
                  itemBuilder: (context, index) {
                    final task = _selectedUserTasks[index];
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.task_alt),
                      title: Text(task.title),
                      subtitle: Text(task.status),
                    );
                  },
                ),
        ),
      ],
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
