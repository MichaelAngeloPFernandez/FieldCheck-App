// ignore_for_file: use_build_context_synchronously, library_prefixes, deprecated_member_use
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:ui';
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

class _AdminGeofenceScreenState extends State<AdminGeofenceScreen>
    with SingleTickerProviderStateMixin {
  final GeofenceService _geofenceService = GeofenceService();
  final UserService _userService = UserService();
  List<Geofence> _geofences = [];
  LatLng? _selectedLocation;
  late io.Socket _socket;

  final MapController _mapController = MapController();
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();

  late final TabController _drawerTabController;

  String? _selectedGeofenceId;
  List<UserModel> _allEmployees = [];
  final TextEditingController _assignmentsSearchController =
      TextEditingController();
  Timer? _assignmentsSearchDebounce;
  String _assignmentsFilter = 'all';

  final Map<String, Geofence> _pendingGeofenceUpdates = {};
  final List<Geofence> _pendingNewGeofences = [];
  final Set<String> _pendingDeleteGeofenceIds = <String>{};

  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  bool _isSearchingPlaces = false;
  String? _placesError;
  List<_PlaceSearchResult> _placeResults = [];
  bool _isSearchExpanded = false;

  double _sheetSize = 0.28;

  static const double _sheetMid = 0.28;

  static const double _sheetFullDown = 0.20;
  static const double _sheetFullUp = 0.92;

  static const double _sheetClickDown = 0.18;

  DateTime? _lastSheetDragUpdateAt;

  @override
  void initState() {
    super.initState();
    _drawerTabController = TabController(length: 2, vsync: this);
    _fetchGeofences();
    _fetchAllEmployees();
    _initSocket();

    _sheetController.addListener(() {
      final next = _sheetController.size;
      if (next == _sheetSize) return;
      if (!mounted) return;
      setState(() {
        _sheetSize = next;
      });
    });
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

    options['reconnection'] = true;
    options['reconnectionAttempts'] = 999999;
    options['reconnectionDelay'] = 500;
    options['reconnectionDelayMax'] = 10000;

    _socket = io.io(ApiConfig.baseUrl, options);

    _socket.onConnect((_) => debugPrint('Geofence socket connected'));
    _socket.onDisconnect((_) => debugPrint('Geofence socket disconnected'));

    void refresh(dynamic _) => _fetchGeofences();
    _socket.on('geofenceCreated', refresh);
    _socket.on('geofenceUpdated', refresh);
    _socket.on('geofenceDeleted', refresh);
  }

  @override
  void dispose() {
    _socket.dispose();
    _sheetController.dispose();
    _drawerTabController.dispose();
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

  bool get _hasPendingChanges => _pendingGeofenceUpdates.isNotEmpty;
  bool get _hasPendingNew => _pendingNewGeofences.isNotEmpty;
  bool get _hasPendingDelete => _pendingDeleteGeofenceIds.isNotEmpty;
  bool get _hasAnyPending =>
      _hasPendingChanges || _hasPendingNew || _hasPendingDelete;

  int get _pendingCount =>
      _pendingGeofenceUpdates.length +
      _pendingNewGeofences.length +
      _pendingDeleteGeofenceIds.length;

  void _toggleSheetFull() {
    final target = _sheetSize >= 0.6 ? _sheetClickDown : _sheetFullUp;
    _sheetController.animateTo(
      target,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
    );
  }

  Set<String> get _takenLetters {
    final effective = _pendingGeofenceUpdates.isEmpty
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
    final letters = <String>{};
    for (final g in effective) {
      final l = g.labelLetter;
      if (l == null) continue;
      final v = l.trim().toUpperCase();
      if (v.isEmpty) continue;
      letters.add(v);
    }
    return letters;
  }

  Future<List<_PlaceSearchResult>> _searchPlacesNominatimOnce(
    String query,
  ) async {
    final q = query.trim();
    if (q.length < 3) return const [];

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
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}');
    }

    final decoded = jsonDecode(res.body);
    if (decoded is! List) return const [];
    return decoded
        .map(
          (e) => e is Map<String, dynamic>
              ? e
              : Map<String, dynamic>.from(e as Map),
        )
        .map(_PlaceSearchResult.fromJson)
        .where((r) => r.latLng != null)
        .toList();
  }

  Widget _buildLetterGrid({
    required Set<String> takenLetters,
    required String? selectedLetter,
    required ValueChanged<String> onSelect,
  }) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: List<Widget>.generate(26, (index) {
        final letter = String.fromCharCode('A'.codeUnitAt(0) + index);
        final disabled =
            takenLetters.contains(letter) && selectedLetter != letter;
        final selected = selectedLetter == letter;
        return InkWell(
          onTap: disabled ? null : () => onSelect(letter),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? const Color(0xFF2688d4) : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: disabled
                    ? Colors.black.withValues(alpha: 0.12)
                    : Colors.black.withValues(alpha: 0.35),
                width: 1.2,
              ),
            ),
            child: Text(
              letter,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: disabled
                    ? Colors.black.withValues(alpha: 0.28)
                    : (selected
                          ? Colors.white
                          : Colors.black.withValues(alpha: 0.82)),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildModalMapPreview({
    required LatLng center,
    required double radiusMeters,
    required ValueChanged<LatLng> onCenterChanged,
  }) {
    final localController = MapController();
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 210,
        child: Stack(
          children: [
            FlutterMap(
              mapController: localController,
              options: MapOptions(
                initialCenter: center,
                initialZoom: 17,
                onPositionChanged: (pos, _) {
                  onCenterChanged(pos.center);
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'field_check',
                ),
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: center,
                      radius: radiusMeters,
                      useRadiusInMeter: true,
                      color: Colors.blue.withValues(alpha: 0.18),
                      borderColor: Colors.blue,
                      borderStrokeWidth: 2,
                    ),
                  ],
                ),
              ],
            ),
            const Center(
              child: Icon(Icons.location_on, color: Colors.red, size: 34),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openStageNewGeofenceDialog(
    LatLng center, {
    String? addressHint,
  }) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Opening Add Geofence…'),
        duration: Duration(milliseconds: 700),
      ),
    );
    final nameController = TextEditingController(text: '');
    final addressController = TextEditingController(text: addressHint ?? '');
    final localSearchController = TextEditingController();
    Timer? localDebounce;

    LatLng draftCenter = center;
    double radiusValue = 120;
    String? dialogSelectedLabelLetter;
    String? dialogError;

    List<UserModel> dialogSelectedEmployees = <UserModel>[];
    bool isSearching = false;
    String? placesError;
    List<_PlaceSearchResult> results = [];

    Widget buildDialogBody(
      BuildContext dialogContext,
      void Function(void Function()) setStateDialog,
    ) {
      final taken = _takenLetters;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: localSearchController,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search places...',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (val) {
              localDebounce?.cancel();
              localDebounce = Timer(
                const Duration(milliseconds: 450),
                () async {
                  final q = val.trim();
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
                    final r = await _searchPlacesNominatimOnce(q);
                    setStateDialog(() {
                      results = r;
                      isSearching = false;
                      placesError = r.isEmpty ? 'No results' : null;
                    });
                  } catch (_) {
                    setStateDialog(() {
                      results = [];
                      isSearching = false;
                      placesError = 'Search failed';
                    });
                  }
                },
              );
            },
          ),
          if (isSearching || placesError != null || results.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 8),
              constraints: const BoxConstraints(maxHeight: 160),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.black.withValues(alpha: 0.12)),
                color: Colors.white,
              ),
              child: isSearching
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 10),
                          Text('Searching...'),
                        ],
                      ),
                    )
                  : (results.isNotEmpty
                        ? ListView.builder(
                            itemCount: results.length,
                            itemBuilder: (context, i) {
                              final r = results[i];
                              return ListTile(
                                dense: true,
                                title: Text(
                                  r.displayName,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                onTap: () {
                                  final ll = r.latLng;
                                  if (ll == null) return;
                                  setStateDialog(() {
                                    draftCenter = ll;
                                    results = [];
                                    placesError = null;
                                    isSearching = false;
                                    if (addressController.text.trim().isEmpty ||
                                        addressController.text ==
                                            (addressHint ?? '')) {
                                      addressController.text = r.displayName;
                                    }
                                  });
                                },
                              );
                            },
                          )
                        : Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(placesError ?? 'No results'),
                          )),
            ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 220,
            child: _buildModalMapPreview(
              center: draftCenter,
              radiusMeters: radiusValue,
              onCenterChanged: (c) {
                setStateDialog(() {
                  draftCenter = c;
                });
              },
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Center: ${draftCenter.latitude.toStringAsFixed(5)}, ${draftCenter.longitude.toStringAsFixed(5)}',
            style: TextStyle(
              color: Colors.black.withValues(alpha: 0.62),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: nameController,
            decoration: const InputDecoration(
              labelText: 'Name',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: addressController,
            decoration: const InputDecoration(
              labelText: 'Address',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 14),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Radius (m)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ),
            controller: TextEditingController(
              text: radiusValue.toStringAsFixed(0),
            ),
            keyboardType: TextInputType.number,
            onChanged: (val) {
              final parsed = double.tryParse(val);
              if (parsed == null) return;
              setStateDialog(() {
                radiusValue = parsed.clamp(20.0, 1000.0).toDouble();
              });
            },
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
          const SizedBox(height: 8),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Label Letter (A–Z)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 8),
          _buildLetterGrid(
            takenLetters: taken,
            selectedLetter: dialogSelectedLabelLetter,
            onSelect: (l) {
              setStateDialog(() {
                dialogSelectedLabelLetter = l;
                dialogError = null;
              });
            },
          ),
          const SizedBox(height: 16),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Assign Employees',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _allEmployees.length,
              itemBuilder: (context, i) {
                final emp = _allEmployees[i];
                final checked = dialogSelectedEmployees.any(
                  (e) => e.id == emp.id,
                );
                return CheckboxListTile(
                  dense: true,
                  value: checked,
                  title: Text(emp.name),
                  onChanged: (v) {
                    setStateDialog(() {
                      if (v == true) {
                        if (!dialogSelectedEmployees.any(
                          (e) => e.id == emp.id,
                        )) {
                          dialogSelectedEmployees.add(emp);
                        }
                      } else {
                        dialogSelectedEmployees.removeWhere(
                          (e) => e.id == emp.id,
                        );
                      }
                    });
                  },
                );
              },
            ),
          ),
          if (dialogError != null) ...[
            const SizedBox(height: 12),
            Text(
              dialogError!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      );
    }

    Future<void> validateAndClose(BuildContext dialogContext) async {
      if (nameController.text.trim().isEmpty ||
          addressController.text.trim().isEmpty) {
        return;
      }
      if (dialogSelectedLabelLetter == null) {
        return;
      }
      Navigator.pop(dialogContext, true);
    }

    final shouldStage = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).dialogBackgroundColor,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setStateDialog) {
          return Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 860,
                  maxHeight: MediaQuery.of(sheetContext).size.height * 0.9,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Add Geofence',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: SingleChildScrollView(
                        child: buildDialogBody(sheetContext, setStateDialog),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(sheetContext, false),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: () {
                              if (nameController.text.trim().isEmpty ||
                                  addressController.text.trim().isEmpty) {
                                setStateDialog(() {
                                  dialogError =
                                      'Please provide name and address.';
                                });
                                return;
                              }
                              if (dialogSelectedLabelLetter == null) {
                                setStateDialog(() {
                                  dialogError =
                                      'Please select a label letter (A–Z).';
                                });
                                return;
                              }
                              validateAndClose(sheetContext);
                            },
                            child: const Text('Stage'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );

    localDebounce?.cancel();

    if (shouldStage != true) {
      return;
    }

    final staged = Geofence(
      name: nameController.text.trim().isEmpty
          ? 'New Geofence'
          : nameController.text.trim(),
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
      _selectedLocation = LatLng(staged.latitude, staged.longitude);
      _selectedGeofenceId = null;
    });
  }

  Future<void> _openStageEditGeofenceDialog(Geofence geofence) async {
    final geofenceId = geofence.id;
    final base =
        (geofenceId != null && _pendingGeofenceUpdates.containsKey(geofenceId))
        ? _pendingGeofenceUpdates[geofenceId]!
        : geofence;

    final nameController = TextEditingController(text: base.name);
    final addressController = TextEditingController(text: base.address);
    final localSearchController = TextEditingController();
    Timer? localDebounce;

    LatLng draftCenter = LatLng(base.latitude, base.longitude);
    double radiusValue = base.radius;
    String? dialogSelectedLabelLetter = base.labelLetter;
    String? dialogError;

    List<UserModel> dialogSelectedEmployees = List<UserModel>.from(
      base.assignedEmployees ?? const [],
    );
    bool isSearching = false;
    String? placesError;
    List<_PlaceSearchResult> results = [];
    final shouldStage = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final media = MediaQuery.of(sheetContext);
        final maxWidth = media.size.width >= 900 ? 820.0 : media.size.width;

        return Padding(
          padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: maxWidth,
                maxHeight: media.size.height * 0.92,
              ),
              child: Material(
                color: Theme.of(sheetContext).colorScheme.surface,
                borderRadius: BorderRadius.circular(18),
                clipBehavior: Clip.antiAlias,
                child: StatefulBuilder(
                  builder: (context, setStateDialog) {
                    final taken = _takenLetters;
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                          child: Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'Edit Geofence',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: () => Navigator.pop(context, false),
                                icon: const Icon(Icons.close),
                              ),
                            ],
                          ),
                        ),
                        Flexible(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Card(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            'Assigned employees: ${dialogSelectedEmployees.length}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                        TextButton(
                                          onPressed: () {
                                            Navigator.pop(context, false);
                                            _drawerTabController.animateTo(1);
                                            _sheetController.animateTo(
                                              _sheetFullUp,
                                              duration: const Duration(
                                                milliseconds: 220,
                                              ),
                                              curve: Curves.easeOut,
                                            );
                                          },
                                          child: const Text('Manage'),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                TextField(
                                  controller: localSearchController,
                                  decoration: const InputDecoration(
                                    prefixIcon: Icon(Icons.search),
                                    hintText: 'Search places...',
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                  onChanged: (val) {
                                    localDebounce?.cancel();
                                    localDebounce = Timer(
                                      const Duration(milliseconds: 450),
                                      () async {
                                        final q = val.trim();
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
                                          final r =
                                              await _searchPlacesNominatimOnce(
                                                q,
                                              );
                                          setStateDialog(() {
                                            results = r;
                                            isSearching = false;
                                            placesError = r.isEmpty
                                                ? 'No results'
                                                : null;
                                          });
                                        } catch (_) {
                                          setStateDialog(() {
                                            results = [];
                                            isSearching = false;
                                            placesError = 'Search failed';
                                          });
                                        }
                                      },
                                    );
                                  },
                                ),
                                if (isSearching ||
                                    placesError != null ||
                                    results.isNotEmpty)
                                  Container(
                                    margin: const EdgeInsets.only(top: 8),
                                    constraints: const BoxConstraints(
                                      maxHeight: 160,
                                    ),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: Colors.black.withAlpha(12),
                                      ),
                                      color: Colors.white,
                                    ),
                                    child: isSearching
                                        ? const Padding(
                                            padding: EdgeInsets.all(12),
                                            child: Row(
                                              children: [
                                                SizedBox(
                                                  width: 18,
                                                  height: 18,
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                      ),
                                                ),
                                                SizedBox(width: 10),
                                                Text('Searching...'),
                                              ],
                                            ),
                                          )
                                        : (results.isNotEmpty
                                              ? ListView.builder(
                                                  itemCount: results.length,
                                                  itemBuilder: (context, i) {
                                                    final r = results[i];
                                                    return ListTile(
                                                      dense: true,
                                                      title: Text(
                                                        r.displayName,
                                                        maxLines: 2,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                      onTap: () {
                                                        final ll = r.latLng;
                                                        if (ll == null) return;
                                                        setStateDialog(() {
                                                          draftCenter = ll;
                                                          results = [];
                                                          placesError = null;
                                                          isSearching = false;
                                                          if (addressController
                                                              .text
                                                              .trim()
                                                              .isEmpty) {
                                                            addressController
                                                                    .text =
                                                                r.displayName;
                                                          }
                                                        });
                                                      },
                                                    );
                                                  },
                                                )
                                              : Padding(
                                                  padding: const EdgeInsets.all(
                                                    12,
                                                  ),
                                                  child: Text(
                                                    placesError ?? 'No results',
                                                  ),
                                                )),
                                  ),
                                const SizedBox(height: 12),
                                SizedBox(
                                  width: double.infinity,
                                  height: 240,
                                  child: _buildModalMapPreview(
                                    center: draftCenter,
                                    radiusMeters: radiusValue,
                                    onCenterChanged: (c) {
                                      setStateDialog(() {
                                        draftCenter = c;
                                      });
                                    },
                                  ),
                                ),
                                const SizedBox(height: 10),
                                TextField(
                                  controller: nameController,
                                  decoration: const InputDecoration(
                                    labelText: 'Name',
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                TextField(
                                  controller: addressController,
                                  decoration: const InputDecoration(
                                    labelText: 'Address',
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                const Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    'Radius (m)',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                TextField(
                                  decoration: const InputDecoration(
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                  controller: TextEditingController(
                                    text: radiusValue.toStringAsFixed(0),
                                  ),
                                  keyboardType: TextInputType.number,
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
                                const SizedBox(height: 8),
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
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: List<Widget>.generate(26, (
                                    int index,
                                  ) {
                                    final letter = String.fromCharCode(
                                      'A'.codeUnitAt(0) + index,
                                    );
                                    final disabled =
                                        taken.contains(letter) &&
                                        dialogSelectedLabelLetter != letter;
                                    return ChoiceChip(
                                      label: Text(letter),
                                      selected:
                                          dialogSelectedLabelLetter == letter,
                                      onSelected: disabled
                                          ? null
                                          : (selected) {
                                              setStateDialog(() {
                                                dialogSelectedLabelLetter =
                                                    selected ? letter : null;
                                                dialogError = null;
                                              });
                                            },
                                    );
                                  }),
                                ),
                                if (dialogError != null) ...[
                                  const SizedBox(height: 12),
                                  Text(
                                    dialogError!,
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.error,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: const Text('Cancel'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: FilledButton(
                                  onPressed: () {
                                    if (nameController.text.trim().isEmpty ||
                                        addressController.text.trim().isEmpty) {
                                      setStateDialog(() {
                                        dialogError =
                                            'Please provide name and address.';
                                      });
                                      return;
                                    }
                                    if (dialogSelectedLabelLetter == null) {
                                      setStateDialog(() {
                                        dialogError =
                                            'Please select a label letter (A–Z).';
                                      });
                                      return;
                                    }
                                    Navigator.pop(context, true);
                                  },
                                  child: const Text('Stage'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );

    if (shouldStage != true) return;
    if (geofenceId == null) return;

    final updated = geofence.copyWith(
      name: nameController.text.trim(),
      address: addressController.text.trim(),
      latitude: draftCenter.latitude,
      longitude: draftCenter.longitude,
      radius: radiusValue,
      labelLetter: dialogSelectedLabelLetter,
      assignedEmployees: dialogSelectedEmployees,
    );

    setState(() {
      _pendingGeofenceUpdates[geofenceId] = updated;
      _selectedLocation = draftCenter;
    });
  }

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
      _pendingDeleteGeofenceIds.clear();
    });
  }

  Future<void> _saveAllPending() async {
    if (!_hasAnyPending) return;

    final entries = _pendingGeofenceUpdates.entries.toList();
    int successCount = 0;
    final List<String> failedNames = [];

    for (final id in _pendingDeleteGeofenceIds.toList()) {
      try {
        await _geofenceService.deleteGeofence(id);
        successCount++;
      } catch (_) {
        failedNames.add('Delete:$id');
      }
    }

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
      _pendingDeleteGeofenceIds.clear();
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

  Widget _buildSheetHeader() {
    final pendingCount = _pendingCount;
    final selected = _selectedGeofence;
    final title = selected != null ? selected.name : 'Geofence Manager';
    final subtitle = selected != null
        ? selected.address
        : 'Select a geofence to edit';

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _toggleSheetFull,
      onVerticalDragUpdate: (details) {
        final now = DateTime.now();
        final last = _lastSheetDragUpdateAt;
        if (last != null && now.difference(last).inMilliseconds < 12) {
          return;
        }
        _lastSheetDragUpdateAt = now;
        final screenH = MediaQuery.of(context).size.height;
        if (screenH <= 0) return;
        final delta = -details.delta.dy / screenH;
        final next = (_sheetSize + delta).clamp(_sheetFullDown, _sheetFullUp);
        _sheetController.jumpTo(next);
      },
      onVerticalDragEnd: (_) {
        final snap = <double>[_sheetFullDown, _sheetMid, 0.5, _sheetFullUp]
            .reduce(
              (a, b) => (_sheetSize - a).abs() < (_sheetSize - b).abs() ? a : b,
            );
        _sheetController.animateTo(
          snap,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        ),
        child: Column(
          children: [
            Center(
              child: Container(
                width: 56,
                height: 6,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.28),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.82),
                        ),
                      ),
                    ],
                  ),
                ),
                if (pendingCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2688d4).withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: const Color(0xFF2688d4).withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      '$pendingCount pending',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),

                const SizedBox(width: 8),
                IconButton(
                  tooltip: _sheetSize >= 0.6 ? 'Collapse' : 'Expand',
                  onPressed: _toggleSheetFull,
                  icon: Icon(
                    _sheetSize >= 0.6
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.keyboard_arrow_up_rounded,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
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

  Widget _buildGeofenceRow(Geofence g) {
    final isPendingDelete =
        g.id != null && _pendingDeleteGeofenceIds.contains(g.id);
    final effectiveIsActive = isPendingDelete ? false : g.isActive;

    return ListTile(
      dense: true,
      title: Text(
        g.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Text(
        'r=${g.radius.toStringAsFixed(0)}m',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: Colors.white.withValues(alpha: 0.78)),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Transform.scale(
            scale: 0.9,
            child: Switch(
              value: effectiveIsActive,
              onChanged: isPendingDelete
                  ? null
                  : (v) {
                      final id = g.id;
                      if (id == null) return;
                      final base = _geofences.firstWhere(
                        (x) => x.id == id,
                        orElse: () => g,
                      );
                      final current = _pendingGeofenceUpdates[id] ?? base;
                      setState(() {
                        _pendingGeofenceUpdates[id] = current.copyWith(
                          isActive: v,
                        );
                      });
                    },
            ),
          ),
          IconButton(
            tooltip: 'Edit',
            onPressed: isPendingDelete
                ? null
                : () {
                    _selectGeofence(g);
                    final id = g.id;
                    if (id != null && _pendingGeofenceUpdates.containsKey(id)) {
                      _openStageEditGeofenceDialog(
                        _pendingGeofenceUpdates[id]!,
                      );
                      return;
                    }
                    _openStageEditGeofenceDialog(g);
                  },
            icon: Icon(
              Icons.edit,
              color: Colors.white.withValues(alpha: 0.86),
              size: 20,
            ),
          ),
          IconButton(
            tooltip: isPendingDelete ? 'Restore' : 'Delete',
            onPressed: () {
              final id = g.id;
              if (id == null) return;
              setState(() {
                if (_pendingDeleteGeofenceIds.contains(id)) {
                  _pendingDeleteGeofenceIds.remove(id);
                } else {
                  _pendingDeleteGeofenceIds.add(id);
                  _pendingGeofenceUpdates.remove(id);
                  if (_selectedGeofenceId == id) {
                    _selectedGeofenceId = null;
                  }
                }
              });
            },
            icon: Icon(
              isPendingDelete ? Icons.restore_from_trash : Icons.delete,
              color: isPendingDelete
                  ? Colors.white.withValues(alpha: 0.86)
                  : Colors.red.withValues(alpha: 0.92),
              size: 20,
            ),
          ),
        ],
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
        color: Colors.black.withValues(alpha: 0.30),
        elevation: 0,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: _toggleSearchExpanded,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(Icons.search, color: Colors.white, size: 22),
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
          style: const TextStyle(color: Colors.white),
          cursorColor: Colors.white,
          decoration: InputDecoration(
            hintText: 'Search places (e.g., "Makati", "Ayala")',
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.68)),
            prefixIcon: Icon(
              Icons.search,
              color: Colors.white.withValues(alpha: 0.8),
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
                      color: Colors.white.withValues(alpha: 0.8),
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
            fillColor: Colors.black.withValues(alpha: 0.28),
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
              color: Colors.black.withValues(alpha: 0.28),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
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
                          style: const TextStyle(color: Colors.white),
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
                                color: Color(0xFF60A5FA),
                              ),
                              title: Text(
                                r.displayName,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white),
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
                              color: Colors.white.withValues(alpha: 0.78),
                            ),
                          ),
                        )),
          ),
      ],
    );
  }

  Widget _buildGeofenceTab(ScrollController scrollController) {
    final selected = _selectedGeofence;
    final bottomPadding = MediaQuery.of(context).padding.bottom + 24;

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
                      'Unsaved changes: $_pendingCount',
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

        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: () {
              final seed =
                  _selectedLocation ??
                  (_pendingNewGeofences.isNotEmpty
                      ? LatLng(
                          _pendingNewGeofences.first.latitude,
                          _pendingNewGeofences.first.longitude,
                        )
                      : (_geofences.isNotEmpty
                            ? LatLng(
                                _geofences.first.latitude,
                                _geofences.first.longitude,
                              )
                            : const LatLng(14.5995, 120.9842)));
              _openStageNewGeofenceDialog(seed);
            },
            icon: const Icon(Icons.add),
            label: const Text('Add Geofence'),
          ),
        ),
        const SizedBox(height: 10),

        if (selected != null) ...[
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: () => _openStageEditGeofenceDialog(selected),
                  child: const Text('Edit / Stage Changes'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
        ],

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
          if (g.id != null && _pendingDeleteGeofenceIds.contains(g.id)) {
            return _buildGeofenceRow(g);
          }
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
    final bottomPadding = MediaQuery.of(context).padding.bottom + 24;

    if (selected == null) {
      return ListView(
        controller: scrollController,
        padding: EdgeInsets.fromLTRB(12, 12, 12, bottomPadding),
        children: [
          Text(
            'Select a geofence to manage assignments.',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.82)),
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
          style: const TextStyle(color: Colors.white),
          cursorColor: Colors.white,
          decoration: InputDecoration(
            prefixIcon: Icon(
              Icons.search,
              color: Colors.white.withValues(alpha: 0.8),
            ),
            hintText: 'Search employees...',
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.68)),
            filled: true,
            fillColor: Colors.black.withValues(alpha: 0.28),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: Colors.white.withValues(alpha: 0.14),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: Colors.white.withValues(alpha: 0.14),
              ),
            ),
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
              label: const Text('All', style: TextStyle(color: Colors.white)),
              selected: _assignmentsFilter == 'all',
              onSelected: (_) => setState(() => _assignmentsFilter = 'all'),
              selectedColor: const Color(0xFF2688d4).withValues(alpha: 0.35),
              backgroundColor: Colors.black.withValues(alpha: 0.20),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.16)),
            ),
            ChoiceChip(
              label: const Text(
                'Assigned',
                style: TextStyle(color: Colors.white),
              ),
              selected: _assignmentsFilter == 'assigned',
              onSelected: (_) =>
                  setState(() => _assignmentsFilter = 'assigned'),
              selectedColor: const Color(0xFF2688d4).withValues(alpha: 0.35),
              backgroundColor: Colors.black.withValues(alpha: 0.20),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.16)),
            ),
            ChoiceChip(
              label: const Text(
                'Unassigned',
                style: TextStyle(color: Colors.white),
              ),
              selected: _assignmentsFilter == 'unassigned',
              onSelected: (_) =>
                  setState(() => _assignmentsFilter = 'unassigned'),
              selectedColor: const Color(0xFF2688d4).withValues(alpha: 0.35),
              backgroundColor: Colors.black.withValues(alpha: 0.20),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.16)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Assigned: ${assignedIds.length}',
          style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white),
        ),
        const SizedBox(height: 8),
        ...employees.map((emp) {
          final empId = emp.id;
          final isAssigned =
              empId.trim().isNotEmpty && assignedIds.contains(empId.toString());
          return CheckboxListTile(
            dense: true,
            value: isAssigned,
            activeColor: const Color(0xFF2688d4),
            checkColor: Colors.white,
            side: BorderSide(color: Colors.white.withValues(alpha: 0.45)),
            title: Text(emp.name, style: const TextStyle(color: Colors.white)),
            subtitle: Text(
              emp.username ?? '',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.72)),
            ),
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
      _placeResults = [];
      _placesError = null;
    });

    _openStageNewGeofenceDialog(latLng, addressHint: result.displayName);

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
            isEditable: true,
            onTap: (lat, lng) {
              _openStageNewGeofenceDialog(LatLng(lat, lng));
            },
            onLongPress: (lat, lng) {
              _openStageNewGeofenceDialog(LatLng(lat, lng));
            },
            onGeofenceTap: (geofence) {
              final id = geofence.id;
              Geofence canonical = geofence;
              if (id != null) {
                canonical =
                    _geofences.cast<Geofence?>().firstWhere(
                      (g) => g?.id == id,
                      orElse: () => null,
                    ) ??
                    geofence;
              }

              final effective =
                  (id != null && _pendingGeofenceUpdates.containsKey(id))
                  ? _pendingGeofenceUpdates[id]!
                  : canonical;

              _selectGeofence(effective);
              _openStageEditGeofenceDialog(effective);
            },
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

          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.only(
                left: 12,
                right: 12,
                top: 12,
                bottom: MediaQuery.of(context).padding.bottom,
              ),
              child: DraggableScrollableSheet(
                controller: _sheetController,
                initialChildSize: _sheetMid,
                minChildSize: _sheetFullDown,
                maxChildSize: _sheetFullUp,
                snap: true,
                snapSizes: const [_sheetFullDown, _sheetFullUp],
                builder: (context, controller) {
                  return Material(
                    color: Colors.transparent,
                    elevation: 10,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(16),
                      ),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.40),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(16),
                            ),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.14),
                            ),
                          ),
                          child: Column(
                            children: [
                              _buildSheetHeader(),
                              TabBar(
                                controller: _drawerTabController,
                                labelColor: Colors.white,
                                unselectedLabelColor: Colors.white.withValues(
                                  alpha: 0.72,
                                ),
                                indicatorColor: const Color(0xFF2688d4),
                                dividerColor: Colors.white.withValues(
                                  alpha: 0.12,
                                ),
                                tabs: const [
                                  Tab(text: 'Geofences'),
                                  Tab(text: 'Assignments'),
                                ],
                              ),
                              Expanded(
                                child: TabBarView(
                                  controller: _drawerTabController,
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
