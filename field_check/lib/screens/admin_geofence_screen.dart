// ignore_for_file: use_build_context_synchronously, library_prefixes, deprecated_member_use
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import '../widgets/custom_map.dart';
import '../models/geofence_model.dart';
import '../services/geofence_service.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../services/user_service.dart'; // Import UserService
import 'package:field_check/config/api_config.dart';
import 'package:http/http.dart' as http;

class AdminGeofenceScreen extends StatefulWidget {
  const AdminGeofenceScreen({super.key});

  @override
  State<AdminGeofenceScreen> createState() => _AdminGeofenceScreenState();
}

class _PlaceSearchResult {
  final String displayName;
  final LatLng? latLng;

  _PlaceSearchResult({required this.displayName, required this.latLng});

  factory _PlaceSearchResult.fromJson(Map<String, dynamic> json) {
    final lat = double.tryParse(json['lat']?.toString() ?? '');
    final lon = double.tryParse(json['lon']?.toString() ?? '');
    return _PlaceSearchResult(
      displayName: json['display_name']?.toString() ?? 'Unknown place',
      latLng: (lat != null && lon != null) ? LatLng(lat, lon) : null,
    );
  }
}

class _AdminGeofenceScreenState extends State<AdminGeofenceScreen> {
  final GeofenceService _geofenceService = GeofenceService();
  final UserService _userService = UserService();
  List<Geofence> _geofences = [];
  LatLng? _selectedLocation;
  late io.Socket _socket;

  final MapController _mapController = MapController();

  final Map<String, Geofence> _pendingGeofenceUpdates = {};
  final List<Geofence> _pendingNewGeofences = [];

  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  bool _isSearchingPlaces = false;
  String? _placesError;
  List<_PlaceSearchResult> _placeResults = [];
  bool _isSearchExpanded = false;

  @override
  void initState() {
    super.initState();
    _fetchGeofences();
    _initSocket();
  }

  Future<void> _initSocket() async {
    final token = await _userService.getToken();
    final options = io.OptionBuilder()
        .setTransports(['websocket'])
        .enableAutoConnect()
        .setTimeout(20000)
        .setExtraHeaders({if (token != null) 'Authorization': 'Bearer $token'})
        .build();

    // Inject reconnection options supported by socket_io_client
    options['reconnection'] = true;
    options['reconnectionAttempts'] = 999999;
    options['reconnectionDelay'] = 500;
    options['reconnectionDelayMax'] = 10000;

    _socket = io.io(ApiConfig.baseUrl, options);

    _socket.onConnect((_) => debugPrint('Geofence socket connected'));
    _socket.onDisconnect((_) => debugPrint('Geofence socket disconnected'));
    _socket.on(
      'reconnect_attempt',
      (_) => debugPrint('Geofence socket reconnect attempt'),
    );
    _socket.on('reconnect', (_) => debugPrint('Geofence socket reconnected'));
    _socket.on(
      'reconnect_error',
      (err) => debugPrint('Geofence socket reconnect error: $err'),
    );
    _socket.on(
      'reconnect_failed',
      (_) => debugPrint('Geofence socket reconnect failed'),
    );

    // Trigger refresh on geofence-related events
    void refresh(dynamic _) => _fetchGeofences();
    _socket.on('geofenceCreated', refresh);
    _socket.on('geofenceUpdated', refresh);
    _socket.on('geofenceDeleted', refresh);
  }

  @override
  void dispose() {
    // Dispose socket to avoid leaks
    _socket.dispose();
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchGeofences() async {
    try {
      final fetchedGeofences = await _geofenceService.fetchGeofences();
      setState(() {
        _geofences = fetchedGeofences;
      });
    } catch (e) {
      debugPrint('Error fetching geofences in AdminGeofenceScreen: $e');
      // Optionally show an error message to the user
    }
  }

  Future<void> _searchPlacesNominatim(String query) async {
    final q = query.trim();
    if (q.length < 3) {
      setState(() {
        _placeResults = [];
        _placesError = null;
        _isSearchingPlaces = false;
      });
      return;
    }

    setState(() {
      _isSearchingPlaces = true;
      _placesError = null;
    });

    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': q,
        'format': 'json',
        'addressdetails': '1',
        'limit': '8',
      });
      final res = await http.get(
        uri,
        headers: {
          'Accept': 'application/json',
          // Nominatim requires a User-Agent identifying the application.
          'User-Agent': 'FieldCheck/1.0 (flutter_map admin geofence search)',
        },
      );

