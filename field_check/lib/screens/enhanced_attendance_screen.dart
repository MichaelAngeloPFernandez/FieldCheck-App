// ignore_for_file: avoid_print, use_build_context_synchronously
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/location_service.dart';
import '../services/geofence_service.dart';
import '../models/geofence_model.dart';
import '../services/realtime_service.dart';
import '../services/user_service.dart';
import '../utils/http_util.dart';
import '../services/autosave_service.dart';
import '../widgets/location_tracker_indicator.dart';
import '../widgets/checkin_timer_widget.dart';

class EnhancedAttendanceScreen extends StatefulWidget {
  const EnhancedAttendanceScreen({super.key});

  @override
  State<EnhancedAttendanceScreen> createState() =>
      _EnhancedAttendanceScreenState();
}

class _EnhancedAttendanceScreenState extends State<EnhancedAttendanceScreen> {
  final RealtimeService _realtimeService = RealtimeService();
  final AutosaveService _autosaveService = AutosaveService();
  final LocationService _locationService = LocationService();
  final GeofenceService _geofenceService = GeofenceService();
  final UserService _userService = UserService();

  bool _isCheckedIn = false;
  bool _isLoading = false;
  bool _isOnline = true;
  String _lastCheckTime = "--:--";
  int _pendingSyncCount = 0;

  Position? _userPosition;
  List<Geofence> _assignedGeofences = [];
  List<Geofence> _allGeofences = [];
  Geofence? _currentGeofence;
  bool _isWithinAnyGeofence = false;
  double? _currentDistanceMeters;
  String? _userModelId;

  DateTime? _lastLocationUpdate;

  Timer? _locationUpdateTimer;
  StreamSubscription<Map<String, dynamic>>? _attendanceSubscription;

  @override
  void initState() {
    super.initState();
    _initializeServices();
    _loadAttendanceStatus();
  }

