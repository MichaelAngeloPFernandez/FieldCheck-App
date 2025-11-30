// ignore_for_file: use_build_context_synchronously, deprecated_member_use
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:async';
import 'package:field_check/services/location_service.dart';
import 'package:field_check/services/geofence_service.dart';
import 'package:field_check/models/geofence_model.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:field_check/services/user_service.dart';
import 'package:field_check/services/task_service.dart';
import 'package:field_check/models/task_model.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final LocationService _locationService = LocationService();
  final GeofenceService _geofenceService = GeofenceService();
  final UserService _userService = UserService();
  final TaskService _taskService = TaskService();

  LatLng? _userLatLng;
  List<Geofence> _geofences = [];
  List<Geofence> _assignedGeofences = [];
  List<Geofence> _allGeofences = [];
  List<Task> _tasksAssigned = [];
  List<Task> _tasksAll = [];
  List<Task> _visibleTasks = [];
  String? _userModelId;
  bool _showAssignedOnly = true;
  bool _outsideAnyGeofence = false;
  bool _loading = true;
  bool _showTasks = false;
  String _taskFilter = 'all';
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  // Real-time location streaming
  late StreamSubscription<dynamic>? _locationSubscription;
  bool _gpsConnected = false;
  double? _currentAccuracy;

  @override
  void initState() {
    super.initState();
    _loadData();
    _startRealTimeLocationTracking();
  }

  @override
  void dispose() {
    try {
      _locationSubscription?.cancel();
    } catch (_) {}
    _searchController.dispose();
    super.dispose();
  }

  /// Start real-time location tracking stream
  /// Updates map marker position with latest GPS data immediately
  void _startRealTimeLocationTracking() {
    try {
      _locationSubscription = _locationService.getPositionStream().listen(
        (position) {
          // Update UI immediately with latest position (no throttling)
          setState(() {
            _userLatLng = LatLng(position.latitude, position.longitude);
            _gpsConnected = true; // GPS is actively updating
            _currentAccuracy = position.accuracy;

            // Update geofence status in real-time
            if (_geofences.isNotEmpty) {
              _outsideAnyGeofence = !_geofences.any((g) {
                final d = Geofence.calculateDistance(
                  g.latitude,
                  g.longitude,
                  _userLatLng!.latitude,
                  _userLatLng!.longitude,
                );
                return d <= g.radius;
              });
            }
          });
        },
        onError: (e) {
          setState(() {
            _gpsConnected = false;
          });
          if (kDebugMode) print('Location stream error: $e');
        },
      );
    } catch (e) {
      setState(() {
        _gpsConnected = false;
      });
      if (kDebugMode) print('Failed to start location tracking: $e');
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
    });
    try {
      // Load current user for assigned filtering
      try {
        final profile = await _userService.getProfile();
        _userModelId = profile.id;
      } catch (_) {}

      // Fetch geofences
      final fences = await _geofenceService.fetchGeofences();
      // Get current location
      final pos = await _locationService.getCurrentLocation();
      final user = LatLng(pos.latitude, pos.longitude);

      // Persist last known lat/lng for web fallback
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setDouble('lastKnown.lat', user.latitude);
        await prefs.setDouble('lastKnown.lng', user.longitude);
      } catch (_) {}

      // Filter geofences assigned to this user
      List<Geofence> assigned = fences;
      if (_userModelId != null) {
        assigned = fences.where((g) {
          if (!g.isActive) return false;
          final employees = g.assignedEmployees ?? const [];
          return employees.any((u) => u.id == _userModelId);
        }).toList();
      } else {
        assigned = fences.where((g) => g.isActive).toList();
      }

      final List<Geofence> visible = _showAssignedOnly ? assigned : fences;
      bool outside = true;
      if (visible.isNotEmpty) {
        outside = !visible.any((g) {
          final d = Geofence.calculateDistance(
            g.latitude,
            g.longitude,
            user.latitude,
            user.longitude,
          );
          return d <= g.radius;
        });
      }

      // Fetch tasks (assigned and all), filter to tasks that have location
      List<Task> tasksAssigned = [];
      List<Task> tasksAll = [];
      try {
        if (_userModelId != null) {
          tasksAssigned = await _taskService.fetchAssignedTasks(_userModelId!);
        }
        tasksAll = await _taskService.fetchAllTasks();
      } catch (_) {}

      List<Task> withLocAssigned = tasksAssigned
          .where((t) => t.latitude != null && t.longitude != null)
          .toList();
      List<Task> withLocAll = tasksAll
          .where((t) => t.latitude != null && t.longitude != null)
          .toList();

      setState(() {
        _geofences = visible;
        _allGeofences = fences;
        _assignedGeofences = assigned;
        _tasksAssigned = withLocAssigned;
        _tasksAll = withLocAll;
        _visibleTasks = _showAssignedOnly ? withLocAssigned : withLocAll;
        _userLatLng = user;
        _outsideAnyGeofence = outside;
      });
    } catch (e) {
      // If location fails, still show geofences
      final fences = await _geofenceService.fetchGeofences();

      LatLng? fallbackUser;
      try {
        final prefs = await SharedPreferences.getInstance();
        final lastLat = prefs.getDouble('lastKnown.lat');
        final lastLng = prefs.getDouble('lastKnown.lng');
        if (lastLat != null && lastLng != null) {
          fallbackUser = LatLng(lastLat, lastLng);
        }
      } catch (_) {}

      if (fallbackUser == null && fences.isNotEmpty) {
        fallbackUser = LatLng(fences.first.latitude, fences.first.longitude);
      }

      // Filter geofences assigned to this user
      List<Geofence> assigned = fences;
      if (_userModelId != null) {
        assigned = fences.where((g) {
          if (!g.isActive) return false;
          final employees = g.assignedEmployees ?? const [];
          return employees.any((u) => u.id == _userModelId);
        }).toList();
      } else {
        assigned = fences.where((g) => g.isActive).toList();
      }

      final List<Geofence> visible = _showAssignedOnly ? assigned : fences;
      bool outside = false;
      if (fallbackUser != null) {
        final fu = fallbackUser;
        outside = !visible.any((g) {
          final d = Geofence.calculateDistance(
            g.latitude,
            g.longitude,
            fu.latitude,
            fu.longitude,
          );
          return d <= g.radius;
        });
      }

      // Even if tasks fail, safely set empty lists
      setState(() {
        _geofences = visible;
        _allGeofences = fences;
        _assignedGeofences = assigned;
        _visibleTasks = [];
        _tasksAssigned = [];
        _tasksAll = [];
        _userLatLng = fallbackUser;
        _outsideAnyGeofence = outside;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to get location: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final LatLng defaultCenter =
        _userLatLng ??
        (_geofences.isNotEmpty
            ? LatLng(_geofences.first.latitude, _geofences.first.longitude)
            : const LatLng(14.5995, 120.9842));

    return Scaffold(
      appBar: AppBar(
        title: const Text('FieldCheck Map'),
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        actions: [
          IconButton(onPressed: _loadData, icon: const Icon(Icons.refresh)),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(color: Color(0xFF2688d4)),
              child: Text(
                'FieldCheck',
                style: TextStyle(color: Colors.white, fontSize: 20),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.dashboard),
              title: const Text('Dashboard'),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.task),
              title: const Text('My Tasks'),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.map),
              title: const Text('Map'),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('Settings'),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                Positioned.fill(
                  child: FlutterMap(
                    options: MapOptions(
                      initialCenter: defaultCenter,
                      initialZoom: 15,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'field_check',
                      ),
                      if (!_showTasks && _geofences.isNotEmpty)
                        CircleLayer(
                          circles: _geofences.map((g) {
                            final center = LatLng(g.latitude, g.longitude);
                            final color = g.isActive
                                ? Colors.green
                                : Colors.grey;
                            return CircleMarker(
                              point: center,
                              color: color.withValues(alpha: 0.2),
                              borderColor: color,
                              borderStrokeWidth: 2,
                              useRadiusInMeter: true,
                              radius: g.radius,
                            );
                          }).toList(),
                        ),
                      if (_showTasks && _visibleTasks.isNotEmpty)
                        MarkerLayer(
                          markers: _visibleTasks.map((t) {
                            final point = LatLng(t.latitude!, t.longitude!);
                            final iconColor = t.status == 'completed'
                                ? Colors.green
                                : (t.status == 'in_progress'
                                      ? Colors.orange
                                      : Colors.deepPurple);
                            return Marker(
                              point: point,
                              width: 44,
                              height: 44,
                              child: GestureDetector(
                                onTap: () {
                                  showModalBottomSheet(
                                    context: context,
                                    isScrollControlled: true,
                                    builder: (_) => Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            t.title,
                                            style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(t.description),
                                          const SizedBox(height: 8),
                                          Text('Status: ${t.status}'),
                                          const SizedBox(height: 12),
                                          Row(
                                            children: [
                                              ElevatedButton.icon(
                                                onPressed: () =>
                                                    Navigator.pop(context),
                                                icon: const Icon(
                                                  Icons.directions,
                                                ),
                                                label: const Text('Navigate'),
                                              ),
                                              const SizedBox(width: 8),
                                              OutlinedButton.icon(
                                                onPressed: () =>
                                                    Navigator.pop(context),
                                                icon: const Icon(Icons.info),
                                                label: const Text('Details'),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                                child: Icon(
                                  Icons.assignment,
                                  color: iconColor,
                                  size: 36,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      if (_userLatLng != null)
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: _userLatLng!,
                              width: 44,
                              height: 44,
                              child: Icon(
                                Icons.person_pin_circle,
                                color: _outsideAnyGeofence
                                    ? Colors.red
                                    : Colors.blue,
                                size: 44,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                Positioned(
                  right: 16,
                  bottom: 120,
                  child: Column(
                    children: [
                      Tooltip(
                        message: 'Center map on your current location',
                        child: FloatingActionButton.small(
                          heroTag: 'center',
                          onPressed: () => _loadData(),
                          child: const Icon(Icons.my_location),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Tooltip(
                        message: _showTasks
                            ? 'Show geofence areas'
                            : 'Show nearby tasks',
                        child: FloatingActionButton.small(
                          heroTag: 'toggleView',
                          onPressed: () {
                            setState(() {
                              _showTasks = !_showTasks;
                            });
                          },
                          child: Icon(
                            _showTasks ? Icons.location_on : Icons.assignment,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Tooltip(
                        message: _showAssignedOnly
                            ? 'Show all geofences'
                            : 'Show assigned only',
                        child: FloatingActionButton.small(
                          heroTag: 'toggleAssigned',
                          onPressed: () {
                            setState(() {
                              _showAssignedOnly = !_showAssignedOnly;
                              if (_showTasks) {
                                _visibleTasks = _showAssignedOnly
                                    ? _tasksAssigned
                                    : _tasksAll;
                              } else {
                                _geofences = _showAssignedOnly
                                    ? (_assignedGeofences.isNotEmpty
                                          ? _assignedGeofences
                                          : _allGeofences
                                                .where((g) => g.isActive)
                                                .toList())
                                    : _allGeofences;
                              }
                            });
                          },
                          child: Icon(
                            _showAssignedOnly ? Icons.lock : Icons.public,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (!_showTasks && _outsideAnyGeofence)
                  Positioned(
                    left: 16,
                    right: 16,
                    top: 12,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red),
                      ),
                      child: Row(
                        children: const [
                          Icon(Icons.error, color: Colors.red),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'You are outside the geofence area',
                              style: TextStyle(color: Colors.red),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                // GPS Status Indicator
                Positioned(
                  left: 16,
                  right: 16,
                  top: _outsideAnyGeofence && !_showTasks ? 70 : 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: _gpsConnected
                          ? Colors.blue[50]
                          : Colors.orange[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _gpsConnected ? Colors.blue : Colors.orange,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _gpsConnected ? Icons.gps_fixed : Icons.gps_not_fixed,
                          color: _gpsConnected ? Colors.blue : Colors.orange,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _gpsConnected
                                ? 'GPS Active • Accuracy: ${_currentAccuracy?.toStringAsFixed(1) ?? '?'}m'
                                : 'GPS Connecting...',
                            style: TextStyle(
                              color: _gpsConnected
                                  ? Colors.blue
                                  : Colors.orange,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_showAssignedOnly && _assignedGeofences.isEmpty)
                  Positioned(
                    left: 16,
                    right: 16,
                    top: 60,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info, color: Colors.orange),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Not assigned to any geofence',
                              style: TextStyle(color: Colors.orange),
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (_) => AlertDialog(
                                  title: const Text('Request Assignment'),
                                  content: const Text(
                                    'Please contact your administrator to be assigned to a geofence area.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text('OK'),
                                    ),
                                  ],
                                ),
                              );
                            },
                            child: const Text('How to fix'),
                          ),
                        ],
                      ),
                    ),
                  ),
                DraggableScrollableSheet(
                  initialChildSize: 0.15,
                  minChildSize: 0.1,
                  maxChildSize: 0.45,
                  builder: (context, controller) => Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(16),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: ListView(
                      controller: controller,
                      padding: const EdgeInsets.all(16),
                      children: [
                        // Search Bar
                        TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: _showTasks ? 'Search tasks...' : 'Search geofences...',
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() {
                                        _searchQuery = '';
                                      });
                                    },
                                  )
                                : null,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                          ),
                          onChanged: (value) {
                            setState(() {
                              _searchQuery = value.toLowerCase();
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _showTasks ? 'Nearby Tasks' : 'Nearby Geofences',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Row(
                              children: [
                                ChoiceChip(
                                  selected: !_showTasks,
                                  label: const Text('Geofences'),
                                  onSelected: (_) => setState(() {
                                    _showTasks = false;
                                  }),
                                ),
                                const SizedBox(width: 8),
                                ChoiceChip(
                                  selected: _showTasks,
                                  label: const Text('Tasks'),
                                  onSelected: (_) => setState(() {
                                    _showTasks = true;
                                  }),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (_showTasks)
                          Row(
                            children: [
                              ChoiceChip(
                                selected: _taskFilter == 'all',
                                label: const Text('All'),
                                onSelected: (_) => setState(() {
                                  _taskFilter = 'all';
                                }),
                              ),
                              const SizedBox(width: 8),
                              ChoiceChip(
                                selected: _taskFilter == 'pending',
                                label: const Text('Pending'),
                                onSelected: (_) => setState(() {
                                  _taskFilter = 'pending';
                                }),
                              ),
                              const SizedBox(width: 8),
                              ChoiceChip(
                                selected: _taskFilter == 'in_progress',
                                label: const Text('In Progress'),
                                onSelected: (_) => setState(() {
                                  _taskFilter = 'in_progress';
                                }),
                              ),
                              const SizedBox(width: 8),
                              ChoiceChip(
                                selected: _taskFilter == 'completed',
                                label: const Text('Completed'),
                                onSelected: (_) => setState(() {
                                  _taskFilter = 'completed';
                                }),
                              ),
                            ],
                          ),
                        if (_showTasks) const SizedBox(height: 8),
                        if (!_showTasks)
                          ..._geofences
                              .where((g) => _searchQuery.isEmpty || g.name.toLowerCase().contains(_searchQuery))
                              .take(10)
                              .map(
                                (g) => ListTile(
                                  leading: Icon(
                                    Icons.location_on,
                                    color: g.isActive
                                        ? Colors.green
                                        : Colors.grey,
                                  ),
                                  title: Text(g.name),
                                  subtitle: Text(
                                    '${g.radius.toStringAsFixed(0)}m • ${g.type ?? 'TEAM'}${g.labelLetter != null ? ' • ${g.labelLetter}' : ''}',
                                  ),
                                  trailing: _userLatLng != null
                                      ? Text(
                                          '${Geofence.calculateDistance(g.latitude, g.longitude, _userLatLng!.latitude, _userLatLng!.longitude).round()}m',
                                        )
                                      : null,
                                ),
                              ),
                        if (_showTasks)
                          ..._visibleTasks
                              .where((t) => (_taskFilter == 'all' ? true : t.status == _taskFilter) &&
                                  (_searchQuery.isEmpty || t.title.toLowerCase().contains(_searchQuery) || t.description.toLowerCase().contains(_searchQuery)))
                              .take(10)
                              .map(
                                (t) => ListTile(
                                  leading: Icon(
                                    Icons.assignment,
                                    color: t.status == 'completed'
                                        ? Colors.green
                                        : (t.status == 'in_progress'
                                              ? Colors.orange
                                              : Colors.deepPurple),
                                  ),
                                  title: Text(t.title),
                                  subtitle: Text(t.description),
                                  trailing: Text(t.status),
                                ),
                              ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
