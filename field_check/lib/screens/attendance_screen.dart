import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../services/location_service.dart';
import '../services/geofence_service.dart';
import '../models/geofence_model.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/user_service.dart';
import '../config/api_config.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  bool _isCheckedIn = false;
  // final String _currentLocation = "Main Office"; // This will be dynamic based on geofence
  String _lastCheckTime = "--:--";
  bool _isWithinGeofence = true;
  bool _isLoading = false;
  bool _isOnline = true;
  bool _locationError = false;
  String? _locationErrorMessage;
  double? _fallbackLat;
  double? _fallbackLng;

  // Admin-enforced settings
  final bool _allowOfflineModeAdmin = true;
  final bool _requireBeaconVerificationAdmin = false;
  final bool _enableLocationTrackingAdmin = true;

  // User preferences
  bool _userUseBluetoothBeacons = false;
  bool _userEnableLocationTracking = true;

  final LocationService _locationService = LocationService();
  final UserService _userService = UserService();
  final GeofenceService _geofenceService = GeofenceService(); // Initialize GeofenceService
  
  Position? _userPosition;
  Geofence? _nearestGeofence;
  StreamSubscription? _geofenceStatusSubscription;
  double? _currentDistanceMeters;
  DateTime? _lastLocationUpdate;
  
  @override
  void initState() {
    super.initState();
    _loadAdminAndUserSettings();
  }
  
  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadAdminAndUserSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      // Admin settings could be fetched from backend; keeping current defaults
      // _allowOfflineModeAdmin = _allowOfflineModeAdmin;
      // _requireBeaconVerificationAdmin = _requireBeaconVerificationAdmin;
      // _enableLocationTrackingAdmin = _enableLocationTrackingAdmin;
      // User preferences from Settings screen
      _userUseBluetoothBeacons = prefs.getBool('user.useBluetoothBeacons') ?? _userUseBluetoothBeacons;
      _userEnableLocationTracking = prefs.getBool('user.locationTrackingEnabled') ?? _userEnableLocationTracking;
      final offlinePref = prefs.getBool('user.offlineMode') ?? false;
      _isOnline = !offlinePref;
    });
    await _initializeLocationAndGeofence();
  }
  
  Future<void> _initializeLocationAndGeofence() async {
    setState(() {
      _isLoading = true;
    });
    try {
      // Skip if location tracking disabled by admin or user
      if (!_enableLocationTrackingAdmin || !_userEnableLocationTracking) {
        _geofenceStatusSubscription?.cancel();
        setState(() {
          _userPosition = null;
          _nearestGeofence = null;
          _currentDistanceMeters = null;
          _isWithinGeofence = false;
        });
        return;
      }

      _userPosition = await _locationService.getCurrentLocation();
      setState(() {
        _locationError = false;
        _locationErrorMessage = null;
        _fallbackLat = null;
        _fallbackLng = null;
        _lastLocationUpdate = DateTime.now();
      });

      // Persist last known lat/lng for web fallback
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setDouble('lastKnown.lat', _userPosition!.latitude);
        await prefs.setDouble('lastKnown.lng', _userPosition!.longitude);
      } catch (_) {}

      // Fetch nearest geofence from backend
      final allGeofences = await _geofenceService.fetchGeofences();
      if (_userPosition != null && allGeofences.isNotEmpty) {
        _nearestGeofence = _geofenceService.findNearestGeofence(
          _userPosition!.latitude,
          _userPosition!.longitude,
          allGeofences,
        );
      }

      _updateDistanceAndStatus();

    } catch (e) {
      debugPrint('Error initializing location or geofence: $e');
      setState(() {
        _locationError = true;
        _locationErrorMessage = e.toString();
      });

      // Apply graceful fallback: last known or geofence center
      try {
        final geofences = await _geofenceService.fetchGeofences();
        final prefs = await SharedPreferences.getInstance();
        final lastLat = prefs.getDouble('lastKnown.lat');
        final lastLng = prefs.getDouble('lastKnown.lng');

        double? flLat = lastLat;
        double? flLng = lastLng;

        setState(() {
          _fallbackLat = flLat;
          _fallbackLng = flLng;
          _nearestGeofence = (geofences.isNotEmpty && flLat != null && flLng != null)
              ? _geofenceService.findNearestGeofence(flLat, flLng, geofences)
              : null;
        });
            } catch (_) {}
    } finally {
      _updateDistanceAndStatus();
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _updateDistanceAndStatus() {
    final double? userLat = _userPosition?.latitude ?? _fallbackLat;
    final double? userLng = _userPosition?.longitude ?? _fallbackLng;

    if (userLat != null && userLng != null && _nearestGeofence != null) {
      final d = Geofence.calculateDistance(
        _nearestGeofence!.latitude,
        _nearestGeofence!.longitude,
        userLat,
        userLng,
      );
      const double boundaryToleranceMeters = 5.0;
      setState(() {
        _currentDistanceMeters = d;
        _isWithinGeofence = d <= _nearestGeofence!.radius + boundaryToleranceMeters;
      });
    } else {
      setState(() {
        _currentDistanceMeters = null;
        _isWithinGeofence = false;
      });
    }
  }

  Future<void> _updateLocationAndGeofenceStatus() async {
    setState(() {
      _isLoading = true;
      _locationError = false;
      _locationErrorMessage = null;
    });
  
    try {
      final position = await LocationService().getCurrentLocation();
      setState(() {
        _userPosition = position;
        _fallbackLat = null;
        _fallbackLng = null;
        _locationError = false;
        _locationErrorMessage = null;
        _lastLocationUpdate = DateTime.now();
      });

      // Persist last known lat/lng for web fallback
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setDouble('lastKnown.lat', position.latitude);
        await prefs.setDouble('lastKnown.lng', position.longitude);
      } catch (_) {}

      final geofences = await _geofenceService.fetchGeofences();
      setState(() {
        _nearestGeofence = _geofenceService.findNearestGeofence(
          position.latitude,
          position.longitude,
          geofences,
        );
      });
    } catch (e) {
      setState(() {
        _locationError = true;
        _locationErrorMessage = e.toString();
      });

      // Apply graceful fallback: last known or geofence center
      try {
        final geofences = await _geofenceService.fetchGeofences();
        final prefs = await SharedPreferences.getInstance();
        final lastLat = prefs.getDouble('lastKnown.lat');
        final lastLng = prefs.getDouble('lastKnown.lng');

        double? flLat = lastLat;
        double? flLng = lastLng;

        setState(() {
          _fallbackLat = flLat;
          _fallbackLng = flLng;
          _nearestGeofence = (geofences.isNotEmpty && flLat != null && flLng != null)
              ? _geofenceService.findNearestGeofence(flLat, flLng, geofences)
              : null;
        });
            } catch (_) {}
    } finally {
      // Update computed distance and status using position or fallback
      _updateDistanceAndStatus();
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleAttendance() async {
    // Refresh location if we have no position yet or the last update is stale
    final now = DateTime.now();
    if (_enableLocationTrackingAdmin &&
        (_userPosition == null ||
            _lastLocationUpdate == null ||
            now.difference(_lastLocationUpdate!).inSeconds > 15)) {
      await _updateLocationAndGeofenceStatus();
    }

    // Admin-enforced: block offline check if not allowed
    if (!_isOnline && !_allowOfflineModeAdmin) {
      _showOfflineNotAllowedDialog();
      return;
    }

    // Admin-enforced: require beacon usage
    if (_requireBeaconVerificationAdmin && !_userUseBluetoothBeacons) {
      _showBeaconRequiredDialog();
      return;
    }

    // Only enforce geofence when location tracking is enabled by admin
    if (_enableLocationTrackingAdmin && !_isWithinGeofence) {
      _showGeofenceErrorDialog();
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final String endpoint = _isCheckedIn ? 'checkout' : 'checkin';
    final url = Uri.parse('${ApiConfig.baseUrl}/api/attendance/$endpoint');
    final token = await _userService.getToken();

    try {
      final response = await http.post(
          url,
          headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'latitude': _userPosition?.latitude,
          'longitude': _userPosition?.longitude,
          'geofenceId': _nearestGeofence?.id, // Include geofence ID
        }),
      );

      if (response.statusCode == 200) {
        final now = DateTime.now();
        final formattedTime = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";
        if (!mounted) return;
        setState(() {
          _isCheckedIn = !_isCheckedIn;
          _lastCheckTime = formattedTime;
        });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isCheckedIn ? 'Successfully checked in!' : 'Successfully checked out!'),
            backgroundColor: _isCheckedIn ? Colors.green : Colors.blue,
          ),
        );
      } else {
        final error = json.decode(response.body)['message'] ?? 'Failed to update attendance';
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Network error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
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
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            if (!_isOnline)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  border: Border.all(color: Colors.orange.shade200),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.cloud_off, color: Colors.orange.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Offline. Actions will auto-sync when online.',
                        style: TextStyle(color: Colors.orange.shade700),
                      ),
                    ),
                  ],
                ),
              ),
            if (_locationError)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  border: Border.all(color: Colors.orange),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning, color: Colors.orange),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _buildLocationErrorMessageText(),
                        style: const TextStyle(color: Colors.orange),
                      ),
                    ),
                    TextButton(
                      onPressed: _updateLocationAndGeofenceStatus,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            
            // Current location and status
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Current Location',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.location_on, color: Color(0xFF2688d4)),
                        const SizedBox(width: 8),
                        Text(
                          _nearestGeofence?.name ?? 'N/A',
                          style: const TextStyle(fontSize: 16),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_enableLocationTrackingAdmin)
                      Text(
                        'Coordinates: ${_userPosition?.latitude.toStringAsFixed(6) ?? 'N/A'}, ${_userPosition?.longitude.toStringAsFixed(6) ?? 'N/A'}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      )
                    else
                      const Text(
                        'Location tracking disabled by admin',
                        style: TextStyle(fontSize: 12, color: Colors.orange),
                      ),
                    if (_enableLocationTrackingAdmin && _nearestGeofence != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Distance: ${_currentDistanceMeters != null ? '${_currentDistanceMeters!.toStringAsFixed(1)} m' : 'N/A'}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      Text(
                        'Radius: ${_nearestGeofence!.radius.toStringAsFixed(0)} m',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                    const SizedBox(height: 16),
                    if (_enableLocationTrackingAdmin)
                      Row(
                        children: [
                          Icon(
                            _isWithinGeofence ? Icons.check_circle : Icons.error,
                            color: _isWithinGeofence ? Colors.green : Colors.red,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _isWithinGeofence
                                ? 'You are within the geofence area'
                                : 'You are outside the geofence area',
                            style: TextStyle(
                              color: _isWithinGeofence ? Colors.green : Colors.red,
                            ),
                          ),
                        ],
                      )
                    else
                      const Row(
                        children: [
                          Icon(Icons.location_disabled, color: Colors.orange),
                          SizedBox(width: 8),
                          Text('Geofence checks disabled by admin'),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            
            // Check in/out section
            const Text(
              'Check-in/Check-out',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Column(
                children: [
                  Text(
                    _isCheckedIn ? 'You are currently CHECKED IN' : 'You are currently CHECKED OUT',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _isCheckedIn ? Colors.green : Colors.red,
                    ),
                  ),
                  const SizedBox(height: 16),
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
                        onTap: _isLoading ? null : _toggleAttendance,
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
                                        color: _isCheckedIn ? Colors.red : Colors.green,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _isCheckedIn
                        ? 'Checked in at $_lastCheckTime'
                        : _lastCheckTime == "--:--"
                            ? 'Not checked in yet'
                            : 'Checked out at $_lastCheckTime',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Offline and location tracking toggles
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    if (_allowOfflineModeAdmin)
                      GestureDetector(
                        onTap: _toggleOfflineMode,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.grey[200],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _isOnline ? Icons.cloud_done : Icons.cloud_off,
                                color: _isOnline ? Colors.green[700] : Colors.orange[700],
                              ),
                              const SizedBox(width: 8),
                              Text(_isOnline ? 'Online Mode' : 'Offline Mode'),
                            ],
                          ),
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.cloud_done,
                              color: Colors.green,
                            ),
                            SizedBox(width: 8),
                            Text('Online mode enforced'),
                          ],
                        ),
                      ),
                    const SizedBox(width: 8),
                    if (_enableLocationTrackingAdmin)
                      GestureDetector(
                        onTap: _toggleUserLocationTracking,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.grey[200],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _userEnableLocationTracking ? Icons.location_on : Icons.location_off,
                                color: _userEnableLocationTracking ? Colors.green[700] : Colors.orange[700],
                              ),
                              const SizedBox(width: 8),
                              Text(_userEnableLocationTracking ? 'Location: On' : 'Location: Off'),
                            ],
                          ),
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.location_disabled, color: Colors.orange),
                            SizedBox(width: 8),
                            Text('Location disabled by admin'),
                          ],
                        ),
                      ),
                  ],
                ),
                TextButton.icon(
                  onPressed: _updateLocationAndGeofenceStatus,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh Location'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  ),
);
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
              'You are not within the designated geofence area. Please move to an authorized location to check in.',
            ),
            const SizedBox(height: 16),
            const Text(
              'Current location details:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text('Latitude: ${_userPosition != null ? _userPosition!.latitude.toStringAsFixed(6) : 'N/A'}'),
            Text('Longitude: ${_userPosition != null ? _userPosition!.longitude.toStringAsFixed(6) : 'N/A'}'),
            const SizedBox(height: 8),
            if (_nearestGeofence != null) ...[
              Text('Nearest geofence: ${_nearestGeofence?.name ?? 'N/A'}'),
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
              _updateLocationAndGeofenceStatus();
            },
            child: const Text('Refresh Location'),
          ),
        ],
      ),
    );
  }

  void _showOfflineNotAllowedDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Offline Check-in Disabled'),
        content: const Text(
          'Your administrator has disabled offline check-in/check-out. Please switch to online mode to proceed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showBeaconRequiredDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Beacon Verification Required'),
        content: const Text(
          'Your administrator requires Bluetooth beacon verification. Enable beacons in Settings to proceed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _toggleOfflineMode() {
    setState(() {
      _isOnline = !_isOnline;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_isOnline ? 'Switched to online mode' : 'Switched to offline mode'),
      ),
    );
  }

  Future<void> _toggleUserLocationTracking() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userEnableLocationTracking = !_userEnableLocationTracking;
    });
    await prefs.setBool('user.locationTrackingEnabled', _userEnableLocationTracking);

    if (_userEnableLocationTracking) {
      await _initializeLocationAndGeofence();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location tracking enabled')),
      );
    } else {
      setState(() {
        _userPosition = null;
        _nearestGeofence = null;
        _currentDistanceMeters = null;
        _isWithinGeofence = false;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location tracking disabled')),
      );
    }
  }

  String _buildLocationErrorMessageText() {
    final bool isInsecureOrigin = kIsWeb && Uri.base.scheme != 'https';
    final String base = (_locationErrorMessage ?? '').toLowerCase();

    if (isInsecureOrigin) {
      return 'Geolocation blocked on http. Open over https or allow location.';
    }
    if (base.contains('permanently denied') || base.contains('denied forever')) {
      return 'Location permanently denied. Enable in browser site settings.';
    }
    if (base.contains('denied')) {
      return 'Location permission denied. Allow location in site settings.';
    }
    if (base.contains('disabled')) {
      return 'Location services disabled. Enable OS location services and retry.';
    }
    return 'Location unavailable. Check permissions or network and retry.';
  }


}