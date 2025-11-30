// ignore_for_file: undefined_function, undefined_named_parameter
import 'package:geolocator/geolocator.dart' as geolocator;
import 'dart:async';

class LocationService {
  Future<geolocator.Position> getCurrentLocation() async {
    bool serviceEnabled;
    geolocator.LocationPermission permission;

    // Test if location services are enabled.
    serviceEnabled = await geolocator.Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // Location services are not enabled don't continue
      // accessing the position and request users of the
      // App to enable the location services.
      return Future.error('Location services are disabled.');
    }

    permission = await geolocator.Geolocator.checkPermission();
    if (permission == geolocator.LocationPermission.denied) {
      permission = await geolocator.Geolocator.requestPermission();
      if (permission == geolocator.LocationPermission.denied) {
        // Permissions are denied, next time you could try
        // requesting permissions again (this is also where
        // Android's shouldShowRequestPermissionRationale
        // returned true. According to Android guidelines
        // your App should show an explanatory UI now.
        return Future.error('Location permissions are denied');
      }
    }

    if (permission == geolocator.LocationPermission.deniedForever) {
      // Permissions are denied forever, handle appropriately.
      return Future.error(
        'Location permissions are permanently denied, we cannot request permissions.',
      );
    }

    // When we reach here, permissions are granted and we can
    // continue accessing the position of the device.
    return await geolocator.Geolocator.getCurrentPosition();
  }

  /// High-accuracy real-time position stream optimized for employee tracking
  /// - Uses bestForNavigation accuracy for GPS-grade precision (2-5m)
  /// - 0m distance filter for immediate responsive updates
  /// - No artificial delays - streams every position update immediately
  /// - Applies GPS spike filtering to remove implausible jumps
  Stream<geolocator.Position> getPositionStream({
    geolocator.LocationAccuracy accuracy =
        geolocator.LocationAccuracy.bestForNavigation,
    int distanceFilter = 0, // Changed from 1 to 0 for immediate updates
  }) async* {
    // Ensure permissions before starting stream
    await getCurrentLocation();

    // Use raw geolocator stream for lowest latency
    final baseStream = geolocator.Geolocator.getPositionStream(
      locationSettings: geolocator.LocationSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilter,
        timeLimit: const Duration(seconds: 10), // Add timeout for faster initial lock
      ),
    );

    geolocator.Position? last;
    DateTime? lastTime;

    // Stream all positions without artificial delays
    await for (final pos in baseStream) {
      final now = DateTime.now();

      // Skip GPS spikes: implausible jumps > 500m/s (1800 km/h)
      if (last != null && lastTime != null) {
        final elapsed = now.difference(lastTime).inMilliseconds / 1000.0;
        if (elapsed > 0) {
          final distance = geolocator.Geolocator.distanceBetween(
            last.latitude,
            last.longitude,
            pos.latitude,
            pos.longitude,
          );
          final speed = distance / elapsed;

          // Skip implausible speeds (500m/s = unrealistic for human movement)
          if (speed > 500.0) {
            continue; // Skip this GPS spike
          }
        }
      }

      last = pos;
      lastTime = now;
      yield pos; // Emit immediately, no delays
    }
  }
}
