// ignore_for_file: avoid_print, use_build_context_synchronously
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geolocator/geolocator.dart' as geolocator;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/location_service.dart';
import '../services/geofence_service.dart';
import '../models/geofence_model.dart';
import '../services/realtime_service.dart';
import '../services/user_service.dart';
import '../utils/http_util.dart';
import '../services/autosave_service.dart';
import '../services/attendance_service.dart';
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
  final AttendanceService _attendanceService = AttendanceService();

  bool _isCheckedIn = false;
  bool _isLoading = false;
  bool _isOnline = true;
  String _lastCheckTime = "--:--";
  int _pendingSyncCount = 0;
  DateTime? _lastCheckTimestamp;
  DateTime? _localCheckInAnchorTimestamp;

  Position? _userPosition;
  List<Geofence> _assignedGeofences = [];
  List<Geofence> _allGeofences = [];
  Geofence? _currentGeofence;
  bool _isWithinAnyGeofence = false;
  double? _currentDistanceMeters;
  String? _userModelId;

  DateTime? _lastLocationUpdate;
  Timer? _locationUpdateTimer;
  StreamSubscription? _attendanceSub;

  String? _locationIssueMessage;
  bool _locationPermissionDeniedForever = false;
  bool _locationServiceDisabled = false;

  @override
  void initState() {
    super.initState();
    _initializeServices();
    _loadAttendanceStatus();
  }

  @override
  void dispose() {
    _locationUpdateTimer?.cancel();
    _attendanceSub?.cancel();
    super.dispose();
  }

  Future<void> _initializeServices() async {
    // Initialize realtime service in background (don't block UI)
    _realtimeService.initialize().ignore();

    // Listen for attendance updates relevant to this user and refresh status
    _attendanceSub = _realtimeService.attendanceStream.listen((event) {
      try {
        final data = event['data'];
        if (data == null) return;

        String? employeeId;
        if (data is Map<String, dynamic>) {
          final emp = data['employee'];
          if (emp is Map) {
            employeeId = (emp['_id'] ?? emp['id'] ?? emp['employeeId'])
                ?.toString();
          } else if (emp != null) {
            employeeId = emp.toString();
          }
        }

        if (employeeId != null &&
            _userModelId != null &&
            employeeId == _userModelId) {
          // Refresh authoritative status so timer widgets and UI update
          _loadAttendanceStatus();
        }
      } catch (e) {
        debugPrint('Error processing realtime attendance event: $e');
      }
    });

    await _autosaveService.initialize();

    await _loadUserSettings();
    await _loadCurrentUser();
    await _loadAssignedGeofences();
    await _initializeLocation();
    // Note: Location updates only happen on-demand when user taps check-in/out
    // Do NOT call _startLocationUpdates() - it causes unnecessary location polling
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
      // Determine assigned geofences for the current user. The backend
      // returns `assignedEmployees` inside each geofence; prefer those.
      String? userId = _userModelId;
      if (userId == null) {
        try {
          final profile = await _userService.getProfile();
          userId = profile.id;
          if (mounted) {
            setState(() {
              _userModelId = userId;
            });
          }
        } catch (_) {
          // ignore - we'll still show all geofences as fallback
        }
      }

      final allActive = geofences.where((g) => g.isActive).toList();
      List<Geofence> assigned = [];
      if (userId != null) {
        assigned = allActive.where((g) {
          final list = g.assignedEmployees;
          if (list == null || list.isEmpty) return false;
          return list.any((u) => (u.id == userId) || (u.employeeId == userId));
        }).toList();
      }

      // If no explicit assigned geofences found, keep assigned list empty
      // so fallback logic will choose nearest overall geofence instead.
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
      final status = await _attendanceService.getCurrentAttendanceStatus();
      if (mounted) {
        setState(() {
          _isCheckedIn = status.isCheckedIn;
          _lastCheckTime = status.lastCheckTime ?? "--:--";
          final serverTs = status.lastCheckTimestamp;

          if (!_isCheckedIn) {
            _localCheckInAnchorTimestamp = null;
            _lastCheckTimestamp = serverTs;
            return;
          }

          // If we just checked in locally, the backend may briefly return a stale
          // timestamp (previous attendance record / timezone drift). That causes
          // the timer to jump to an old value. Prefer the local anchor until the
          // server returns a timestamp that is not older than it.
          if (_localCheckInAnchorTimestamp != null && serverTs != null) {
            if (serverTs.isBefore(_localCheckInAnchorTimestamp!)) {
              _lastCheckTimestamp = _localCheckInAnchorTimestamp;
              return;
            }
          }

          // Use local anchor if present (for consistent 00:00 start), otherwise
          // fall back to server timestamp.
          _lastCheckTimestamp = _localCheckInAnchorTimestamp ?? serverTs;
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
      await _refreshLocationAndStatus(showSnackOnError: false);
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _updateLocation() async {
    try {
      setState(() {
        _isLoading = true;
      });

      await _refreshLocationAndStatus(showSnackOnError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _refreshLocationAndStatus({required bool showSnackOnError}) async {
    try {
      final position = await _locationService.getCurrentLocation();
      if (!mounted) return;
      setState(() {
        _userPosition = position;
        _lastLocationUpdate = DateTime.now();
        _locationIssueMessage = null;
        _locationPermissionDeniedForever = false;
        _locationServiceDisabled = false;
      });
      await _updateGeofenceStatus();
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      final lower = msg.toLowerCase();

      setState(() {
        _locationIssueMessage = 'Unable to get your location.';
        _locationPermissionDeniedForever = false;
        _locationServiceDisabled = false;

        if (lower.contains('disabled')) {
          _locationIssueMessage = 'GPS is off. Turn on Location Services.';
          _locationServiceDisabled = true;
        } else if (lower.contains('permanently denied') ||
            lower.contains('denied forever')) {
          _locationIssueMessage =
              'Location permission is blocked. Allow it in Settings.';
          _locationPermissionDeniedForever = true;
        } else if (lower.contains('permissions are denied') ||
            lower.contains('permission denied')) {
          _locationIssueMessage = 'Location permission is denied.';
        }
      });

      if (showSnackOnError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_locationIssueMessage ?? 'Failed to update location'),
            duration: const Duration(seconds: 3),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _openSystemLocationSettings() async {
    try {
      await geolocator.Geolocator.openLocationSettings();
    } catch (_) {}
  }

  Future<void> _openSystemAppSettings() async {
    try {
      await geolocator.Geolocator.openAppSettings();
    } catch (_) {}
  }

  Widget _buildLocationStatusBanner() {
    if (_locationIssueMessage == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.gps_off, color: Colors.red.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _locationIssueMessage!,
              style: TextStyle(
                color: Colors.red.shade700,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (_locationServiceDisabled)
            TextButton(
              onPressed: _openSystemLocationSettings,
              child: const Text('Open Settings'),
            )
          else if (_locationPermissionDeniedForever)
            TextButton(
              onPressed: _openSystemAppSettings,
              child: const Text('Open Settings'),
            )
          else
            TextButton(
              onPressed: _isLoading ? null : _updateLocation,
              child: const Text('Retry'),
            ),
        ],
      ),
    );
  }

  Future<void> _updateGeofenceStatus() async {
    if (_userPosition == null || _allGeofences.isEmpty) return;

    final accuracy = _userPosition!.accuracy;
    double extraTolerance = 50;
    if (accuracy > 0) {
      extraTolerance = (accuracy * 1.5).clamp(50, 300).toDouble();
    }

    // PRIORITY 1: Check if employee is inside any ASSIGNED geofence
    Geofence? selectedGeofence;
    double minDistance = double.infinity;
    Geofence? nearestAssignedGeofence;
    bool withinAnyGeofence = false;

    for (final geofence in _assignedGeofences) {
      if (!geofence.isActive) continue;

      final distance = Geolocator.distanceBetween(
        _userPosition!.latitude,
        _userPosition!.longitude,
        geofence.latitude,
        geofence.longitude,
      );

      // Track nearest assigned geofence as fallback
      if (distance < minDistance) {
        minDistance = distance;
        nearestAssignedGeofence = geofence;
      }

      // If inside this assigned geofence, prefer it
      if (distance <= geofence.radius + extraTolerance) {
        withinAnyGeofence = true;
        selectedGeofence = geofence; // Use first assigned geofence we're inside
        break; // Stop at first match (inside assigned geofence)
      }
    }

    // PRIORITY 2: If not inside any assigned geofence, use nearest assigned geofence
    if (selectedGeofence == null && nearestAssignedGeofence != null) {
      selectedGeofence = nearestAssignedGeofence;
    }

    // PRIORITY 3: If no assigned geofences or employee unassigned, fall back to nearest overall
    if (selectedGeofence == null) {
      minDistance = double.infinity;
      for (final geofence in _allGeofences) {
        if (!geofence.isActive) continue;

        final distance = Geolocator.distanceBetween(
          _userPosition!.latitude,
          _userPosition!.longitude,
          geofence.latitude,
          geofence.longitude,
        );

        if (distance < minDistance) {
          minDistance = distance;
          selectedGeofence = geofence;
        }

        if (distance <= geofence.radius + extraTolerance) {
          withinAnyGeofence = true;
        }
      }
    }

    if (mounted) {
      setState(() {
        _currentGeofence = selectedGeofence;
        _currentDistanceMeters = selectedGeofence != null
            ? Geolocator.distanceBetween(
                _userPosition!.latitude,
                _userPosition!.longitude,
                selectedGeofence.latitude,
                selectedGeofence.longitude,
              )
            : null;
        _isWithinAnyGeofence = withinAnyGeofence;
      });
    }
  }

  Future<void> _toggleAttendance() async {
    // Only refresh location if it's stale (> 10 seconds old) or missing
    final now = DateTime.now();
    if (_userPosition == null ||
        _lastLocationUpdate == null ||
        now.difference(_lastLocationUpdate!).inSeconds > 10) {
      try {
        await _updateLocation().timeout(
          const Duration(seconds: 8),
          onTimeout: () {
            debugPrint(
              'Location update timed out, proceeding with last known position',
            );
          },
        );
      } catch (e) {
        debugPrint(
          'Location update failed: $e, proceeding with last known position',
        );
      }
    }

    if (!_isCheckedIn && !_isWithinAnyGeofence) {
      _showGeofenceErrorDialog();
      return;
    }

    if (_isCheckedIn && _userPosition == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Unable to get location. Please enable GPS and try again.',
            ),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
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

        final confirmed = await _confirmCheckIn();
        if (!confirmed) {
          if (mounted) {
            setState(() {
              _isLoading = false;
            });
          }
          return;
        }
      }

      // Get time now
      final now = DateTime.now();

      final bool wasCheckedInBeforeSubmit = _isCheckedIn;

      // For checkout, use current geofence or find the one from the open attendance record
      String? geofenceIdForSubmission = _currentGeofence?.id;

      // If no current geofence, try to use the first assigned geofence as fallback
      if (geofenceIdForSubmission == null && _assignedGeofences.isNotEmpty) {
        geofenceIdForSubmission = _assignedGeofences.first.id;
        debugPrint(
          'Using fallback geofence for checkout: $geofenceIdForSubmission',
        );
      }

      final attendanceData = {
        'isCheckedIn': !_isCheckedIn,
        'timestamp': now.toIso8601String(),
        'latitude': _userPosition?.latitude,
        'longitude': _userPosition?.longitude,
        'geofenceId': geofenceIdForSubmission,
        'geofenceName':
            _currentGeofence?.name ??
            (_assignedGeofences.isNotEmpty
                ? _assignedGeofences.first.name
                : null),
      };

      // DEBUG: Log geofence selection and lists to help diagnose wrong-location bug
      try {
        debugPrint('=== Attendance submit debug ===');
        debugPrint('UserId: ${_userModelId ?? 'unknown'}');
        debugPrint(
          'Selected geofenceIdForSubmission: $geofenceIdForSubmission',
        );
        debugPrint('CurrentGeofence.name: ${_currentGeofence?.name}');
        debugPrint(
          'Assigned geofences (${_assignedGeofences.length}): ${_assignedGeofences
                  .map((g) => '${g.id ?? 'no-id'}:${g.name}')
                  .join(', ')}',
        );
        debugPrint(
          'All geofences (${_allGeofences.length}): ${_allGeofences
                  .map((g) => '${g.id ?? 'no-id'}:${g.name}')
                  .join(', ')}',
        );
        debugPrint('Attendance payload: $attendanceData');
      } catch (e) {
        debugPrint('Error while logging attendance debug: $e');
      }

      // Quick user-visible confirmation of selected geofence to help testing
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Submitting to: ${attendanceData['geofenceName'] ?? 'N/A'} (${attendanceData['geofenceId'] ?? 'no-id'})',
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }

      // Save to autosave first (for offline sync support)
      final storageKey = 'attendance_${now.millisecondsSinceEpoch}';
      await _autosaveService.saveData(storageKey, attendanceData);

      // Try to persist attendance immediately via REST API. We saved an
      // autosave copy above so that if submission fails we can retry later.
      try {
        await _attendanceService.submitAttendance(
          AttendanceData(
            isCheckedIn: !_isCheckedIn,
            timestamp: now,
            latitude: _userPosition?.latitude,
            longitude: _userPosition?.longitude,
            geofenceId: geofenceIdForSubmission,
            geofenceName: _currentGeofence?.name,
          ),
        );

        // Update local state immediately so the timer starts at 00:00 and the
        // UI does not jump due to backend timestamp delay/timezone drift.
        if (mounted) {
          setState(() {
            _isCheckedIn = !wasCheckedInBeforeSubmit;
            if (_isCheckedIn) {
              _localCheckInAnchorTimestamp = now;
            } else {
              _localCheckInAnchorTimestamp = null;
            }
            _lastCheckTimestamp = now;
            _lastCheckTime = TimeOfDay.fromDateTime(now).format(context);
          });
        }

        // Clear autosave copy for successfully synced records
        await _autosaveService.clearData(storageKey);
      } catch (e) {
        // Keep autosave entry for retry and inform the user; do not clear it.
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Attendance submit failed: $e — saved for retry'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }

      // Refresh pending sync count for offline mode banner
      await _loadPendingSyncCount();

      // CRITICAL: Reload attendance status from backend to ensure accurate state
      await _loadAttendanceStatus();

      if (mounted) {
        final newIsCheckedIn = _isCheckedIn; // authoritative server state
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newIsCheckedIn
                  ? 'Successfully checked in!'
                  : 'Successfully checked out!',
            ),
            backgroundColor: newIsCheckedIn ? Colors.green : Colors.blue,
            duration: const Duration(seconds: 3),
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

  Future<bool> _confirmCheckIn() async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Confirm Check-In'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Do you want to check in now?'),
                const SizedBox(height: 8),
                if (_currentGeofence != null)
                  Text('Location: ${_currentGeofence!.name}'),
                if (_currentDistanceMeters != null)
                  Text(
                    'Distance: ${_currentDistanceMeters!.toStringAsFixed(1)}m',
                  ),
                if (_userPosition != null)
                  Text(
                    'GPS accuracy: ${_userPosition!.accuracy.toStringAsFixed(0)}m',
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
                child: const Text('Check In'),
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

                const SizedBox(height: 16),
                _buildLocationStatusBanner(),

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
                checkInTimestamp: _lastCheckTimestamp,
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