      if (res.statusCode != 200) {
        throw Exception('HTTP ${res.statusCode}');
      }

      final decoded = jsonDecode(res.body);
      if (decoded is! List) {
        throw Exception('Unexpected response');
      }

      final results = decoded
          .map(
            (e) => e is Map<String, dynamic>
                ? e
                : Map<String, dynamic>.from(e as Map),
          )
          .map(_PlaceSearchResult.fromJson)
          .where((r) => r.latLng != null)
          .toList();

      if (!mounted) return;
      setState(() {
        _placeResults = results;
        _isSearchingPlaces = false;
        _placesError = results.isEmpty ? 'No results' : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSearchingPlaces = false;
        _placesError = 'Search failed';
        _placeResults = [];
      });
    }
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 500), () {
      _searchPlacesNominatim(value);
    });
  }

  void _toggleSearchExpanded() {
    setState(() {
      _isSearchExpanded = !_isSearchExpanded;
      if (!_isSearchExpanded) {
        _searchController.clear();
        _placeResults = [];
        _placesError = null;
        _isSearchingPlaces = false;
      }
    });
  }

  void _selectPlaceResult(_PlaceSearchResult result) {
    final latLng = result.latLng;
    if (latLng == null) return;

    setState(() {
      _selectedLocation = latLng;
      _placeResults = [];
      _placesError = null;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('📍 Map moved to: ${result.displayName}'),
        duration: const Duration(seconds: 2),
        backgroundColor: Colors.blue,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final effectiveGeofences = _pendingGeofenceUpdates.isEmpty
        ? [..._geofences, ..._pendingNewGeofences]
        : [
            ...(_geofences
                .map(
                  (g) =>
                      g.id != null && _pendingGeofenceUpdates.containsKey(g.id)
                      ? _pendingGeofenceUpdates[g.id]!
                      : g,
                )
                .toList()),
            ..._pendingNewGeofences,
          ];

    return Scaffold(
      body: Stack(
        children: [
          CustomMap(
            height: double.infinity,
            geofences: effectiveGeofences,
            mapController: _mapController,
            overlayTopOffset: _hasOverlaps(effectiveGeofences) ? 64 : 12,
            currentLocation: _selectedLocation != null
                ? UserLocation.fromLatLng(_selectedLocation!)
                : null,
            isEditable: false,
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_hasOverlaps(effectiveGeofences))
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.secondaryContainer
                            .withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Theme.of(context)
                              .colorScheme
                              .onSecondaryContainer
                              .withValues(alpha: 0.25),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSecondaryContainer,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Overlap detected between some geofences. Consider adjusting radius or location.',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSecondaryContainer,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () => _showOverlapDetails(context),
                            style: TextButton.styleFrom(
                              foregroundColor: Theme.of(
                                context,
                              ).colorScheme.onSecondaryContainer,
                              textStyle: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            child: const Text('Details'),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),

          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Align(
                      alignment: Alignment.bottomRight,
                      child: Material(
                        color: Theme.of(context).colorScheme.surface,
                        elevation: 6,
                        borderRadius: BorderRadius.circular(999),
                        child: IconButton(
                          tooltip: _isSearchExpanded
                              ? 'Collapse search'
                              : 'Search',
                          onPressed: _toggleSearchExpanded,
                          icon: Icon(
                            Icons.search,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ),
                    if (_isSearchExpanded) ...[
                      const SizedBox(height: 8),
                      Material(
                        elevation: 6,
                        borderRadius: BorderRadius.circular(12),
                        child: TextField(
                          controller: _searchController,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                          cursorColor: Theme.of(context).colorScheme.onSurface,
                          decoration: InputDecoration(
                            hintText: 'Search places (e.g., "Makati", "Ayala")',
                            hintStyle: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withValues(alpha: 0.6),
                            ),
                            prefixIcon: Icon(
                              Icons.search,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withValues(alpha: 0.75),
                            ),
                            suffixIcon: _searchController.text.isEmpty
                                ? null
                                : IconButton(
                                    onPressed: () {
                                      setState(() {
                                        _searchController.clear();
                                        _placeResults = [];
                                        _placesError = null;
                                      });
                                    },
                                    icon: Icon(
                                      Icons.clear,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: 0.75),
                                    ),
                                  ),
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
                            filled: true,
                            fillColor: Theme.of(context).colorScheme.surface,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                          ),
                          onChanged: _onSearchChanged,
                        ),
                      ),
                      if (_isSearchingPlaces ||
                          _placesError != null ||
                          _placeResults.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(top: 8),
                          width: double.infinity,
                          constraints: const BoxConstraints(maxHeight: 240),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Theme.of(
                                context,
                              ).dividerColor.withValues(alpha: 0.35),
                            ),
                          ),
                          child: _isSearchingPlaces
                              ? Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    children: [
                                      const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        'Searching...',
                                        style: TextStyle(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurface,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : (_placeResults.isNotEmpty
                                    ? ListView.builder(
                                        shrinkWrap: true,
                                        itemCount: _placeResults.length,
                                        itemBuilder: (context, index) {
                                          final r = _placeResults[index];
                                          return ListTile(
                                            dense: true,
                                            leading: const Icon(
                                              Icons.location_on,
                                              color: Colors.blue,
                                            ),
                                            title: Text(
                                              r.displayName,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            onTap: () => _selectPlaceResult(r),
                                          );
                                        },
                                      )
                                    : Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: Text(
                                          _placesError ?? 'No results',
                                          style: TextStyle(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurface
                                                .withValues(alpha: 0.75),
                                          ),
                                        ),
                                      )),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _isOverlap(Geofence a, Geofence b) {
    final d = Geofence.calculateDistance(
      a.latitude,
      a.longitude,
      b.latitude,
      b.longitude,
    );
    const toleranceMeters = 1.0;
    return d < (a.radius + b.radius - toleranceMeters);
  }

  bool _hasOverlaps(List<Geofence> geofences) {
    for (int i = 0; i < geofences.length; i++) {
      for (int j = i + 1; j < geofences.length; j++) {
        if (_isOverlap(geofences[i], geofences[j])) return true;
      }
    }
    return false;
  }

  void _showOverlapDetails(BuildContext context) {
    final List<String> pairs = [];
    final effectiveGeofences = _pendingGeofenceUpdates.isEmpty
        ? [..._geofences, ..._pendingNewGeofences]
        : [
            ...(_geofences
                .map(
                  (g) =>
                      g.id != null && _pendingGeofenceUpdates.containsKey(g.id)
                      ? _pendingGeofenceUpdates[g.id]!
                      : g,
                )
                .toList()),
            ..._pendingNewGeofences,
          ];
    for (int i = 0; i < effectiveGeofences.length; i++) {
      for (int j = i + 1; j < effectiveGeofences.length; j++) {
        final a = effectiveGeofences[i];
        final b = effectiveGeofences[j];
        if (_isOverlap(a, b)) {
          final d = Geofence.calculateDistance(
            a.latitude,
            a.longitude,
            b.latitude,
            b.longitude,
          );
          pairs.add(
            '${a.name} ↔ ${b.name} (d=${d.toStringAsFixed(0)}m, r=${(a.radius + b.radius).toStringAsFixed(0)}m)',
          );
        }
      }
    }
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Overlapping Geofences'),
        content: pairs.isEmpty
            ? const Text('No overlaps found.')
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: pairs.map((p) => Text('• $p')).toList(),
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
