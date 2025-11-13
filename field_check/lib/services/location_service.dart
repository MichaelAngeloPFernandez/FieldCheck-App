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
        'Location permissions are permanently denied, we cannot request permissions.');
    }

    // When we reach here, permissions are granted and we can
    // continue accessing the position of the device.
    return await geolocator.Geolocator.getCurrentPosition();
  }

  /// Background-friendly position stream with sane defaults and simple filtering.
  /// - desiredAccuracy: best for navigation when active
  /// - distanceFilter: emit only on movement (meters)
  /// - intervalDuration: minimum interval between updates
  /// - Applies a basic jitter filter to drop implausible jumps
  Stream<geolocator.Position> getPositionStream({
    geolocator.LocationAccuracy accuracy = geolocator.LocationAccuracy.best,
    int distanceFilter = 15,
    Duration intervalDuration = const Duration(seconds: 10),
  }) async* {
    // Ensure permissions before starting stream
    await getCurrentLocation();
    final baseStream = geolocator.Geolocator.getPositionStream(
      distanceFilter: distanceFilter,
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
        // Drop improbable jumps > 150m in 1s (likely jitter)
        if (elapsed > 0 && (distance / elapsed) > 150.0) {
          continue;
        }
      }
      last = pos;
      lastTime = now;
      yield pos;
      // Throttle slightly to avoid over-updating downstream
      if (intervalDuration.inMilliseconds > 0) {
        await Future.delayed(intervalDuration);
      }
    }
  }
}