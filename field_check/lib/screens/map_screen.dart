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
import 'package:geocoding/geocoding.dart';
import 'package:field_check/services/location_sync_service.dart';
import 'package:field_check/services/realtime_service.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final LocationService _locationService = LocationService();
  final GeofenceService _geofenceService = GeofenceService();
  final UserService _userService = UserService();
  final LocationSyncService _locationSyncService = LocationSyncService();
  final RealtimeService _realtimeService = RealtimeService();

  LatLng? _userLatLng;
  List<Geofence> _geofences = [];
  List<Geofence> _assignedGeofences = [];
  List<Geofence> _allGeofences = [];
  String? _userModelId;
  bool _showAssignedOnly = true;
  bool _outsideAnyGeofence = false;
  bool _loading = true;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _locationSearchController =
      TextEditingController();
  bool _isSearchingLocation = false;
  bool _showLocationSearchBar = false;
  List<Location> _locationSearchResults = [];
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();
  late MapController _mapController;

  // Real-time location streaming
  late StreamSubscription<dynamic>? _locationSubscription;
  StreamSubscription<Map<String, dynamic>>? _adminNearbySub;
  bool _gpsConnected = false;
  double? _currentAccuracy;

  String _adminNearbyMode = 'off';
  LatLng? _adminLatLng;

  Widget _buildDebugOverlay() {
    if (!kDebugMode) return const SizedBox.shrink();

    final pos = _userLatLng;
    return Positioned(
      left: 12,
      bottom: 12,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 360),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(10),
        ),
        child: DefaultTextStyle(
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 14,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'GPS: ${_gpsConnected ? 'OK' : 'WAIT'}  acc=${_currentAccuracy?.toStringAsFixed(1) ?? '-'}m',
              ),
              Text(
                'pos: ${pos == null ? '-' : '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}'}',
              ),
              const SizedBox(height: 6),
              ValueListenableBuilder<bool>(
                valueListenable: _locationSyncService.connectedListenable,
                builder: (context, connected, _) {
                  return Text(
                    'socket: ${connected ? 'CONNECTED' : 'DISCONNECTED'}',
                  );
                },
              ),
              Text('socketUrl: ${_locationSyncService.socketUrl}'),
              ValueListenableBuilder<DateTime?>(
                valueListenable: _locationSyncService.lastSharedListenable,
                builder: (context, value, _) {
                  final text = value == null
                      ? 'lastShared: never'
                      : 'lastShared: ${value.toIso8601String()}';
                  return Text(text);
                },
              ),
              ValueListenableBuilder<String?>(
                valueListenable: _locationSyncService.lastErrorListenable,
                builder: (context, value, _) {
                  if (value == null || value.trim().isEmpty) {
                    return const Text('error: -');
                  }
                  return Text('error: $value');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(
    String title, {
    String? subtitle,
    Widget? trailing,
  }) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing,
      ],
    );
  }

  Widget _buildSurfaceCard({
    required Widget child,
    EdgeInsetsGeometry? padding,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildStatusPill({
    required String label,
    required Color color,
    IconData? icon,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBanner({
    required IconData icon,
    required String message,
    required Color background,
    required Color foreground,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: background),
      ),
      child: Row(
        children: [
          Icon(icon, color: foreground, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: foreground, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStateCard({
    required IconData icon,
    required String title,
    required String message,
  }) {
    final theme = Theme.of(context);
    return _buildSurfaceCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: theme.colorScheme.primary),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _loadData();
    _startRealTimeLocationTracking();
    _initAdminNearby();
  }

  Future<void> _initAdminNearby() async {
    await _realtimeService.initialize();
    _adminNearbySub?.cancel();
    _adminNearbySub = _realtimeService.adminNearbyStream.listen((data) {
      final mode = (data['mode'] ?? 'off').toString();
      final lat = data['latitude'];
      final lng = data['longitude'];
      final nextLat = lat is num ? lat.toDouble() : null;
      final nextLng = lng is num ? lng.toDouble() : null;

      if (!mounted) return;
      setState(() {
        _adminNearbyMode = mode;
        _adminLatLng = (mode != 'off' && nextLat != null && nextLng != null)
            ? LatLng(nextLat, nextLng)
            : null;
      });
    });
  }

  @override
  void dispose() {
    try {
      _locationSubscription?.cancel();
    } catch (_) {}
    _adminNearbySub?.cancel();
    _searchDebounce?.cancel();
    _searchController.dispose();
    _locationSearchController.dispose();
    _sheetController.dispose();
    super.dispose();
  }

  Timer? _searchDebounce;

  Future<void> _performLocationSearch(String query) async {
    if (query.isEmpty) {
      if (!mounted) return;
      setState(() {
        _locationSearchResults = [];
        _isSearchingLocation = false;
      });
      return;
    }

    if (!mounted) return;
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
  }

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
    _searchDebounce = Timer(const Duration(milliseconds: 500), () {
      _performLocationSearch(query);
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

  void _fitToVisibleBounds() {
    LatLngBounds? bounds;
    void extendBounds(LatLng point) {
      if (bounds == null) {
        bounds = LatLngBounds(point, point);
      } else {
        bounds!.extend(point);
      }
    }

    for (final geofence in _geofences) {
      extendBounds(LatLng(geofence.latitude, geofence.longitude));
    }

    if (_userLatLng != null) {
      extendBounds(_userLatLng!);
    }

    if (bounds == null) return;
    try {
      _mapController.fitCamera(
        CameraFit.bounds(bounds: bounds!, padding: const EdgeInsets.all(48)),
      );
    } catch (_) {
      _mapController.move(bounds!.center, 14);
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

      setState(() {
        _geofences = visible;
        _allGeofences = fences;
        _assignedGeofences = assigned;
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

      setState(() {
        _geofences = visible;
        _allGeofences = fences;
        _assignedGeofences = assigned;
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

    final minSheetSize = kIsWeb ? 0.10 : 0.02;
    final initialSheetSize = kIsWeb ? 0.22 : 0.18;
    final midSheetSize = kIsWeb ? 0.45 : 0.4;
    final maxSheetSize = kIsWeb ? 0.90 : 0.98;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'FieldCheck Map',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh map data',
            onPressed: _loadData,
            icon: const Icon(Icons.refresh),
          ),
        ],
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
                      initialZoom: 13.0,
                      maxZoom: 18.0,
                      minZoom: 3.0,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                        subdomains: const ['a', 'b', 'c'],
                      ),
                      if (_geofences.isNotEmpty)
                        CircleLayer(
                          circles: _geofences.map((g) {
                            final center = LatLng(g.latitude, g.longitude);
                            final color = g.isActive
                                ? Colors.green
                                : Theme.of(context).colorScheme.onSurface
                                      .withValues(alpha: 0.55);
                            return CircleMarker(
                              point: center,
                              color: color.withOpacity(0.2),
                              borderColor: color,
                              borderStrokeWidth: 2,
                              useRadiusInMeter: true,
                              radius: g.radius,
                            );
                          }).toList(),
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
                      if (_adminNearbyMode != 'off' && _adminLatLng != null)
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: _adminLatLng!,
                              width: 46,
                              height: 46,
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.deepPurple,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.deepPurple.withValues(
                                        alpha: 0.35,
                                      ),
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
                          ],
                        ),
                    ],
                  ),
                ),
                _buildDebugOverlay(),
                // Search location bar with autocomplete
                // Positioned below the status banners to avoid overlap on web.
                if (_showLocationSearchBar)
                  Positioned(
                    top: 140,
                    left: 16,
                    right: 16,
                    child: Column(
                      children: [
                        _buildSurfaceCard(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _locationSearchController,
                                  decoration: InputDecoration(
                                    hintText: 'Search map location...',
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
                                  style: Theme.of(
                                    context,
                                  ).textTheme.bodySmall?.copyWith(fontSize: 14),
                                  onChanged: _searchLocation,
                                  textInputAction: TextInputAction.search,
                                  onSubmitted: (value) {
                                    _searchDebounce?.cancel();
                                    _performLocationSearch(value.trim());
                                  },
                                ),
                              ),
                              IconButton(
                                tooltip: 'Search',
                                icon: const Icon(Icons.search, size: 18),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () {
                                  final query = _locationSearchController.text
                                      .trim();
                                  _searchDebounce?.cancel();
                                  _performLocationSearch(query);
                                },
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
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: _buildSurfaceCard(
                              padding: const EdgeInsets.all(12),
                              child: const SizedBox(
                                height: 30,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                          ),
                        if (_locationSearchResults.isNotEmpty)
                          Container(
                            margin: const EdgeInsets.only(top: 8),
                            constraints: const BoxConstraints(maxHeight: 300),
                            child: _buildSurfaceCard(
                              padding: EdgeInsets.zero,
                              child: ListView.separated(
                                shrinkWrap: true,
                                itemCount: _locationSearchResults.length > 5
                                    ? 5
                                    : _locationSearchResults.length,
                                separatorBuilder: (context, index) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final location =
                                      _locationSearchResults[index];
                                  return Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () =>
                                          _onLocationSelected(location),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 12,
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.location_on,
                                              size: 20,
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.primary,
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
                                                      fontWeight:
                                                          FontWeight.w500,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    'Tap to navigate',
                                                    style: TextStyle(
                                                      fontSize: 13,
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .onSurface
                                                          .withValues(
                                                            alpha: 0.7,
                                                          ),
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
                        message: 'Fit map to visible items',
                        child: FloatingActionButton.small(
                          heroTag: 'fitView',
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.surface,
                          foregroundColor: Theme.of(
                            context,
                          ).colorScheme.primary,
                          onPressed: _fitToVisibleBounds,
                          child: const Icon(Icons.center_focus_strong),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Tooltip(
                        message: 'Search map location',
                        child: FloatingActionButton.small(
                          heroTag: 'mapSearch',
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.surface,
                          foregroundColor: Theme.of(
                            context,
                          ).colorScheme.primary,
                          onPressed: () {
                            setState(() {
                              _showLocationSearchBar = !_showLocationSearchBar;
                              if (!_showLocationSearchBar) {
                                _locationSearchController.clear();
                                _locationSearchResults = [];
                              }
                            });
                          },
                          child: Icon(
                            _showLocationSearchBar ? Icons.close : Icons.search,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Tooltip(
                        message: 'Center map on your current location',
                        child: FloatingActionButton.small(
                          heroTag: 'center',
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.surface,
                          foregroundColor: Theme.of(
                            context,
                          ).colorScheme.primary,
                          onPressed: () => _loadData(),
                          child: const Icon(Icons.my_location),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Tooltip(
                        message: _showAssignedOnly
                            ? 'Show all geofences'
                            : 'Show assigned only',
                        child: FloatingActionButton.small(
                          heroTag: 'toggleAssigned',
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.surface,
                          foregroundColor: Theme.of(
                            context,
                          ).colorScheme.primary,
                          onPressed: () {
                            setState(() {
                              _showAssignedOnly = !_showAssignedOnly;
                              _geofences = _showAssignedOnly
                                  ? _assignedGeofences
                                  : _allGeofences;
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
                // GPS Status Indicator and status banners
                Positioned(
                  left: 16,
                  right: 16,
                  top: 12,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_outsideAnyGeofence)
                        _buildStatusBanner(
                          icon: Icons.error,
                          message: 'You are outside the geofence area',
                          background: Theme.of(context).colorScheme.error,
                          foreground: Theme.of(context).colorScheme.onError,
                        ),
                      if (_outsideAnyGeofence) const SizedBox(height: 8),
                      _buildStatusBanner(
                        icon: _gpsConnected
                            ? Icons.gps_fixed
                            : Icons.gps_not_fixed,
                        message: _gpsConnected
                            ? 'GPS Active • Accuracy: ${_currentAccuracy?.toStringAsFixed(1) ?? '?'}m'
                            : 'GPS Connecting...',
                        background: _gpsConnected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.tertiary,
                        foreground: _gpsConnected
                            ? Theme.of(context).colorScheme.onPrimary
                            : Theme.of(context).colorScheme.onTertiary,
                      ),
                      if (_showAssignedOnly && _assignedGeofences.isEmpty)
                        const SizedBox(height: 8),
                      _buildSurfaceCard(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.location_on,
                              size: 16,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'View: Geofences',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: 0.8),
                                    ),
                              ),
                            ),
                            _buildStatusPill(
                              label: '${_geofences.length} shown',
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ],
                        ),
                      ),
                      if (_showAssignedOnly && _assignedGeofences.isEmpty)
                        _buildSurfaceCard(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Icon(Icons.info, color: Colors.orange.shade700),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Not assigned to any geofence',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: Colors.orange.shade700,
                                        fontWeight: FontWeight.w600,
                                      ),
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
                                          onPressed: () =>
                                              Navigator.pop(context),
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
                    ],
                  ),
                ),
                DraggableScrollableSheet(
                  controller: _sheetController,
                  initialChildSize: initialSheetSize,
                  minChildSize: minSheetSize,
                  maxChildSize: maxSheetSize,
                  snap: true,
                  snapSizes: [minSheetSize, midSheetSize, maxSheetSize],
                  builder: (context, controller) => Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(20),
                      ),
                      border: Border.all(
                        color: Theme.of(
                          context,
                        ).dividerColor.withValues(alpha: 0.35),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.2),
                          blurRadius: 16,
                          offset: const Offset(0, -4),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: 8),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          child: Center(
                            child: Container(
                              width: 44,
                              height: 5,
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.35),
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Expanded(
                          child: ListView(
                            controller: controller,
                            padding: const EdgeInsets.all(16),
                            children: [
                              // Search Bar
                              _buildSurfaceCard(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                child: TextField(
                                  controller: _searchController,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurface,
                                      ),
                                  decoration: InputDecoration(
                                    hintText: 'Search geofences...',
                                    hintStyle: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: 0.6),
                                    ),
                                    prefixIcon: Icon(
                                      Icons.search,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: 0.7),
                                    ),
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
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                        color: Theme.of(
                                          context,
                                        ).dividerColor.withValues(alpha: 0.35),
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                        color: Theme.of(
                                          context,
                                        ).dividerColor.withValues(alpha: 0.35),
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                        width: 2,
                                      ),
                                    ),
                                    filled: true,
                                    fillColor: Theme.of(
                                      context,
                                    ).colorScheme.surface,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                  ),
                                  onChanged: (value) {
                                    setState(() {
                                      _searchQuery = value.toLowerCase();
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(height: 16),
                              _buildSectionHeader(
                                'Nearby Geofences',
                                subtitle:
                                    'Tap a geofence to focus the map view.',
                              ),
                              const SizedBox(height: 12),
                              if (_geofences.isNotEmpty)
                                ..._geofences
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
                                      return Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 6,
                                        ),
                                        child: _buildSurfaceCard(
                                          padding: EdgeInsets.zero,
                                          child: ListTile(
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                  horizontal: 12,
                                                  vertical: 8,
                                                ),
                                            title: Text(
                                              g.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            subtitle: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                const SizedBox(height: 2),
                                                Text(
                                                  g.address,
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodyMedium
                                                      ?.copyWith(
                                                        color: Theme.of(context)
                                                            .colorScheme
                                                            .onSurface
                                                            .withValues(
                                                              alpha: 0.75,
                                                            ),
                                                      ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  'Radius: ${g.radius.toStringAsFixed(0)} m',
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodyMedium
                                                      ?.copyWith(
                                                        color: Theme.of(context)
                                                            .colorScheme
                                                            .onSurface
                                                            .withValues(
                                                              alpha: 0.75,
                                                            ),
                                                      ),
                                                ),
                                              ],
                                            ),
                                            trailing: _buildStatusPill(
                                              label: g.isActive
                                                  ? 'ACTIVE'
                                                  : 'OFF',
                                              color: g.isActive
                                                  ? Colors.green
                                                  : Theme.of(
                                                      context,
                                                    ).colorScheme.tertiary,
                                              icon: g.isActive
                                                  ? Icons.check_circle
                                                  : Icons.pause_circle,
                                            ),
                                            onTap: () {
                                              _mapController.move(
                                                LatLng(g.latitude, g.longitude),
                                                17,
                                              );
                                            },
                                          ),
                                        ),
                                      );
                                    }),
                              const SizedBox(height: 16),
                              if (_geofences.isEmpty)
                                _buildStateCard(
                                  icon: Icons.location_off,
                                  title: 'No geofences available',
                                  message:
                                      'No geofences are assigned or visible at the moment.',
                                ),
                              const SizedBox(height: 24),
                            ],
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
