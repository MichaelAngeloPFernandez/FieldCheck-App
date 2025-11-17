// ignore_for_file: use_build_context_synchronously, library_prefixes, deprecated_member_use
import 'package:flutter/material.dart';
import '../widgets/custom_map.dart';
import '../models/geofence_model.dart';
import '../services/geofence_service.dart';
import 'package:latlong2/latlong.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../services/user_service.dart'; // Import UserService
import '../models/user_model.dart'; // Import UserModel
import 'package:field_check/config/api_config.dart';

class AdminGeofenceScreen extends StatefulWidget {
  const AdminGeofenceScreen({super.key});

  @override
  State<AdminGeofenceScreen> createState() => _AdminGeofenceScreenState();
}

class _AdminGeofenceScreenState extends State<AdminGeofenceScreen> {
  final GeofenceService _geofenceService = GeofenceService();
  final UserService _userService = UserService(); // Initialize UserService
  List<Geofence> _geofences = []; // Initialize as empty list
  LatLng? _selectedLocation;
  final double _newGeofenceRadius = 100.0;
  late io.Socket _socket;

  List<UserModel> _allEmployees = []; // All employees fetched from backend

  @override
  void initState() {
    super.initState();
    _fetchGeofences();
    _fetchAllEmployees(); // Fetch all employees
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
    _socket.on('reconnect_attempt', (_) => debugPrint('Geofence socket reconnect attempt'));
    _socket.on('reconnect', (_) => debugPrint('Geofence socket reconnected'));
    _socket.on('reconnect_error', (err) => debugPrint('Geofence socket reconnect error: $err'));
    _socket.on('reconnect_failed', (_) => debugPrint('Geofence socket reconnect failed'));

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          if (_hasOverlaps(_geofences))
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 8, left: 16, right: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amberAccent.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.amber),
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
                  )
                ],
              ),
            ),
          // Map area with geofence drawing tools
          Expanded(
            flex: 3,
            child: Stack(
              children: [
                // Custom map implementation
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: CustomMap(
                    height: double.infinity,
                    geofences: _geofences,
                    currentLocation: _selectedLocation != null
                          ? UserLocation.fromLatLng(_selectedLocation!)
                          : null,
                    isEditable: true,
                    onTap: (lat, lng) {
                      setState(() {
                        _selectedLocation = LatLng(lat, lng);
                      });
                      _showAddGeofenceDialog(lat, lng);
                    },
                  ),
                ),
              ],
            ),
          ),

          // Geofence list
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Geofence Areas',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: () {
                          _showAddGeofenceDialog();
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('Add New'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2688d4),
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: _geofences.length,
                    itemBuilder: (context, index) {
                      final geofence = _geofences[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: ListTile(
                          title: Text(geofence.name),
                          subtitle: Text(geofence.address),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('${geofence.radius.toInt()}m'),
                              const SizedBox(width: 8),
                              Switch(
                                value: geofence.isActive,
                                onChanged: (value) async {
                                  final updatedGeofence = geofence.copyWith(isActive: value);
                                  try {
                                    await _geofenceService.updateGeofence(updatedGeofence);
                                    await _fetchGeofences(); // Refresh list from backend
                                  } catch (e) {
                                    debugPrint('Error updating geofence status: $e');
                                    // Optionally show an error message
                                  }
                                },
                                activeThumbColor: const Color(0xFF2688d4),
                              ),
                              IconButton(
                                icon: const Icon(Icons.edit),
                                onPressed: () {
                                  _showEditGeofenceDialog(geofence, index);
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () {
                                  _deleteGeofence(index);
                                },
                              ),
                            ],
                          ),
                          onTap: () {
                            setState(() {
                              _selectedLocation = LatLng(
                                geofence.latitude,
                                geofence.longitude,
                              );
                            });
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _deleteGeofence(int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Geofence'),
        content: Text('Are you sure you want to delete ${_geofences[index].name}?'),
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

  void _showAddGeofenceDialog([double? lat, double? lng]) {
    final nameController = TextEditingController();
    final addressController = TextEditingController();
    final radiusController = TextEditingController(text: _newGeofenceRadius.toString());
    double radiusValue = _newGeofenceRadius;
    String? dialogSelectedType = 'TEAM'; // Default to TEAM
    String? dialogSelectedLabelLetter; // No default
    List<UserModel> dialogSelectedEmployees = [];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: const Text('Add New Geofence'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                TextField(
                  controller: addressController,
                  decoration: const InputDecoration(labelText: 'Address'),
                ),
                TextField(
                  controller: radiusController,
                  decoration: const InputDecoration(labelText: 'Radius (meters)'),
                  keyboardType: TextInputType.number,
                  onChanged: (val) {
                    final parsed = double.tryParse(val);
                    if (parsed != null) {
                      setStateDialog(() => radiusValue = parsed);
                    }
                  },
                ),
                const SizedBox(height: 12),
                Slider(
                  value: radiusValue,
                  min: 20,
                  max: 1000,
                  divisions: 49,
                  label: '${radiusValue.toInt()} m',
                  onChanged: (v) {
                    setStateDialog(() {
                      radiusValue = v;
                      radiusController.text = v.toStringAsFixed(0);
                    });
                  },
                ),
                const SizedBox(height: 16),
                // Type selection (TEAM/SOLO)
                DropdownButtonFormField<String>(
                  initialValue: dialogSelectedType,
                  decoration: const InputDecoration(labelText: 'Geofence Type'),
                  items: <String>['TEAM', 'SOLO'].map((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(value),
                    );
                  }).toList(),
                  onChanged: (String? newValue) {
                    setStateDialog(() {
                      dialogSelectedType = newValue;
                    });
                  },
                ),
                const SizedBox(height: 16),
                // Label Letter selection (A-Z chips)
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Label Letter (A-Z)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8.0,
                  children: List<Widget>.generate(26, (int index) {
                    final letter = String.fromCharCode('A'.codeUnitAt(0) + index);
                    return ChoiceChip(
                      label: Text(letter),
                      selected: dialogSelectedLabelLetter == letter,
                      onSelected: (bool selected) {
                        setStateDialog(() {
                          dialogSelectedLabelLetter = selected ? letter : null;
                        });
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                // Employee Assignment
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Assign Employees', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 8),
                ..._allEmployees.map((employee) {
                  final isSelected = dialogSelectedEmployees.any((e) => e.id == employee.id);
                  return CheckboxListTile(
                    title: Text(employee.name),
                    value: isSelected,
                    onChanged: (bool? value) {
                      setStateDialog(() {
                        if (value == true) {
                          if (!dialogSelectedEmployees.any((e) => e.id == employee.id)) {
                            dialogSelectedEmployees.add(employee);
                          }
                        } else {
                          dialogSelectedEmployees.removeWhere((e) => e.id == employee.id);
                        }
                      });
                    },
                  );
                }),
                const SizedBox(height: 16),
                Text(
                  lat != null && lng != null
                      ? 'Location: ${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}'
                      : 'No location selected. Tap on the map first.',
                  style: TextStyle(
                    color: lat != null ? Colors.blue : Colors.red,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                setState(() {
                  _selectedLocation = null;
                });
                Navigator.pop(context);
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: lat != null && lng != null
                  ? () async {
                      final name = nameController.text.trim();
                      final address = addressController.text.trim();
                      final radius = double.tryParse(radiusController.text) ?? radiusValue;

                      if (name.isEmpty || address.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Please provide name and address')),
                        );
                        return;
                      }
                      if (dialogSelectedType == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Please select geofence type (TEAM or SOLO)')),
                        );
                        return;
                      }
                      if (dialogSelectedLabelLetter == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Please select a label letter (A–Z)')),
                        );
                        return;
                      }

                      final newGeofence = Geofence(
                        // id omitted so backend generates ObjectId
                        name: name,
                        address: address,
                        latitude: lat,
                        longitude: lng,
                        radius: radius,
                        createdAt: DateTime.now(),
                        isActive: true,
                        shape: GeofenceShape.circle,
                        assignedEmployees: dialogSelectedEmployees,
                        type: dialogSelectedType,
                        labelLetter: dialogSelectedLabelLetter,
                      );

                      try {
                        await _geofenceService.addGeofence(newGeofence);
                        await _fetchGeofences(); // Refresh list from backend
                        setState(() {
                          _selectedLocation = null;
                        });
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Geofence added')),
                        );
                      } catch (e) {
                        debugPrint('Error adding geofence: $e');
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Failed to add geofence: $e')),
                        );
                        Navigator.pop(context);
                      }
                    }
                  : null,
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditGeofenceDialog(Geofence geofence, int index) {
    final nameController = TextEditingController(text: geofence.name);
    final addressController = TextEditingController(text: geofence.address);
    final radiusController = TextEditingController(text: geofence.radius.toString());
    double radiusValue = geofence.radius;
    String? dialogSelectedType = geofence.type; // Initialize with existing type
    String? dialogSelectedLabelLetter = geofence.labelLetter; // Initialize with existing labelLetter
    List<UserModel> dialogSelectedEmployees = List.from(geofence.assignedEmployees ?? []);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: const Text('Edit Geofence'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                TextField(
                  controller: addressController,
                  decoration: const InputDecoration(labelText: 'Address'),
                ),
                TextField(
                  controller: radiusController,
                  decoration: const InputDecoration(labelText: 'Radius (meters)'),
                  keyboardType: TextInputType.number,
                  onChanged: (val) {
                    final parsed = double.tryParse(val);
                    if (parsed != null) {
                      setStateDialog(() => radiusValue = parsed);
                    }
                  },
                ),
                const SizedBox(height: 12),
                Slider(
                  value: radiusValue,
                  min: 20,
                  max: 1000,
                  divisions: 49,
                  label: '${radiusValue.toInt()} m',
                  onChanged: (v) {
                    setStateDialog(() {
                      radiusValue = v;
                      radiusController.text = v.toStringAsFixed(0);
                    });
                  },
                ),
                const SizedBox(height: 16),
                // Type selection (TEAM/SOLO)
                DropdownButtonFormField<String>(
                  initialValue: dialogSelectedType,
                  decoration: const InputDecoration(labelText: 'Geofence Type'),
                  items: <String>['TEAM', 'SOLO'].map((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(value),
                    );
                  }).toList(),
                  onChanged: (String? newValue) {
                    setStateDialog(() {
                      dialogSelectedType = newValue;
                    });
                  },
                ),
                const SizedBox(height: 16),
                // Label Letter selection (A-Z chips)
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Label Letter (A-Z)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8.0,
                  children: List<Widget>.generate(26, (int index) {
                    final letter = String.fromCharCode('A'.codeUnitAt(0) + index);
                    return ChoiceChip(
                      label: Text(letter),
                      selected: dialogSelectedLabelLetter == letter,
                      onSelected: (bool selected) {
                        setStateDialog(() {
                          dialogSelectedLabelLetter = selected ? letter : null;
                        });
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                // Employee Assignment
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Assign Employees', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 8),
                ..._allEmployees.map((employee) {
                  final isSelected = dialogSelectedEmployees.any((e) => e.id == employee.id);
                  return CheckboxListTile(
                    title: Text(employee.name),
                    value: isSelected,
                    onChanged: (bool? value) {
                      setStateDialog(() {
                        if (value == true) {
                          if (!dialogSelectedEmployees.any((e) => e.id == employee.id)) {
                            dialogSelectedEmployees.add(employee);
                          }
                        } else {
                          dialogSelectedEmployees.removeWhere((e) => e.id == employee.id);
                        }
                      });
                    },
                  );
                }),
                const SizedBox(height: 16),
                Text(
                  'Location: ${geofence.latitude.toStringAsFixed(6)}, ${geofence.longitude.toStringAsFixed(6)}',
                  style: const TextStyle(
                    color: Colors.blue,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                final name = nameController.text.trim();
                final address = addressController.text.trim();
                final radius = double.tryParse(radiusController.text) ?? radiusValue;

                if (name.isEmpty || address.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please provide name and address')),
                  );
                  return;
                }
                if (dialogSelectedType == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please select geofence type (TEAM or SOLO)')),
                  );
                  return;
                }
                if (dialogSelectedLabelLetter == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please select a label letter (A–Z)')),
                  );
                  return;
                }

                final updatedGeofence = geofence.copyWith(
                  name: name,
                  address: address,
                  radius: radius,
                  assignedEmployees: dialogSelectedEmployees,
                  type: dialogSelectedType,
                  labelLetter: dialogSelectedLabelLetter,
                );

                try {
                  await _geofenceService.updateGeofence(updatedGeofence);
                  await _fetchGeofences(); // Refresh list from backend
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Geofence updated')),
                  );
                } catch (e) {
                  debugPrint('Error updating geofence: $e');
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to update geofence: $e')),
                  );
                  Navigator.pop(context);
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
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
    final d = Geofence.calculateDistance(a.latitude, a.longitude, b.latitude, b.longitude);
    return d < (a.radius + b.radius);
  }

  void _showOverlapDetails(BuildContext context) {
    final List<String> pairs = [];
    for (int i = 0; i < _geofences.length; i++) {
      for (int j = i + 1; j < _geofences.length; j++) {
        if (_isOverlap(_geofences[i], _geofences[j])) {
          pairs.add('${_geofences[i].name} ↔ ${_geofences[j].name}');
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
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }
}