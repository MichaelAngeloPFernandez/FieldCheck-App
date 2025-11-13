// ignore_for_file: use_build_context_synchronously, deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
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

  @override
  void initState() {
    super.initState();
    _loadData();
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to get location: $e')),
      );
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
    final LatLng defaultCenter = _userLatLng ??
        (_geofences.isNotEmpty
            ? LatLng(_geofences.first.latitude, _geofences.first.longitude)
            : const LatLng(14.5995, 120.9842)); // Default to Manila if nothing

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Map',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else ...[
            // Toggle between view types and assigned/all filter
            Row(
              children: [
                ChoiceChip(
                  selected: !_showTasks,
                  label: const Text('Geofences'),
                  onSelected: (_) {
                    setState(() {
                      _showTasks = false;
                    });
                  },
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  selected: _showTasks,
                  label: const Text('Tasks'),
                  onSelected: (_) {
                    setState(() {
                      _showTasks = true;
                    });
                  },
                ),
                const SizedBox(width: 16),
                ChoiceChip(
                  selected: _showAssignedOnly,
                  label: const Text('Assigned'),
                  onSelected: (_) {
                    setState(() {
                      _showAssignedOnly = true;
                      if (_showTasks) {
                        _visibleTasks = _tasksAssigned;
                      } else {
                        _geofences = _assignedGeofences.isNotEmpty
                            ? _assignedGeofences
                            : _allGeofences.where((g) => g.isActive).toList();
                        if (_userLatLng != null) {
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
                      }
                    });
                  },
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  selected: !_showAssignedOnly,
                  label: const Text('All'),
                  onSelected: (_) {
                    setState(() {
                      _showAssignedOnly = false;
                      if (_showTasks) {
                        _visibleTasks = _tasksAll;
                      } else {
                        _geofences = _allGeofences;
                        if (_userLatLng != null) {
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
                      }
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (!_showTasks && _outsideAnyGeofence)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  border: Border.all(color: Colors.red),
                  borderRadius: BorderRadius.circular(8),
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
            const SizedBox(height: 8),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
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
                          final LatLng center = LatLng(g.latitude, g.longitude);
                          final Color color = g.isActive ? Colors.green : Colors.grey;
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
                          final LatLng point = LatLng(t.latitude!, t.longitude!);
                          return Marker(
                            point: point,
                            width: 40,
                            height: 40,
                            child: GestureDetector(
                              onTap: () {
                                showDialog(
                                  context: context,
                                  builder: (_) => AlertDialog(
                                    title: Text(t.title),
                                    content: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(t.description),
                                        const SizedBox(height: 8),
                                        Text('Status: ${t.status}'),
                                        const SizedBox(height: 8),
                                        if (t.address != null && t.address!.isNotEmpty)
                                          Text('Address: ${t.address}'),
                                      ],
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.of(context).pop(),
                                        child: const Text('Close'),
                                      ),
                                    ],
                                  ),
                                );
                              },
                              child: const Icon(
                                Icons.assignment,
                                color: Colors.deepPurple,
                                size: 32,
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
                            width: 40,
                            height: 40,
                            child: Icon(
                              Icons.person_pin_circle,
                              color: _outsideAnyGeofence ? Colors.red : Colors.blue,
                              size: 40,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  onPressed: _loadData,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh'),
                ),
                if (_userLatLng != null)
                  Text(
                    'Lat: ${_userLatLng!.latitude.toStringAsFixed(6)}, Lng: ${_userLatLng!.longitude.toStringAsFixed(6)}',
                    style: const TextStyle(color: Colors.grey),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}