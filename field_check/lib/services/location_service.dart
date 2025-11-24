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
  /// - Uses bestForNavigation accuracy for GPS-grade precision
  /// - Minimal distance filter (1m) for continuous tracking
  /// - Updates every 5 seconds for responsive real-time monitoring
  /// - Applies jitter filtering to remove GPS noise/spikes
  Stream<geolocator.Position> getPositionStream({
    geolocator.LocationAccuracy accuracy =
        geolocator.LocationAccuracy.bestForNavigation,
    int distanceFilter = 1,
    Duration intervalDuration = const Duration(seconds: 5),
  }) async* {
    // Ensure permissions before starting stream
    await getCurrentLocation();
    final baseStream = geolocator.Geolocator.getPositionStream(
      locationSettings: geolocator.LocationSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilter,
      ),
    );

    geolocator.Position? last;
    DateTime? lastTime;

    await for (final pos in baseStream) {
      final now = DateTime.now();
      if (last != null && lastTime != null) {
        final elapsed = now.difference(lastTime).inMilliseconds / 1000.0;
        final distance = geolocator.Geolocator.distanceBetween(
          last.latitude,
          last.longitude,
          pos.latitude,
          pos.longitude,
        );
        // Drop implausible jumps > 200m in 1s (GPS spikes)
        if (elapsed > 0 && (distance / elapsed) > 200.0) {
          continue;
        }
      }
      last = pos;
      lastTime = now;
      yield pos;
      // Update every 5 seconds for real-time tracking
      if (intervalDuration.inMilliseconds > 0) {
        await Future.delayed(intervalDuration);
      }
    }
  }
}
