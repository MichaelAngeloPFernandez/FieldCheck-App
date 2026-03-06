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
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();

  String? _selectedGeofenceId;
  List<UserModel> _allEmployees = [];
  final TextEditingController _assignmentsSearchController =
      TextEditingController();
  Timer? _assignmentsSearchDebounce;
  String _assignmentsFilter = 'all';

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
    _fetchAllEmployees();
    _initSocket();
  }

  Future<void> _fetchAllEmployees() async {
    try {
      final employees = await _userService.fetchEmployees();
      if (!mounted) return;
      setState(() {
        _allEmployees = employees;
      });
    } catch (e) {
      debugPrint('Error fetching employees: $e');
    }
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
    for (final g in _geofences) {
      if (g.id == id) return g;
    }
    return null;
  }

  bool get _hasAnyPending =>
      _pendingGeofenceUpdates.isNotEmpty || _pendingNewGeofences.isNotEmpty;

  void _selectGeofence(Geofence geofence) {
    setState(() {
      _selectedGeofenceId = geofence.id;
      _selectedLocation = LatLng(geofence.latitude, geofence.longitude);
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

  Widget _buildSheetHandle() {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
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
    );
  }

  Widget _buildGeofenceRow(Geofence g) {
    return ListTile(
      dense: true,
      title: Text(g.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        'r=${g.radius.toStringAsFixed(0)}m',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Icon(
        Icons.chevron_right,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
      ),
      onTap: () {
        _selectGeofence(g);
        _mapController.move(LatLng(g.latitude, g.longitude), 16);
      },
    );
  }

  Widget _buildSearchToggleButton() {
    return Align(
      alignment: Alignment.centerRight,
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        elevation: 0,
        borderRadius: BorderRadius.circular(999),
        child: IconButton(
          tooltip: _isSearchExpanded ? 'Collapse search' : 'Search',
          onPressed: _toggleSearchExpanded,
          icon: Icon(
            Icons.search,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
    );
  }

  Widget _buildSearchPanel() {
    if (!_isSearchExpanded) return const SizedBox.shrink();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),
        TextField(
          controller: _searchController,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
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
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.75),
                    ),
                  ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: Theme.of(context).dividerColor.withValues(alpha: 0.35),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: Theme.of(context).dividerColor.withValues(alpha: 0.35),
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
                color: Theme.of(context).dividerColor.withValues(alpha: 0.35),
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
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Searching...',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
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
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withValues(alpha: 0.75),
                            ),
                          ),
                        )),
          ),
      ],
    );
  }

  Widget _buildGeofenceTab(ScrollController scrollController) {
    final selected = _selectedGeofence;
    final bottomPadding = MediaQuery.of(context).padding.bottom + 24 + 72;

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

        _buildSearchToggleButton(),
        _buildSearchPanel(),
        const SizedBox(height: 8),

        Text(
          'Geofence Areas',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onSurface,
          ),
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
                  Text(
                    selected.name,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    selected.address,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
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

        const SizedBox(height: 8),
        ..._pendingNewGeofences.map(_buildGeofenceRow),
        ..._geofences.map((g) {
          final staged =
              g.id != null && _pendingGeofenceUpdates.containsKey(g.id)
              ? _pendingGeofenceUpdates[g.id]!
              : g;
          return _buildGeofenceRow(staged);
        }),
      ],
    );
  }

  Widget _buildAssignmentsTab(ScrollController scrollController) {
    final selected = _selectedGeofence;
    final bottomPadding = MediaQuery.of(context).padding.bottom + 24 + 72;

    if (selected == null) {
      return ListView(
        controller: scrollController,
        padding: EdgeInsets.fromLTRB(12, 12, 12, bottomPadding),
        children: [
          Text(
            'Select a geofence to manage assignments.',
            style: TextStyle(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.75),
            ),
          ),
        ],
      );
    }

    final assignedIds = (selected.assignedEmployees ?? const [])
        .map((e) => e.id.toString())
        .where((id) => id.trim().isNotEmpty)
        .toSet();

    Iterable<UserModel> base = _allEmployees;

    if (_assignmentsFilter == 'assigned') {
      base = base.where((e) => assignedIds.contains(e.id));
    } else if (_assignmentsFilter == 'unassigned') {
      base = base.where((e) => !assignedIds.contains(e.id));
    }

    final q = _assignmentsSearchController.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      base = base.where((e) {
        final name = e.name.toLowerCase();
        final username = (e.username ?? '').toLowerCase();
        return name.contains(q) || username.contains(q);
      });
    }

    final employees = base.toList();

    return ListView(
      controller: scrollController,
      padding: EdgeInsets.fromLTRB(12, 12, 12, bottomPadding),
      children: [
        TextField(
          controller: _assignmentsSearchController,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Search employees...',
          ),
          onChanged: (_) {
            _assignmentsSearchDebounce?.cancel();
            _assignmentsSearchDebounce = Timer(
              const Duration(milliseconds: 250),
              () {
                if (mounted) setState(() {});
              },
            );
          },
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: const Text('All'),
              selected: _assignmentsFilter == 'all',
              onSelected: (_) => setState(() => _assignmentsFilter = 'all'),
            ),
            ChoiceChip(
              label: const Text('Assigned'),
              selected: _assignmentsFilter == 'assigned',
              onSelected: (_) =>
                  setState(() => _assignmentsFilter = 'assigned'),
            ),
            ChoiceChip(
              label: const Text('Unassigned'),
              selected: _assignmentsFilter == 'unassigned',
              onSelected: (_) =>
                  setState(() => _assignmentsFilter = 'unassigned'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Assigned: ${assignedIds.length}',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        ...employees.map((emp) {
          final empId = emp.id;
          final isAssigned =
              empId.trim().isNotEmpty && assignedIds.contains(empId.toString());
          return CheckboxListTile(
            dense: true,
            value: isAssigned,
            title: Text(emp.name),
            subtitle: Text(emp.username ?? ''),
            onChanged: (v) {
              final geofenceId = selected.id;
              if (geofenceId == null) return;
              if (empId.trim().isEmpty) return;

              final current = _pendingGeofenceUpdates[geofenceId] ?? selected;
              final existing = List.of(
                current.assignedEmployees ?? const <UserModel>[],
              );
              if (v == true) {
                if (!existing.any((e) => e.id == empId)) {
                  existing.add(emp);
                }
              } else {
                existing.removeWhere((e) => e.id == empId);
              }
              setState(() {
                _pendingGeofenceUpdates[geofenceId] = current.copyWith(
                  assignedEmployees: existing,
                );
              });
            },
          );
        }),
      ],
    );
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
                child: DraggableScrollableSheet(
                  controller: _sheetController,
                  initialChildSize: 0.28,
                  minChildSize: 0.18,
                  maxChildSize: 0.55,
                  snap: true,
                  snapSizes: const [0.28, 0.5, 0.55],
                  builder: (context, controller) {
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
                              _buildSheetHandle(),
                              TabBar(
                                labelColor: Theme.of(
                                  context,
                                ).colorScheme.onSurface,
                                unselectedLabelColor: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.7),
                                indicatorColor: const Color(0xFF2688d4),
                                dividerColor: Theme.of(
                                  context,
                                ).dividerColor.withValues(alpha: 0.35),
                                tabs: const [
                                  Tab(text: 'Geofences'),
                                  Tab(text: 'Assignments'),
                                ],
                              ),
                              Expanded(
                                child: TabBarView(
                                  children: [
                                    _buildGeofenceTab(controller),
                                    _buildAssignmentsTab(controller),
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
