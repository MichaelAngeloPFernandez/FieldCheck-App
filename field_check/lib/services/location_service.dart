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

    // Fast path: use a recent, reasonably accurate last-known location if available.
    // Accept up to ~200m so indoor GPS fixes can be reused without waiting
    // for a fresh lock every time.
    const double desiredAccuracyMeters = 200;
    try {
      final lastPosition = await geolocator.Geolocator.getLastKnownPosition();

      if (lastPosition != null &&
          lastPosition.accuracy > 0 &&
          lastPosition.accuracy <= desiredAccuracyMeters) {
        return lastPosition;
      }
    } catch (_) {
      // Ignore last-known errors and fall through to a live request.
    }

    // Fallback: single live request with a balanced timeout for GPS lock
    try {
      final current = await geolocator.Geolocator.getCurrentPosition(
        locationSettings: const geolocator.LocationSettings(
          accuracy: geolocator.LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      // Geofence checks are adaptive to accuracy, so we return whatever
      // the OS can provide within the timeout.
      return current;
    } catch (e) {
      // If the live request fails or times out, fall back once more to
      // any last-known position before giving up.
      try {
        final lastPosition = await geolocator.Geolocator.getLastKnownPosition();
        if (lastPosition != null) {
          return lastPosition;
        }
      } catch (_) {}

      rethrow;
    }
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
        timeLimit: const Duration(
          seconds: 30,
        ), // Increased timeout to 30s for better GPS lock
      ),
    );

    geolocator.Position? last;
    DateTime? lastTime;

    // Stream all positions without artificial delays
    await for (final pos in baseStream) {
      final now = DateTime.now();

      // Accept positions with reasonable accuracy (up to 200m for indoor/outdoor GPS)
      // Indoor GPS can have accuracy 50-200m, outdoor 5-10m
      if (pos.accuracy <= 0 || pos.accuracy > 200) {
        continue;
      }

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
