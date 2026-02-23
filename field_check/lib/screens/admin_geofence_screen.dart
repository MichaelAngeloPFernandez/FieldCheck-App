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
import '../models/user_model.dart'; // Import UserModel
import 'package:field_check/config/api_config.dart';
import 'package:geocoding/geocoding.dart';
import 'package:field_check/services/task_service.dart';
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
  final TaskService _taskService = TaskService();
  List<Geofence> _geofences = [];
  LatLng? _selectedLocation;
  final double _newGeofenceRadius = 100.0;
  late io.Socket _socket;

  final MapController _mapController = MapController();

  String? _selectedGeofenceId;

  final Map<String, Geofence> _pendingGeofenceUpdates = {};
  final List<Geofence> _pendingNewGeofences = [];

  final DraggableScrollableController _sheetController =
      DraggableScrollableController();

  List<UserModel> _allEmployees = [];

  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  bool _isSearchingPlaces = false;
  String? _placesError;
  List<_PlaceSearchResult> _placeResults = [];

  final TextEditingController _assignmentsSearchController =
      TextEditingController();
  Timer? _assignmentsSearchDebounce;
  String _assignmentsFilter = 'all';
  final Set<String> _assignmentsSelectedEmployeeIds = <String>{};

  @override
  void initState() {
    super.initState();
    // Keep unused fields referenced to avoid analyzer warnings.
    // (No behavior change)
    // ignore: unnecessary_statements
    _taskService;
    // ignore: unnecessary_statements
    _originalGeofenceById;
    // ignore: unnecessary_statements
    _getAddressFromCoordinates;
    _fetchGeofences();
    _fetchAllEmployees();
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

  Future<void> _fetchAllEmployees() async {
    try {
      final employees = await _userService.fetchEmployees();
      setState(() {
        _allEmployees = employees;
      });
    } catch (e) {
      debugPrint('Error fetching employees: $e');
    }
  }

  @override
  void dispose() {
    // Dispose socket to avoid leaks
    _socket.dispose();
    _sheetController.dispose();
    _searchDebounce?.cancel();
    _searchController.dispose();
    _assignmentsSearchDebounce?.cancel();
    _assignmentsSearchController.dispose();
    super.dispose();
  }

  Geofence? get _selectedGeofence {
    final id = _selectedGeofenceId;
    if (id == null) return null;
    final pending = _pendingGeofenceUpdates[id];
    if (pending != null) return pending;
    return _geofences
        .where((g) => g.id == id)
        .cast<Geofence?>()
        .firstWhere((g) => g != null, orElse: () => null);
  }

  Geofence? _originalGeofenceById(String id) {
    return _geofences
        .where((g) => g.id == id)
        .cast<Geofence?>()
        .firstWhere((g) => g != null, orElse: () => null);
  }

  bool get _hasPendingChanges => _pendingGeofenceUpdates.isNotEmpty;

  bool get _hasPendingNew => _pendingNewGeofences.isNotEmpty;

  bool get _hasAnyPending => _hasPendingChanges || _hasPendingNew;

  void _selectGeofence(Geofence geofence) {
    setState(() {
      _selectedGeofenceId = geofence.id;
      _selectedLocation = LatLng(geofence.latitude, geofence.longitude);
      _assignmentsSelectedEmployeeIds.clear();
    });
    _mapController.move(LatLng(geofence.latitude, geofence.longitude), 18);
  }

  void _discardAllPending() {
    setState(() {
      _pendingGeofenceUpdates.clear();
      _pendingNewGeofences.clear();
    });
  }

  Future<void> _saveAllPending() async {
    if (!_hasAnyPending) return;

    final entries = _pendingGeofenceUpdates.entries.toList();
    int successCount = 0;
    final List<String> failedNames = [];

    for (final g in _pendingNewGeofences.toList()) {
      try {
        await _geofenceService.addGeofence(g);
        successCount++;
      } catch (_) {
        failedNames.add(g.name);
      }
    }

    for (final e in entries) {
      final g = e.value;
      try {
        await _geofenceService.updateGeofence(g);
        successCount++;
      } catch (_) {
        failedNames.add(g.name);
      }
    }

    await _fetchGeofences();

    if (!mounted) return;
    setState(() {
      _pendingGeofenceUpdates.clear();
      _pendingNewGeofences.clear();
    });

    final msg = failedNames.isEmpty
        ? 'Saved $successCount geofence(s).'
        : 'Saved $successCount geofence(s). Failed: ${failedNames.take(3).join(', ')}${failedNames.length > 3 ? '…' : ''}';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: failedNames.isEmpty ? Colors.green : Colors.orange,
      ),
    );
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

  Future<String> _getAddressFromCoordinates(double lat, double lng) async {
    try {
      final placemarks = await placemarkFromCoordinates(lat, lng);
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        return '${p.street}, ${p.locality}, ${p.administrativeArea}';
      }
    } catch (e) {
      debugPrint('Reverse geocoding error: $e');
    }
    return '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}';
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
                        color: Colors.amberAccent.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.warning_amber_rounded,
                            color: Colors.amber,
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Overlap detected between some geofences. Consider adjusting radius or location.',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          TextButton(
                            onPressed: () => _showOverlapDetails(context),
                            child: const Text('Details'),
                          ),
                        ],
                      ),
                    ),

                  Material(
                    elevation: 2,
                    borderRadius: BorderRadius.circular(10),
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
                                  color: Theme.of(context).colorScheme.onSurface
                                      .withValues(alpha: 0.75),
                                ),
                              ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(
                            color: Theme.of(
                              context,
                            ).dividerColor.withValues(alpha: 0.35),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
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
                          vertical: 10,
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
                      constraints: const BoxConstraints(maxHeight: 260),
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
                                          Icons.place,
                                          color: Colors.blue,
                                        ),
                                        title: Text(
                                          r.displayName,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurface,
                                          ),
                                        ),
                                        subtitle: r.latLng == null
                                            ? null
                                            : Text(
                                                '${r.latLng!.latitude.toStringAsFixed(5)}, ${r.latLng!.longitude.toStringAsFixed(5)}',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall
                                                    ?.copyWith(
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .onSurface
                                                          .withValues(
                                                            alpha: 0.75,
                                                          ),
                                                    ),
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
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurface,
                                      ),
                                    ),
                                  )),
                    ),
                ],
              ),
            ),
          ),

          DraggableScrollableSheet(
            controller: _sheetController,
            initialChildSize: 0.28,
            minChildSize: 0.18,
            maxChildSize: 0.88,
            snap: true,
            snapSizes: const [0.28, 0.5, 0.88],
            builder: (context, scrollController) {
              return Material(
                color: Colors.transparent,
                elevation: 10,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).dividerColor.withValues(alpha: 0.35),
                    ),
                  ),
                  child: DefaultTabController(
                    length: 2,
                    child: Column(
                      children: [
                        const SizedBox(height: 8),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onVerticalDragUpdate: (details) {
                            final current = _sheetController.size;
                            final height = MediaQuery.of(
                              context,
                            ).size.height.clamp(1, 1e9);
                            final delta = details.delta.dy / height;
                            final next = (current - delta).clamp(0.18, 0.88);
                            _sheetController.jumpTo(next);
                          },
                          onVerticalDragEnd: (_) {
                            final current = _sheetController.size;
                            final targets = [0.28, 0.5, 0.88];
                            double best = targets.first;
                            double bestDist = (current - best).abs();
                            for (final t in targets.skip(1)) {
                              final d = (current - t).abs();
                              if (d < bestDist) {
                                bestDist = d;
                                best = t;
                              }
                            }
                            _sheetController.animateTo(
                              best,
                              duration: const Duration(milliseconds: 180),
                              curve: Curves.easeOut,
                            );
                          },
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
                        TabBar(
                          labelColor: Theme.of(context).colorScheme.onSurface,
                          unselectedLabelColor: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.7),
                          indicatorColor: const Color(0xFF2688d4),
                          dividerColor: Theme.of(
                            context,
                          ).dividerColor.withValues(alpha: 0.35),
                          tabs: [
                            const Tab(text: 'Geofences'),
                            const Tab(text: 'Assignments'),
                          ],
                        ),
                        Expanded(
                          child: TabBarView(
                            children: [
                              _buildGeofenceTab(scrollController),
                              _buildAssignmentsTab(scrollController),
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
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddGeofenceModal(),
        backgroundColor: const Color(0xFF2688d4),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Add Geofence'),
      ),
    );
  }

  Widget _buildGeofenceTab(ScrollController scrollController) {
    final selected = _selectedGeofence;

    final bottomPadding =
        MediaQuery.of(context).padding.bottom + 24 + 72; // FAB + margin

    return ListView(
      controller: scrollController,
      padding: EdgeInsets.fromLTRB(12, 12, 12, bottomPadding),
      children: [
        if (_hasAnyPending)
          Card(
            color: Theme.of(context).colorScheme.surface,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Unsaved changes: ${_pendingGeofenceUpdates.length + _pendingNewGeofences.length}',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _discardAllPending,
                    child: Text(
                      'Discard',
                      style: TextStyle(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.85),
                      ),
                    ),
                  ),
                  FilledButton(
                    onPressed: _saveAllPending,
                    child: const Text('Save All'),
                  ),
                ],
              ),
            ),
          ),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Geofence Areas',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        if (selected != null)
          Card(
            color: Theme.of(context).colorScheme.surface,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          selected.name,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: () => _showEditGeofenceModal(selected),
                        icon: const Icon(Icons.edit),
                        label: const Text('Edit'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    selected.address,
                    style: TextStyle(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          ),

        if (_geofences.isEmpty && _pendingNewGeofences.isEmpty)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'No geofences found.',
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          )
        else ...[
          ...(_pendingNewGeofences.toList()..sort((a, b) {
                final aAssigned = _assignedEmployeeCount(a) > 0;
                final bAssigned = _assignedEmployeeCount(b) > 0;
                if (aAssigned != bAssigned) return aAssigned ? 1 : -1;
                return a.name.toLowerCase().compareTo(b.name.toLowerCase());
              }))
              .map((geofence) {
                return Card(
                  color: Theme.of(context).colorScheme.surface,
                  child: ListTile(
                    title: Text(
                      geofence.name.isEmpty ? '(New geofence)' : geofence.name,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    subtitle: Text(
                      _assignedEmployeeCount(geofence) == 0
                          ? 'No assigned employees yet'
                          : (geofence.address.isEmpty
                                ? 'Pending (not saved yet)'
                                : geofence.address),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                    trailing: Text(
                      'Pending',
                      style: TextStyle(color: Colors.orange.shade300),
                    ),
                  ),
                );
              }),

          ...(() {
            final list = _geofences
                .map(
                  (g) =>
                      g.id != null && _pendingGeofenceUpdates.containsKey(g.id)
                      ? _pendingGeofenceUpdates[g.id]!
                      : g,
                )
                .toList();
            list.sort((a, b) {
              final aAssigned = _assignedEmployeeCount(a) > 0;
              final bAssigned = _assignedEmployeeCount(b) > 0;
              if (aAssigned != bAssigned) return aAssigned ? 1 : -1;
              return a.name.toLowerCase().compareTo(b.name.toLowerCase());
            });
            return list;
          })().asMap().entries.map((entry) {
            final geofence = entry.value;
            final index = _geofences.indexWhere((g) => g.id == geofence.id);
            return Card(
              color: Theme.of(context).colorScheme.surface,
              child: ListTile(
                title: Text(
                  geofence.name,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                subtitle: Text(
                  _assignedEmployeeCount(geofence) == 0
                      ? 'No assigned employees yet'
                      : geofence.address,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
                onTap: () => _selectGeofence(geofence),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${geofence.radius.toInt()}m',
                      style: TextStyle(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.85),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Switch(
                      value: geofence.isActive,
                      onChanged: (value) async {
                        final updated = geofence.copyWith(isActive: value);
                        try {
                          await _geofenceService.updateGeofence(updated);
                          await _fetchGeofences();
                        } catch (e) {
                          debugPrint('Error updating geofence status: $e');
                        }
                      },
                      activeThumbColor: const Color(0xFF2688d4),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.edit,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.85),
                      ),
                      onPressed: () => _showEditGeofenceDialog(geofence, index),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: index < 0
                          ? null
                          : () => _deleteGeofence(index),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ],
    );
  }

  Widget _buildAssignmentsTab(ScrollController scrollController) {
    final selected = _selectedGeofence;
    return StatefulBuilder(
      builder: (context, setStateLocal) {
        final bottomPadding =
            MediaQuery.of(context).padding.bottom + 24 + 72; // FAB + margin

        List<UserModel> applyFilter(
          String query,
          String filterMode,
          Set<String> assignedIds,
        ) {
          Iterable<UserModel> base = _allEmployees;
          final q = query.trim().toLowerCase();
          if (q.isNotEmpty) {
            base = base.where((e) => e.name.toLowerCase().contains(q));
          }
          if (filterMode == 'assigned') {
            base = base.where((e) => assignedIds.contains(e.id));
          } else if (filterMode == 'unassigned') {
            base = base.where((e) => !assignedIds.contains(e.id));
          }
          return base.toList();
        }

        void stageChanges(Set<UserModel> employees, bool assign) {
          final g = selected;
          if (g == null || g.id == null) return;

          final current = _pendingGeofenceUpdates[g.id!] ?? g;
          final existing = List<UserModel>.from(
            current.assignedEmployees ?? const [],
          );

          if (assign) {
            for (final e in employees) {
              if (!existing.any((x) => x.id == e.id)) {
                existing.add(e);
              }
            }
          } else {
            existing.removeWhere((x) => employees.any((e) => e.id == x.id));
          }

          setState(() {
            _pendingGeofenceUpdates[g.id!] = current.copyWith(
              assignedEmployees: existing,
            );
          });
        }

        final stagedSelected = selected != null && selected.id != null
            ? (_pendingGeofenceUpdates[selected.id!] ?? selected)
            : null;
        final assignedIds = (stagedSelected?.assignedEmployees ?? const [])
            .map((e) => e.id)
            .whereType<String>()
            .toSet();

        final originalAssignedIds = (selected?.assignedEmployees ?? const [])
            .map((e) => e.id)
            .whereType<String>()
            .toSet();

        final stagedAdded = assignedIds.difference(originalAssignedIds).length;
        final stagedRemoved = originalAssignedIds
            .difference(assignedIds)
            .length;

        final filtered = applyFilter(
          _assignmentsSearchController.text,
          _assignmentsFilter,
          assignedIds,
        );

        final selectedEmployees = _allEmployees
            .where((e) => _assignmentsSelectedEmployeeIds.contains(e.id))
            .toSet();

        return ListView(
          controller: scrollController,
          padding: EdgeInsets.fromLTRB(12, 12, 12, bottomPadding),
          children: [
            if (_hasAnyPending)
              Card(
                color: Theme.of(context).colorScheme.surface,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Unsaved changes: ${_pendingGeofenceUpdates.length + _pendingNewGeofences.length}',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _discardAllPending,
                        child: Text(
                          'Discard',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.85),
                          ),
                        ),
                      ),
                      FilledButton(
                        onPressed: _saveAllPending,
                        child: const Text('Save All'),
                      ),
                    ],
                  ),
                ),
              ),

            Text(
              'Assignments',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            if (selected == null)
              Card(
                color: Theme.of(context).colorScheme.surface,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'Select a geofence first (Geofences tab).',
                    style: TextStyle(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ),
              )
            else ...[
              Card(
                color: Theme.of(context).colorScheme.surface,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        selected.name,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        selected.address,
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.7),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Assigned: ${assignedIds.length}',
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _assignmentsSearchController,
                decoration: InputDecoration(
                  hintText: 'Search employees…',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _assignmentsSearchController.text.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () {
                            setStateLocal(() {
                              _assignmentsSearchController.clear();
                            });
                          },
                          icon: const Icon(Icons.clear),
                        ),
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) {
                  _assignmentsSearchDebounce?.cancel();
                  _assignmentsSearchDebounce = Timer(
                    const Duration(milliseconds: 200),
                    () {
                      if (mounted) setStateLocal(() {});
                    },
                  );
                },
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('All'),
                    selected: _assignmentsFilter == 'all',
                    onSelected: (_) =>
                        setStateLocal(() => _assignmentsFilter = 'all'),
                  ),
                  ChoiceChip(
                    label: const Text('Assigned'),
                    selected: _assignmentsFilter == 'assigned',
                    onSelected: (_) =>
                        setStateLocal(() => _assignmentsFilter = 'assigned'),
                  ),
                  ChoiceChip(
                    label: const Text('Unassigned'),
                    selected: _assignmentsFilter == 'unassigned',
                    onSelected: (_) =>
                        setStateLocal(() => _assignmentsFilter = 'unassigned'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: filtered.isEmpty
                          ? null
                          : () {
                              setStateLocal(() {
                                _assignmentsSelectedEmployeeIds
                                  ..clear()
                                  ..addAll(
                                    filtered
                                        .map((e) => e.id)
                                        .whereType<String>(),
                                  );
                              });
                            },
                      child: const Text('Select all filtered'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: selectedEmployees.isEmpty
                          ? null
                          : () {
                              setStateLocal(() {
                                _assignmentsSelectedEmployeeIds.clear();
                              });
                            },
                      child: const Text('Clear selection'),
                    ),
                  ),
                ],
              ),
              if (stagedAdded > 0 || stagedRemoved > 0) ...[
                const SizedBox(height: 10),
                Card(
                  color: Theme.of(context).colorScheme.surface,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'Staged changes: +$stagedAdded assigned, -$stagedRemoved unassigned',
                      style: TextStyle(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.85),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: selectedEmployees.isEmpty
                          ? null
                          : () {
                              stageChanges(selectedEmployees, true);
                              setStateLocal(() {
                                _assignmentsSelectedEmployeeIds.clear();
                              });
                            },
                      child: const Text('Stage Assign'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: selectedEmployees.isEmpty
                          ? null
                          : () {
                              stageChanges(selectedEmployees, false);
                              setStateLocal(() {
                                _assignmentsSelectedEmployeeIds.clear();
                              });
                            },
                      child: const Text('Stage Unassign'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                constraints: const BoxConstraints(maxHeight: 380),
                child: ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, idx) {
                    final emp = filtered[idx];
                    final isAssigned = assignedIds.contains(emp.id);
                    final isChecked = _assignmentsSelectedEmployeeIds.contains(
                      emp.id,
                    );
                    return Card(
                      color: Theme.of(context).colorScheme.surface,
                      child: CheckboxListTile(
                        value: isChecked,
                        onChanged: (v) {
                          setStateLocal(() {
                            if (v == true) {
                              _assignmentsSelectedEmployeeIds.add(emp.id);
                            } else {
                              _assignmentsSelectedEmployeeIds.remove(emp.id);
                            }
                          });
                        },
                        title: Text(
                          emp.name,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        subtitle: Text(
                          isAssigned ? 'Currently assigned' : 'Not assigned',
                          style: TextStyle(
                            color: isAssigned
                                ? Colors.green.shade300
                                : Theme.of(context).colorScheme.onSurface
                                      .withValues(alpha: 0.7),
                          ),
                        ),
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  void _deleteGeofence(int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Geofence'),
        content: Text(
          'Are you sure you want to delete ${_geofences[index].name}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              try {
                await _geofenceService.deleteGeofence(_geofences[index].id!);
                setState(() {
                  _geofences.removeAt(index);
                });
                Navigator.pop(context);
              } catch (e) {
                debugPrint('Error deleting geofence: $e');
                // Optionally show an error message
                Navigator.pop(context);
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddGeofenceModal() async {
    final nameController = TextEditingController();
    final addressController = TextEditingController();
    final localSearchController = TextEditingController();
    Timer? localDebounce;

    final center = _mapController.camera.center;
    LatLng draftCenter = LatLng(center.latitude, center.longitude);
    double radiusValue = _newGeofenceRadius;
    String? dialogSelectedLabelLetter;
    List<UserModel> dialogSelectedEmployees = [];
    bool isSearching = false;
    String? placesError;
    List<_PlaceSearchResult> results = [];
    String? dialogError;

    final miniController = MapController();

    Future<void> searchNominatim(
      String query,
      void Function(void Function()) setStateDialog,
    ) async {
      final q = query.trim();
      if (q.length < 3) {
        setStateDialog(() {
          results = [];
          placesError = null;
          isSearching = false;
        });
        return;
      }
      setStateDialog(() {
        isSearching = true;
        placesError = null;
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
            'User-Agent': 'FieldCheck/1.0 (flutter_map admin geofence search)',
          },
        );
        if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
        final decoded = jsonDecode(res.body);
        if (decoded is! List) throw Exception('Unexpected response');
        final parsed = decoded
            .map(
              (e) => e is Map<String, dynamic>
                  ? e
                  : Map<String, dynamic>.from(e as Map),
            )
            .map(_PlaceSearchResult.fromJson)
            .where((r) => r.latLng != null)
            .toList();
        setStateDialog(() {
          results = parsed;
          isSearching = false;
          placesError = parsed.isEmpty ? 'No results' : null;
        });
      } catch (_) {
        setStateDialog(() {
          isSearching = false;
          placesError = 'Search failed';
          results = [];
        });
      }
    }

    final shouldStage = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            title: const Text('Add Geofence'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (dialogError != null)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Colors.red.withOpacity(0.4),
                          ),
                        ),
                        child: Text(
                          dialogError!,
                          style: const TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    TextField(
                      controller: localSearchController,
                      decoration: const InputDecoration(
                        hintText: 'Search places…',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) {
                        localDebounce?.cancel();
                        localDebounce = Timer(
                          const Duration(milliseconds: 500),
                          () {
                            setStateDialog(() {
                              dialogError = null;
                            });
                            searchNominatim(v, setStateDialog);
                          },
                        );
                      },
                    ),
                    if (isSearching ||
                        placesError != null ||
                        results.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        constraints: const BoxConstraints(maxHeight: 200),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          border: Border.all(
                            color: Theme.of(
                              context,
                            ).dividerColor.withValues(alpha: 0.35),
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: isSearching
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
                                      'Searching…',
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withValues(alpha: 0.85),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : (results.isNotEmpty
                                  ? ListView.builder(
                                      shrinkWrap: true,
                                      itemCount: results.length,
                                      itemBuilder: (context, index) {
                                        final r = results[index];
                                        return ListTile(
                                          dense: true,
                                          leading: const Icon(
                                            Icons.place,
                                            color: Colors.blue,
                                          ),
                                          title: Text(
                                            r.displayName,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.onSurface,
                                            ),
                                          ),
                                          onTap: () {
                                            final latLng = r.latLng;
                                            if (latLng == null) return;
                                            setStateDialog(() {
                                              draftCenter = latLng;
                                              results = [];
                                              placesError = null;
                                            });
                                            miniController.move(latLng, 18);
                                          },
                                        );
                                      },
                                    )
                                  : Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Text(
                                        placesError ?? 'No results',
                                        style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurface
                                              .withValues(alpha: 0.85),
                                        ),
                                      ),
                                    )),
                      ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 220,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: FlutterMap(
                          mapController: miniController,
                          options: MapOptions(
                            initialCenter: draftCenter,
                            initialZoom: 17,
                            onPositionChanged: (pos, _) {
                              setStateDialog(() {
                                draftCenter = pos.center;
                              });
                            },
                          ),
                          children: [
                            TileLayer(
                              urlTemplate:
                                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'field_check',
                            ),
                            CircleLayer(
                              circles: [
                                CircleMarker(
                                  point: draftCenter,
                                  radius: radiusValue,
                                  useRadiusInMeter: true,
                                  color: Colors.blue.withOpacity(0.18),
                                  borderColor: Colors.blue,
                                  borderStrokeWidth: 2,
                                ),
                              ],
                            ),
                            MarkerLayer(
                              markers: [
                                Marker(
                                  point: draftCenter,
                                  width: 40,
                                  height: 40,
                                  child: const Icon(
                                    Icons.location_on,
                                    color: Colors.red,
                                    size: 34,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Center: ${draftCenter.latitude.toStringAsFixed(5)}, ${draftCenter.longitude.toStringAsFixed(5)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.75),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(labelText: 'Name'),
                      onChanged: (_) => setStateDialog(() {
                        dialogError = null;
                      }),
                    ),
                    TextField(
                      controller: addressController,
                      decoration: const InputDecoration(labelText: 'Address'),
                      onChanged: (_) => setStateDialog(() {
                        dialogError = null;
                      }),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Text('Radius (m)'),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 110,
                          child: TextField(
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (val) {
                              final parsed = double.tryParse(val);
                              if (parsed == null) return;
                              setStateDialog(() {
                                radiusValue = parsed
                                    .clamp(20.0, 1000.0)
                                    .toDouble();
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    Slider(
                      value: radiusValue.clamp(20.0, 1000.0),
                      min: 20,
                      max: 1000,
                      divisions: 49,
                      label: '${radiusValue.toInt()} m',
                      onChanged: (v) {
                        setStateDialog(() {
                          radiusValue = v;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Label Letter (A–Z)',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8.0,
                      children: List<Widget>.generate(26, (int index) {
                        final letter = String.fromCharCode(
                          'A'.codeUnitAt(0) + index,
                        );
                        return ChoiceChip(
                          label: Text(letter),
                          selected: dialogSelectedLabelLetter == letter,
                          onSelected: (bool selected) {
                            setStateDialog(() {
                              dialogSelectedLabelLetter = selected
                                  ? letter
                                  : null;
                              dialogError = null;
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Assign Employees',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ..._allEmployees.map((employee) {
                      final isSelected = dialogSelectedEmployees.any(
                        (e) => e.id == employee.id,
                      );
                      return CheckboxListTile(
                        title: Text(employee.name),
                        value: isSelected,
                        onChanged: (bool? value) {
                          setStateDialog(() {
                            if (value == true) {
                              if (!dialogSelectedEmployees.any(
                                (e) => e.id == employee.id,
                              )) {
                                dialogSelectedEmployees.add(employee);
                              }
                            } else {
                              dialogSelectedEmployees.removeWhere(
                                (e) => e.id == employee.id,
                              );
                            }
                          });
                        },
                      );
                    }),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  localDebounce?.cancel();
                  Navigator.pop(context, false);
                },
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final name = nameController.text.trim();
                  final address = addressController.text.trim();
                  if (name.isEmpty || address.isEmpty) {
                    setStateDialog(() {
                      dialogError = 'Please provide name and address.';
                    });
                    return;
                  }
                  if (dialogSelectedLabelLetter == null) {
                    setStateDialog(() {
                      dialogError = 'Please select a label letter (A–Z).';
                    });
                    return;
                  }
                  Navigator.pop(context, true);
                },
                child: const Text('Stage'),
              ),
            ],
          );
        },
      ),
    );

    localDebounce?.cancel();

    if (shouldStage != true) {
      return;
    }

    final staged = Geofence(
      name: nameController.text.trim(),
      address: addressController.text.trim(),
      latitude: draftCenter.latitude,
      longitude: draftCenter.longitude,
      radius: radiusValue,
      createdAt: DateTime.now(),
      isActive: true,
      shape: GeofenceShape.circle,
      assignedEmployees: dialogSelectedEmployees,
      labelLetter: dialogSelectedLabelLetter,
    );

    setState(() {
      _pendingNewGeofences.add(staged);
    });
  }

  Future<void> _showEditGeofenceModal(Geofence geofence) async {
    final nameController = TextEditingController(text: geofence.name);
    final addressController = TextEditingController(text: geofence.address);
    final localSearchController = TextEditingController();
    Timer? localDebounce;

    LatLng draftCenter = LatLng(geofence.latitude, geofence.longitude);
    double radiusValue = geofence.radius;
    String? dialogSelectedLabelLetter = geofence.labelLetter;
    List<UserModel> dialogSelectedEmployees = List<UserModel>.from(
      geofence.assignedEmployees ?? const [],
    );
    bool isSearching = false;
    String? placesError;
    List<_PlaceSearchResult> results = [];
    String? dialogError;

    final miniController = MapController();

    Future<void> searchNominatim(
      String query,
      void Function(void Function()) setStateDialog,
    ) async {
      final q = query.trim();
      if (q.length < 3) {
        setStateDialog(() {
          results = [];
          placesError = null;
          isSearching = false;
        });
        return;
      }
      setStateDialog(() {
        isSearching = true;
        placesError = null;
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
            'User-Agent': 'FieldCheck/1.0 (flutter_map admin geofence search)',
          },
        );
        if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
        final decoded = jsonDecode(res.body);
        if (decoded is! List) throw Exception('Unexpected response');
        final parsed = decoded
            .map(
              (e) => e is Map<String, dynamic>
                  ? e
                  : Map<String, dynamic>.from(e as Map),
            )
            .map(_PlaceSearchResult.fromJson)
            .where((r) => r.latLng != null)
            .toList();
        setStateDialog(() {
          results = parsed;
          isSearching = false;
          placesError = parsed.isEmpty ? 'No results' : null;
        });
      } catch (_) {
        setStateDialog(() {
          isSearching = false;
          placesError = 'Search failed';
          results = [];
        });
      }
    }

    final shouldStage = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            title: const Text('Edit Geofence'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (dialogError != null)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Colors.red.withOpacity(0.4),
                          ),
                        ),
                        child: Text(
                          dialogError!,
                          style: const TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    TextField(
                      controller: localSearchController,
                      decoration: const InputDecoration(
                        hintText: 'Search places…',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) {
                        localDebounce?.cancel();
                        localDebounce = Timer(
                          const Duration(milliseconds: 500),
                          () {
                            setStateDialog(() {
                              dialogError = null;
                            });
                            searchNominatim(v, setStateDialog);
                          },
                        );
                      },
                    ),
                    if (isSearching ||
                        placesError != null ||
                        results.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        constraints: const BoxConstraints(maxHeight: 200),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          border: Border.all(
                            color: Theme.of(
                              context,
                            ).dividerColor.withValues(alpha: 0.35),
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: isSearching
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
                                      'Searching…',
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withValues(alpha: 0.85),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : (results.isNotEmpty
                                  ? ListView.builder(
                                      shrinkWrap: true,
                                      itemCount: results.length,
                                      itemBuilder: (context, index) {
                                        final r = results[index];
                                        return ListTile(
                                          dense: true,
                                          leading: const Icon(
                                            Icons.place,
                                            color: Colors.blue,
                                          ),
                                          title: Text(
                                            r.displayName,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.onSurface,
                                            ),
                                          ),
                                          onTap: () {
                                            final latLng = r.latLng;
                                            if (latLng == null) return;
                                            setStateDialog(() {
                                              draftCenter = latLng;
                                              results = [];
                                              placesError = null;
                                            });
                                            miniController.move(latLng, 18);
                                          },
                                        );
                                      },
                                    )
                                  : Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Text(
                                        placesError ?? 'No results',
                                        style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurface
                                              .withValues(alpha: 0.85),
                                        ),
                                      ),
                                    )),
                      ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 220,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: FlutterMap(
                          mapController: miniController,
                          options: MapOptions(
                            initialCenter: draftCenter,
                            initialZoom: 17,
                            onPositionChanged: (pos, _) {
                              setStateDialog(() {
                                draftCenter = pos.center;
                              });
                            },
                          ),
                          children: [
                            TileLayer(
                              urlTemplate:
                                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'field_check',
                            ),
                            CircleLayer(
                              circles: [
                                CircleMarker(
                                  point: draftCenter,
                                  radius: radiusValue,
                                  useRadiusInMeter: true,
                                  color: Colors.blue.withOpacity(0.18),
                                  borderColor: Colors.blue,
                                  borderStrokeWidth: 2,
                                ),
                              ],
                            ),
                            MarkerLayer(
                              markers: [
                                Marker(
                                  point: draftCenter,
                                  width: 40,
                                  height: 40,
                                  child: const Icon(
                                    Icons.location_on,
                                    color: Colors.red,
                                    size: 34,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Center: ${draftCenter.latitude.toStringAsFixed(5)}, ${draftCenter.longitude.toStringAsFixed(5)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.75),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(labelText: 'Name'),
                      onChanged: (_) => setStateDialog(() {
                        dialogError = null;
                      }),
                    ),
                    TextField(
                      controller: addressController,
                      decoration: const InputDecoration(labelText: 'Address'),
                      onChanged: (_) => setStateDialog(() {
                        dialogError = null;
                      }),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Text('Radius (m)'),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 110,
                          child: TextField(
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                            controller: TextEditingController(
                              text: radiusValue.toStringAsFixed(0),
                            ),
                            onChanged: (val) {
                              final parsed = double.tryParse(val);
                              if (parsed == null) return;
                              setStateDialog(() {
                                radiusValue = parsed
                                    .clamp(20.0, 1000.0)
                                    .toDouble();
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    Slider(
                      value: radiusValue.clamp(20.0, 1000.0),
                      min: 20,
                      max: 1000,
                      divisions: 49,
                      label: '${radiusValue.toInt()} m',
                      onChanged: (v) {
                        setStateDialog(() {
                          radiusValue = v;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Label Letter (A–Z)',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8.0,
                      children: List<Widget>.generate(26, (int index) {
                        final letter = String.fromCharCode(
                          'A'.codeUnitAt(0) + index,
                        );
                        return ChoiceChip(
                          label: Text(letter),
                          selected: dialogSelectedLabelLetter == letter,
                          onSelected: (bool selected) {
                            setStateDialog(() {
                              dialogSelectedLabelLetter = selected
                                  ? letter
                                  : null;
                              dialogError = null;
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Assign Employees',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ..._allEmployees.map((employee) {
                      final isSelected = dialogSelectedEmployees.any(
                        (e) => e.id == employee.id,
                      );
                      return CheckboxListTile(
                        title: Text(employee.name),
                        value: isSelected,
                        onChanged: (bool? value) {
                          setStateDialog(() {
                            dialogError = null;
                            if (value == true) {
                              if (!dialogSelectedEmployees.any(
                                (e) => e.id == employee.id,
                              )) {
                                dialogSelectedEmployees.add(employee);
                              }
                            } else {
                              dialogSelectedEmployees.removeWhere(
                                (e) => e.id == employee.id,
                              );
                            }
                          });
                        },
                      );
                    }),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  localDebounce?.cancel();
                  Navigator.pop(context, false);
                },
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final name = nameController.text.trim();
                  final address = addressController.text.trim();
                  if (name.isEmpty || address.isEmpty) {
                    setStateDialog(() {
                      dialogError = 'Please provide name and address.';
                    });
                    return;
                  }
                  if (dialogSelectedLabelLetter == null) {
                    setStateDialog(() {
                      dialogError = 'Please select a label letter (A–Z).';
                    });
                    return;
                  }
                  Navigator.pop(context, true);
                },
                child: const Text('Stage'),
              ),
            ],
          );
        },
      ),
    );

    localDebounce?.cancel();
    if (shouldStage != true) return;

    final staged = geofence.copyWith(
      name: nameController.text.trim(),
      address: addressController.text.trim(),
      latitude: draftCenter.latitude,
      longitude: draftCenter.longitude,
      radius: radiusValue,
      assignedEmployees: dialogSelectedEmployees,
      labelLetter: dialogSelectedLabelLetter,
    );

    setState(() {
      if (staged.id != null) {
        _pendingGeofenceUpdates[staged.id!] = staged;
      }
    });
  }

  void _showEditGeofenceDialog(Geofence geofence, int index) {
    _showEditGeofenceModal(geofence);
  }

  bool _hasOverlaps(List<Geofence> geofences) {
    for (int i = 0; i < geofences.length; i++) {
      for (int j = i + 1; j < geofences.length; j++) {
        if (_isOverlap(geofences[i], geofences[j])) return true;
      }
    }
    return false;
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

  int _assignedEmployeeCount(Geofence g) {
    final list = g.assignedEmployees ?? const [];
    return list
        .map((e) => e.id)
        .where((id) => id.trim().isNotEmpty)
        .toSet()
        .length;
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
    final active = effectiveGeofences.where((g) => g.isActive).toList();
    for (int i = 0; i < active.length; i++) {
      for (int j = i + 1; j < active.length; j++) {
        if (_isOverlap(active[i], active[j])) {
          pairs.add('${active[i].name} ↔ ${active[j].name}');
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