  @override
  void dispose() {
    _locationUpdateTimer?.cancel();
    _attendanceSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initializeServices() async {
    // Initialize realtime service in background (don't block UI)
    _realtimeService.initialize().ignore();

    await _autosaveService.initialize();

    // Listen for real-time attendance updates
    _attendanceSubscription = _realtimeService.attendanceStream.listen((event) {
      if (mounted) {
        _handleRealtimeAttendanceUpdate(event);
      }
    });

    await _loadUserSettings();
    await _loadCurrentUser();
    await _loadAssignedGeofences();
    await _initializeLocation();
    _startLocationUpdates();
    await _loadPendingSyncCount();
  }

  Future<void> _loadCurrentUser() async {
    try {
      final profile = await _userService.getProfile();
      if (!mounted) return;
      setState(() {
        _userModelId = profile.id;
      });
    } catch (_) {
      // Ignore and continue; we will attempt again when needed
    }
  }

  Future<void> _loadUserSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isOnline = !(prefs.getBool('user.offlineMode') ?? false);
    });
  }

  Future<void> _loadPendingSyncCount() async {
    try {
      final list = await _autosaveService.getUnsyncedData();
      final pending = list
          .where((e) => (e['key'] as String).startsWith('attendance_'))
          .length;
      if (mounted) {
        setState(() {
          _pendingSyncCount = pending;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadAssignedGeofences() async {
    try {
      final geofences = await _geofenceService.fetchGeofences();
      List<Geofence> assigned = geofences;
      if (_userModelId != null) {
        assigned = geofences.where((g) {
          if (!g.isActive) return false;
          final employees = g.assignedEmployees ?? const [];
          return employees.any((u) => u.id == _userModelId);
        }).toList();
      } else {
        assigned = geofences.where((g) => g.isActive).toList();
      }
      setState(() {
        _allGeofences = geofences;
        _assignedGeofences = assigned;
      });
    } catch (e) {
      debugPrint('Error loading geofences: $e');
    }
  }

  Future<void> _loadAttendanceStatus() async {
    try {
      // Load attendance status from local storage or initialize as checked out
      if (mounted) {
        setState(() {
          _isCheckedIn = false;
          _lastCheckTime = "--:--";
        });
      }
    } catch (e) {
      debugPrint('Error loading attendance status: $e');
    }
  }

  Future<void> _initializeLocation() async {
    setState(() {
      _isLoading = true;
    });

    try {
      _userPosition = await _locationService.getCurrentLocation();
      _lastLocationUpdate = DateTime.now();
      await _updateGeofenceStatus();
    } catch (e) {
      debugPrint('Error getting location: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _startLocationUpdates() {
    _locationUpdateTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _updateLocationBackground();
    });
  }

  Future<void> _updateLocationBackground() async {
    try {
      final position = await _locationService.getCurrentLocation();
      if (mounted) {
        setState(() {
          _userPosition = position;
          _lastLocationUpdate = DateTime.now();
        });
        await _updateGeofenceStatus();
      }
    } catch (e) {
      debugPrint('Error updating location: $e');
    }
  }

  Future<void> _updateLocation() async {
    try {
      setState(() {
        _isLoading = true;
      });

      final position = await _locationService.getCurrentLocation();
      if (mounted) {
        setState(() {
          _userPosition = position;
          _lastLocationUpdate = DateTime.now();
          _isLoading = false;
        });
        await _updateGeofenceStatus();
      }
    } catch (e) {
      debugPrint('Error updating location: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update location: $e'),
            duration: const Duration(seconds: 3),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _updateGeofenceStatus() async {
    if (_userPosition == null || _assignedGeofences.isEmpty) return;

    double minDistance = double.infinity;
    Geofence? nearestGeofence;
    bool withinAnyGeofence = false;

    for (final geofence in _assignedGeofences) {
      final distance = Geolocator.distanceBetween(
        _userPosition!.latitude,
        _userPosition!.longitude,
        geofence.latitude,
        geofence.longitude,
      );

      if (distance < minDistance) {
        minDistance = distance;
        nearestGeofence = geofence;
      }

      // Check if within geofence radius (without extra tolerance for stricter checking)
      if (distance <= geofence.radius) {
        withinAnyGeofence = true;
      }
    }

    if (mounted) {
      setState(() {
        _currentGeofence = nearestGeofence;
        _currentDistanceMeters = minDistance;
        _isWithinAnyGeofence = withinAnyGeofence;
      });
    }
  }

  void _handleRealtimeAttendanceUpdate(Map<String, dynamic> event) {
    final action = event['action'] as String;
    final data = event['data'] as Map<String, dynamic>;

    if (action == 'new' || action == 'updated') {
      // Update local state based on real-time data
      setState(() {
        _isCheckedIn = data['isCheckedIn'] ?? _isCheckedIn;
        _lastCheckTime = data['lastCheckTime'] ?? _lastCheckTime;
      });
    }
  }

  Future<void> _toggleAttendance() async {
    // Ensure we are using a fresh location before checking geofence status
    final now = DateTime.now();
    if (_userPosition == null ||
        _lastLocationUpdate == null ||
        now.difference(_lastLocationUpdate!).inSeconds > 15) {
      await _updateLocation();
    }

    if (!_isWithinAnyGeofence) {
      _showGeofenceErrorDialog();
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      if (_isCheckedIn) {
        final confirmed = await _confirmCheckout();
        if (!confirmed) {
          if (mounted) {
            setState(() {
              _isLoading = false;
            });
          }
          return;
        }
      } else {
        final proceed = await _ensureTasksBeforeCheckIn();
        if (!proceed) {
          if (mounted) {
            setState(() {
              _isLoading = false;
            });
          }
          return;
        }
      }

      // Get PH timezone time (UTC+8)
      final now = DateTime.now();
      final phTime = now.add(Duration(hours: 8 - now.timeZoneOffset.inHours));
      final hour = phTime.hour % 12 == 0 ? 12 : phTime.hour % 12;
      final ampm = phTime.hour >= 12 ? 'PM' : 'AM';
      final formattedTime =
          "${hour.toString().padLeft(2, '0')}:${phTime.minute.toString().padLeft(2, '0')} $ampm";

      final attendanceData = {
        'isCheckedIn': !_isCheckedIn,
        'timestamp': now.toIso8601String(),
        'latitude': _userPosition?.latitude,
        'longitude': _userPosition?.longitude,
        'geofenceId': _currentGeofence?.id,
        'geofenceName': _currentGeofence?.name,
      };

      // Save to autosave first
      await _autosaveService.saveData(
        'attendance_${now.millisecondsSinceEpoch}',
        attendanceData,
      );

      // Send to server via realtime service
      if (_isOnline) {
        // Emit real-time update
        _realtimeService.emit('attendanceUpdate', attendanceData);
      }
      await _loadPendingSyncCount();

      if (mounted) {
        setState(() {
          _isCheckedIn = attendanceData['isCheckedIn'] as bool;
          _lastCheckTime = formattedTime;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isCheckedIn
                  ? 'Successfully checked in!'
                  : 'Successfully checked out!',
            ),
            backgroundColor: _isCheckedIn ? Colors.green : Colors.blue,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<bool> _confirmCheckout() async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Confirm Check-Out'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Are you sure you want to check out?'),
                const SizedBox(height: 8),
                if (_currentGeofence != null)
                  Text('Location: ${_currentGeofence!.name}'),
                if (_currentDistanceMeters != null)
                  Text(
                    'Distance: ${_currentDistanceMeters!.toStringAsFixed(1)}m',
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Check Out'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<bool> _ensureTasksBeforeCheckIn() async {
    try {
      String? userId = _userModelId;
      if (userId == null) {
        final profile = await _userService.getProfile();
        userId = profile.id;
        if (mounted) {
          setState(() {
            _userModelId = userId;
          });
        }
      }
      // Allow check-in to proceed
      return true;
    } catch (_) {
      return true;
    }
  }

  void _showGeofenceErrorDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Location Error'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'You are not within any of your assigned geofence areas. Please move to an authorized location to check in.',
            ),
            const SizedBox(height: 16),
            if (_assignedGeofences.isNotEmpty) ...[
              const Text(
                'Your assigned locations:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ...(_assignedGeofences.map(
                (geofence) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    '• ${geofence.name} – ${geofence.address} (${geofence.radius}m radius)',
                  ),
                ),
              )),
            ],
            const SizedBox(height: 16),
            const Text(
              'Current location details:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Latitude: ${_userPosition?.latitude.toStringAsFixed(6) ?? 'N/A'}',
            ),
            Text(
              'Longitude: ${_userPosition?.longitude.toStringAsFixed(6) ?? 'N/A'}',
            ),
            if (_currentGeofence != null) ...[
              const SizedBox(height: 8),
              Text('Nearest geofence: ${_currentGeofence!.name}'),
              Text(
                'Distance: ${_currentDistanceMeters?.toStringAsFixed(1) ?? 'N/A'}m',
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _updateLocation();
            },
            child: const Text('Refresh Location'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Attendance',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 24),

                // Real-time status indicator
                if (_realtimeService.isConnected)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.wifi, color: Colors.green.shade600),
                        const SizedBox(width: 8),
                        Text(
                          'Live Updates Active',
                          style: TextStyle(
                            color: Colors.green.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 16),
                if (!_isOnline)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.cloud_off, color: Colors.orange.shade700),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Offline. Pending sync: $_pendingSyncCount',
                            style: TextStyle(color: Colors.orange.shade700),
                          ),
                        ),
                        TextButton(
                          onPressed: _isLoading ? null : _syncOfflineAttendance,
                          child: const Text('Sync Now'),
                        ),
                      ],
                    ),
                  ),

                // Location status
                _buildLocationCard(),
                const SizedBox(height: 24),

                // Check-in/out section
                _buildAttendanceCard(),
                const SizedBox(height: 24),

                // Assigned geofences
                if (_assignedGeofences.isNotEmpty) _buildGeofencesCard(),
                const SizedBox(height: 12),
                // Informational: show all geofences
                if (_allGeofences.isNotEmpty) _buildAllGeofencesCard(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAllGeofencesCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'All Locations (Info)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ...(_allGeofences.map(
              (g) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(
                      Icons.place,
                      size: 16,
                      color: g.isActive ? Colors.blue : Colors.grey,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(g.name)),
                    Text(
                      g.isActive ? 'Active' : 'Inactive',
                      style: TextStyle(
                        fontSize: 12,
                        color: g.isActive ? Colors.blue : Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationCard() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Current Location',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  _isWithinAnyGeofence ? Icons.check_circle : Icons.error,
                  color: _isWithinAnyGeofence ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                Text(
                  _isWithinAnyGeofence
                      ? 'Within authorized area'
                      : 'Outside authorized area',
                  style: TextStyle(
                    color: _isWithinAnyGeofence ? Colors.green : Colors.red,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_currentGeofence != null) ...[
              Text(
                'Current: ${_currentGeofence!.name}',
                style: const TextStyle(fontSize: 14),
              ),
              if (_currentDistanceMeters != null)
                Text(
                  'Distance: ${_currentDistanceMeters!.toStringAsFixed(1)}m',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
            ],
            if (_userPosition != null)
              Text(
                'Coordinates: ${_userPosition!.latitude.toStringAsFixed(6)}, ${_userPosition!.longitude.toStringAsFixed(6)}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttendanceCard() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text(
              _isCheckedIn
                  ? 'You are currently CHECKED IN'
                  : 'You are currently CHECKED OUT',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: _isCheckedIn ? Colors.green : Colors.red,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            // Location Tracker Indicator
            LocationTrackerIndicator(
              isCheckedIn: _isCheckedIn,
              onTap: _updateLocation,
            ),
            const SizedBox(height: 16),
            // Check-In Timer Widget
            if (_isCheckedIn)
              CheckInTimerWidget(
                employeeId: _userModelId ?? 'unknown',
                isCheckedIn: _isCheckedIn,
                customTimeout: const Duration(hours: 8),
                onTimerExpired: (employeeId) {
                  debugPrint('Timer expired for $employeeId');
                  // Handle timer expiration - mark attendance as incomplete
                },
              ),
            const SizedBox(height: 24),
            Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isCheckedIn ? Colors.red[100] : Colors.green[100],
                border: Border.all(
                  color: _isCheckedIn ? Colors.red : Colors.green,
                  width: 4,
                ),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap:
                      (_isLoading || (!_isWithinAnyGeofence && !_isCheckedIn))
                      ? null
                      : _toggleAttendance,
                  child: Center(
                    child: _isLoading
                        ? const CircularProgressIndicator()
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _isCheckedIn ? Icons.logout : Icons.login,
                                size: 48,
                                color: _isCheckedIn ? Colors.red : Colors.green,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _isCheckedIn ? 'CHECK OUT' : 'CHECK IN',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: _isCheckedIn
                                      ? Colors.red
                                      : Colors.green,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (!_isWithinAnyGeofence && !_isCheckedIn) ...[
              const Text(
                'Move inside your assigned geofence to check in.',
                style: TextStyle(color: Colors.red),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _updateLocation,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh Location'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
            if (!_isWithinAnyGeofence && _isCheckedIn) ...[
              const Text(
                'You are outside your geofence. You can still check out.',
                style: TextStyle(color: Colors.orange),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _updateLocation,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh Location'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
            Text(
              _isCheckedIn
                  ? 'Checked in at $_lastCheckTime'
                  : _lastCheckTime == "--:--"
                  ? 'Not checked in yet'
                  : 'Checked out at $_lastCheckTime',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _syncOfflineAttendance() async {
    try {
      setState(() {
        _isLoading = true;
      });
      final unsynced = await _autosaveService.getUnsyncedData();
      final items = <Map<String, dynamic>>[];
      for (final e in unsynced) {
        final key = e['key'] as String;
        if (key.startsWith('attendance_')) {
          final data = e['data'] as Map<String, dynamic>;
          items.add({
            'type': (data['data']?['isCheckedIn'] == true)
                ? 'checkin'
                : 'checkout',
            'timestamp': data['data']?['timestamp'],
            'latitude': data['data']?['latitude'],
            'longitude': data['data']?['longitude'],
            'geofenceId': data['data']?['geofenceId'],
          });
        }
      }
      if (items.isEmpty) {
        await _loadPendingSyncCount();
        setState(() {
          _isLoading = false;
        });
        return;
      }
      final res = await HttpUtil().post(
        '/api/sync',
        body: {'attendance': items},
      );
      if (res.statusCode == 200) {
        for (final e in unsynced) {
          final key = e['key'] as String;
          if (key.startsWith('attendance_')) {
            await _autosaveService.clearData(key);
          }
        }
        await _loadPendingSyncCount();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Synced ${items.length} records')),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Sync failed: ${res.body}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sync error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Widget _buildGeofencesCard() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your Assigned Locations',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ...(_assignedGeofences.map(
              (geofence) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(
                      Icons.location_on,
                      size: 16,
                      color: geofence.id == _currentGeofence?.id
                          ? Colors.green
                          : Colors.grey,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        geofence.name,
                        style: TextStyle(
                          color: geofence.id == _currentGeofence?.id
                              ? Colors.green
                              : null,
                          fontWeight: geofence.id == _currentGeofence?.id
                              ? FontWeight.bold
                              : null,
                        ),
                      ),
                    ),
                    Text(
                      '${geofence.radius}m',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            )),
          ],
        ),
      ),
    );
  }
}
