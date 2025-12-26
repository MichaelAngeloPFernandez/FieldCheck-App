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
import 'package:geocoding/geocoding.dart';

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
  final TextEditingController _locationSearchController =
      TextEditingController();
  bool _isSearchingLocation = false;
  List<Location> _locationSearchResults = [];
  late MapController _mapController;

  // Geofence-based filtering
  Geofence? _selectedGeofence;

  // Real-time location streaming
  late StreamSubscription<dynamic>? _locationSubscription;
  bool _gpsConnected = false;
  double? _currentAccuracy;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _loadData();
    _startRealTimeLocationTracking();
  }

  /// Get tasks for a specific geofence
  List<Task> _getTasksForGeofence(Geofence geofence) {
    if (geofence.id == null) return [];
    final source = _showAssignedOnly ? _tasksAssigned : _tasksAll;
    return source.where((t) => t.geofenceId == geofence.id).where((t) {
      if (_taskFilter == 'all') return true;
      return t.status == _taskFilter;
    }).toList();
  }

  /// Compute GEO TASKS: tasks assigned to geofences
  List<Task> _computeGeoTasks() {
    // If a specific geofence is selected, show only its tasks
    if (_selectedGeofence != null && _selectedGeofence!.id != null) {
      return _tasksAll
          .where((t) => t.geofenceId == _selectedGeofence!.id)
          .where((t) {
            if (_taskFilter == 'all') return true;
            return t.status == _taskFilter;
          })
          .toList();
    }

    // Otherwise, show all tasks that have a geofence assignment
    return _tasksAll.where((t) => t.geofenceId != null).where((t) {
      if (_taskFilter == 'all') return true;
      return t.status == _taskFilter;
    }).toList();
  }

  @override
  void dispose() {
    try {
      _locationSubscription?.cancel();
    } catch (_) {}
    _searchDebounce?.cancel();
    _searchController.dispose();
    _locationSearchController.dispose();
    super.dispose();
  }

  Timer? _searchDebounce;

  Future<void> _searchLocation(String query) async {
    // Cancel previous search if any
    _searchDebounce?.cancel();

    if (query.isEmpty) {
      setState(() {
        _locationSearchResults = [];
        _isSearchingLocation = false;
      });
      return;
    }

    // Debounce search by 500ms
    _searchDebounce = Timer(const Duration(milliseconds: 500), () async {
      setState(() {
        _isSearchingLocation = true;
      });

      try {
        final locations = await locationFromAddress(query);
        if (mounted) {
          setState(() {
            _locationSearchResults = locations;
          });
        }
      } catch (e) {
        if (kDebugMode) print('Error searching location: $e');
        if (mounted) {
          setState(() {
            _locationSearchResults = [];
          });
        }
      } finally {
        if (mounted) {
          setState(() {
            _isSearchingLocation = false;
          });
        }
      }
    });
  }

  void _onLocationSelected(Location location) {
    final latLng = LatLng(location.latitude, location.longitude);

    // Animate to the location with smooth transition
    _mapController.move(latLng, 17);

    setState(() {
      _locationSearchResults = [];
      _locationSearchController.clear();
      // Update user location to show the searched location
      _userLatLng = latLng;
    });

    // Show a snackbar confirming the location
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Location: ${location.latitude.toStringAsFixed(4)}, ${location.longitude.toStringAsFixed(4)}',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
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

            // Update GEO TASKS when tasks are visible
            if (_showTasks) {
              _visibleTasks = _computeGeoTasks();
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

      // Include tasks that have coordinates OR are assigned to a geofence
      List<Task> withLocAssigned = tasksAssigned
          .where(
            (t) =>
                !t.isArchived &&
                ((t.latitude != null && t.longitude != null) ||
                    t.geofenceId != null),
          )
          .toList();
      List<Task> withLocAll = tasksAll
          .where(
            (t) =>
                !t.isArchived &&
                ((t.latitude != null && t.longitude != null) ||
                    t.geofenceId != null),
          )
          .toList();

      setState(() {
        _geofences = visible;
        _allGeofences = fences;
        _assignedGeofences = assigned;
        _tasksAssigned = withLocAssigned;
        _tasksAll = withLocAll;
        _userLatLng = user;
        _outsideAnyGeofence = outside;
        // Always recompute visible tasks after loading
        _visibleTasks = _showTasks ? _computeGeoTasks() : [];
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
              onTap: () {
                Navigator.pop(context); // Close drawer
                // Navigate to attendance page (index 0 in dashboard)
                Navigator.of(context).pushNamedAndRemoveUntil(
                  '/dashboard',
                  (route) => false,
                  arguments: 0, // Attendance page index
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.task),
              title: const Text('My Tasks'),
              onTap: () {
                Navigator.pop(context); // Close drawer
                // Navigate to tasks page (index 5 in dashboard)
                Navigator.of(context).pushNamedAndRemoveUntil(
                  '/dashboard',
                  (route) => false,
                  arguments: 5, // Tasks page index
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.map),
              title: const Text('Map'),
              onTap: () {
                Navigator.pop(context); // Close drawer
                // Already on map - just close drawer
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('Settings'),
              onTap: () {
                Navigator.pop(context); // Close drawer
                // Navigate to settings page (index 4 in dashboard)
                Navigator.of(context).pushNamedAndRemoveUntil(
                  '/dashboard',
                  (route) => false,
                  arguments: 4, // Settings page index
                );
              },
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
                    mapController: _mapController,
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
                          circles: _geofences
                              .where(
                                (g) =>
                                    _searchQuery.isEmpty ||
                                    g.name.toLowerCase().contains(
                                      _searchQuery,
                                    ) ||
                                    g.address.toLowerCase().contains(
                                      _searchQuery,
                                    ),
                              )
                              .map((g) {
                                final center = LatLng(g.latitude, g.longitude);
                                final color = g.isActive
                                    ? Colors.green
                                    : Colors.grey;
                                return CircleMarker(
                                  point: center,
                                  color: color.withOpacity(0.2),
                                  borderColor: color,
                                  borderStrokeWidth: 2,
                                  useRadiusInMeter: true,
                                  radius: g.radius,
                                );
                              })
                              .toList(),
                        ),
                      // Task markers - only show tasks with explicit coordinates
                      if (_showTasks && _visibleTasks.isNotEmpty)
                        MarkerLayer(
                          markers: _visibleTasks
                              .where(
                                (t) =>
                                    t.latitude != null && t.longitude != null,
                              )
                              .map((t) {
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
                                  child: Icon(
                                    Icons.assignment,
                                    color: iconColor,
                                    size: 36,
                                  ),
                                );
                              })
                              .toList(),
                        ),
                      // Accuracy circle around user location
                      if (_userLatLng != null && _currentAccuracy != null)
                        CircleLayer(
                          circles: [
                            CircleMarker(
                              point: _userLatLng!,
                              color: Colors.blue.withOpacity(0.1),
                              borderColor: Colors.blue.withOpacity(0.5),
                              borderStrokeWidth: 1,
                              useRadiusInMeter: true,
                              radius: _currentAccuracy!,
                            ),
                          ],
                        ),
                      // User location marker
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
                // Search location bar with autocomplete
                Positioned(
                  top: 12,
                  left: 16,
                  right: 16,
                  child: Column(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _locationSearchController,
                                decoration: InputDecoration(
                                  hintText: 'Search location...',
                                  prefixIcon: const Icon(
                                    Icons.location_on,
                                    size: 20,
                                  ),
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 8,
                                  ),
                                  isDense: true,
                                ),
                                style: const TextStyle(fontSize: 14),
                                onChanged: _searchLocation,
                              ),
                            ),
                            if (_locationSearchController.text.isNotEmpty)
                              IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () {
                                  _locationSearchController.clear();
                                  setState(() {
                                    _locationSearchResults = [];
                                  });
                                },
                              ),
                          ],
                        ),
                      ),
                      if (_isSearchingLocation)
                        Container(
                          margin: const EdgeInsets.only(top: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          child: const SizedBox(
                            height: 30,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      if (_locationSearchResults.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(top: 8),
                          constraints: const BoxConstraints(maxHeight: 300),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.15),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: _locationSearchResults.length > 5
                                ? 5
                                : _locationSearchResults.length,
                            separatorBuilder: (context, index) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final location = _locationSearchResults[index];
                              return Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () => _onLocationSelected(location),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 12,
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.location_on,
                                          size: 20,
                                          color: Colors.blue,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                '${location.latitude.toStringAsFixed(4)}, ${location.longitude.toStringAsFixed(4)}',
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                'Tap to navigate',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.grey[600],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
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
                            : 'Show GEO TASKS',
                        child: FloatingActionButton.small(
                          heroTag: 'toggleView',
                          onPressed: () {
                            setState(() {
                              _showTasks = !_showTasks;
                              if (_showTasks) {
                                _visibleTasks = _computeGeoTasks();
                              }
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
                                _visibleTasks = _computeGeoTasks();
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
                  initialChildSize: 0.18,
                  minChildSize: 0.12,
                  maxChildSize: 0.75,
                  builder: (context, controller) => Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A3A52), // Dark blue background
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(16),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 12,
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
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: _showTasks
                                ? 'Search tasks...'
                                : 'Search geofences...',
                            hintStyle: TextStyle(color: Colors.grey[400]),
                            prefixIcon: const Icon(
                              Icons.search,
                              color: Colors.white70,
                            ),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(
                                      Icons.clear,
                                      color: Colors.white70,
                                    ),
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
                              borderSide: const BorderSide(
                                color: Colors.white24,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(
                                color: Colors.white24,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(
                                color: Color(0xFF2688d4),
                                width: 2,
                              ),
                            ),
                            filled: true,
                            fillColor: Colors.white.withOpacity(0.1),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                            ),
                          ),
                          onChanged: (value) {
                            setState(() {
                              _searchQuery = value.toLowerCase();
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _showTasks ? 'GEO TASKS' : 'Nearby Geofences',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Wrap(
                              spacing: 8,
                              children: [
                                ChoiceChip(
                                  selected: !_showTasks,
                                  label: const Text('Geofences'),
                                  onSelected: (_) => setState(() {
                                    _showTasks = false;
                                  }),
                                ),
                                ChoiceChip(
                                  selected: _showTasks,
                                  label: const Text('Tasks'),
                                  onSelected: (_) => setState(() {
                                    _showTasks = true;
                                    _visibleTasks = _computeGeoTasks();
                                  }),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (_showTasks)
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                ChoiceChip(
                                  selected: _taskFilter == 'all',
                                  label: const Text('All'),
                                  onSelected: (_) => setState(() {
                                    _taskFilter = 'all';
                                    if (_showTasks) {
                                      _visibleTasks = _computeGeoTasks();
                                    }
                                  }),
                                ),
                                const SizedBox(width: 8),
                                ChoiceChip(
                                  selected: _taskFilter == 'pending',
                                  label: const Text('Pending'),
                                  onSelected: (_) => setState(() {
                                    _taskFilter = 'pending';
                                    if (_showTasks) {
                                      _visibleTasks = _computeGeoTasks();
                                    }
                                  }),
                                ),
                                const SizedBox(width: 8),
                                ChoiceChip(
                                  selected: _taskFilter == 'in_progress',
                                  label: const Text('In Progress'),
                                  onSelected: (_) => setState(() {
                                    _taskFilter = 'in_progress';
                                    if (_showTasks) {
                                      _visibleTasks = _computeGeoTasks();
                                    }
                                  }),
                                ),
                                const SizedBox(width: 8),
                                ChoiceChip(
                                  selected: _taskFilter == 'completed',
                                  label: const Text('Completed'),
                                  onSelected: (_) => setState(() {
                                    _taskFilter = 'completed';
                                    if (_showTasks) {
                                      _visibleTasks = _computeGeoTasks();
                                    }
                                  }),
                                ),
                              ],
                            ),
                          ),
                        if (_showTasks) const SizedBox(height: 8),
                        if (!_showTasks)
                          ..._geofences
                              .where(
                                (g) =>
                                    _searchQuery.isEmpty ||
                                    g.name.toLowerCase().contains(_searchQuery),
                              )
                              .map(
                                (g) => Card(
                                  margin: const EdgeInsets.symmetric(
                                    vertical: 4,
                                  ),
                                  color: const Color(0xFF2A5A7A),
                                  child: ListTile(
                                    isThreeLine: true,
                                    selected: _selectedGeofence?.id == g.id,
                                    selectedTileColor: const Color(0xFF3A7AAA),
                                    leading: Icon(
                                      Icons.location_on,
                                      color: _selectedGeofence?.id == g.id
                                          ? Colors.lightBlue
                                          : (g.isActive
                                                ? Colors.lightGreen
                                                : Colors.grey),
                                    ),
                                    title: Text(
                                      g.name,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight:
                                            _selectedGeofence?.id == g.id
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${g.radius.toStringAsFixed(0)}m${g.labelLetter != null ? ' • ${g.labelLetter}' : ''}',
                                          style: const TextStyle(
                                            color: Colors.white70,
                                          ),
                                        ),
                                        if (_selectedGeofence?.id == g.id)
                                          Text(
                                            'Tasks: ${_getTasksForGeofence(g).length}',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.lightBlue,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                      ],
                                    ),
                                    trailing: _userLatLng != null
                                        ? Text(
                                            '${Geofence.calculateDistance(g.latitude, g.longitude, _userLatLng!.latitude, _userLatLng!.longitude).round()}m',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.white70,
                                            ),
                                          )
                                        : null,
                                    onTap: () {
                                      setState(() {
                                        if (_selectedGeofence?.id == g.id) {
                                          _selectedGeofence = null;
                                        } else {
                                          _selectedGeofence = g;
                                        }
                                        _showTasks = true;
                                        _visibleTasks = _computeGeoTasks();
                                      });
                                      // Zoom to geofence
                                      _mapController.move(
                                        LatLng(g.latitude, g.longitude),
                                        15,
                                      );
                                    },
                                  ),
                                ),
                              ),
                        if (_showTasks)
                          ..._visibleTasks
                              .where(
                                (t) =>
                                    (_taskFilter == 'all'
                                        ? true
                                        : t.status == _taskFilter) &&
                                    (_searchQuery.isEmpty ||
                                        t.title.toLowerCase().contains(
                                          _searchQuery,
                                        ) ||
                                        t.description.toLowerCase().contains(
                                          _searchQuery,
                                        )),
                              )
                              .map((t) {
                                final geofence = _allGeofences.firstWhere(
                                  (g) => g.id == t.geofenceId,
                                  orElse: () => Geofence(
                                    id: '',
                                    name: 'Unknown',
                                    address: 'Unknown',
                                    latitude: 0,
                                    longitude: 0,
                                    radius: 0,
                                    isActive: false,
                                  ),
                                );
                                return Card(
                                  margin: const EdgeInsets.symmetric(
                                    vertical: 4,
                                  ),
                                  child: ListTile(
                                    isThreeLine: true,
                                    leading: Icon(
                                      Icons.assignment,
                                      color: t.status == 'completed'
                                          ? Colors.green
                                          : (t.status == 'in_progress'
                                                ? Colors.orange
                                                : Colors.deepPurple),
                                    ),
                                    title: Text(
                                      t.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          t.description,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.location_on,
                                              size: 12,
                                              color: Colors.grey,
                                            ),
                                            const SizedBox(width: 4),
                                            Expanded(
                                              child: Text(
                                                geofence.name,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.grey,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    trailing: Chip(
                                      label: Text(
                                        t.status,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Colors.white,
                                        ),
                                      ),
                                      backgroundColor: t.status == 'completed'
                                          ? Colors.green
                                          : (t.status == 'in_progress'
                                                ? Colors.orange
                                                : Colors.deepPurple),
                                      padding: EdgeInsets.zero,
                                    ),
                                  ),
                                );
                              }),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
