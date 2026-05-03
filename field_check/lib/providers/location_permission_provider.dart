import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Location Permission Provider
/// Manages location permission state and lifecycle
class LocationPermissionProvider extends ChangeNotifier {
  LocationPermission _currentPermission = LocationPermission.denied;
  bool _hasRequestedPermission = false;
  bool _isLocationServiceEnabled = false;

  LocationPermission get currentPermission => _currentPermission;
  bool get hasRequestedPermission => _hasRequestedPermission;
  bool get isLocationServiceEnabled => _isLocationServiceEnabled;
  
  bool get isPermissionGranted =>
      _currentPermission == LocationPermission.whileInUse ||
      _currentPermission == LocationPermission.always;

  bool get isPermissionDenied =>
      _currentPermission == LocationPermission.denied ||
      _currentPermission == LocationPermission.deniedForever;

  LocationPermissionProvider() {
    _initializePermission();
  }

  Future<void> _initializePermission() async {
    try {
      _isLocationServiceEnabled =
          await Geolocator.isLocationServiceEnabled();
      _currentPermission = await Geolocator.checkPermission();
      
      // Check if permission was requested before
      final prefs = await SharedPreferences.getInstance();
      _hasRequestedPermission =
          prefs.getBool('locationPermissionRequested') ?? false;

      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        print('Error initializing location permission: $e');
      }
    }
  }

  Future<LocationPermission> requestLocationPermission() async {
    try {
      // First check if location service is enabled
      _isLocationServiceEnabled =
          await Geolocator.isLocationServiceEnabled();

      if (!_isLocationServiceEnabled) {
        if (kDebugMode) {
          print('Location services are disabled');
        }
        notifyListeners();
        return LocationPermission.denied;
      }

      // Request permission
      _currentPermission = await Geolocator.requestPermission();

      // Mark as requested
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('locationPermissionRequested', true);
      _hasRequestedPermission = true;

      notifyListeners();
      return _currentPermission;
    } catch (e) {
      if (kDebugMode) {
        print('Error requesting location permission: $e');
      }
      return LocationPermission.denied;
    }
  }

  Future<void> checkPermissionStatus() async {
    try {
      _currentPermission = await Geolocator.checkPermission();
      _isLocationServiceEnabled =
          await Geolocator.isLocationServiceEnabled();
      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        print('Error checking permission status: $e');
      }
    }
  }

  Future<void> enableLocationService() async {
    try {
      await Geolocator.openLocationSettings();
      _isLocationServiceEnabled =
          await Geolocator.isLocationServiceEnabled();
      _currentPermission = await Geolocator.checkPermission();
      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        print('Error enabling location service: $e');
      }
    }
  }

  /// Reset permission request state
  /// Useful for testing or when user reinstalls the app
  Future<void> resetPermissionState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('locationPermissionRequested', false);
      _hasRequestedPermission = false;
      await checkPermissionStatus();
      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        print('Error resetting permission state: $e');
      }
    }
  }
}
