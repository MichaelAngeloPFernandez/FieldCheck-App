// ignore_for_file: undefined_function, undefined_named_parameter
import 'package:geolocator/geolocator.dart' as geolocator;
import 'dart:async';
import 'package:flutter/material.dart';

class LocationService {
  static Future<bool> requestLocationPermissionWithDialog(
    BuildContext context, {
    bool showForAllUsers = true,
  }) async {
    // Import widget here to avoid circular dependency
    // ignore: prefer_relative_import
    final locationPermissionDialog = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        // ignore: prefer_relative_import
        return _buildLocationPermissionDialog(showForAllUsers);
      },
    );

    return locationPermissionDialog ?? false;
  }

  static Widget _buildLocationPermissionDialog(bool showForAllUsers) {
    // Lazy-loaded widget to avoid circular imports
    return Builder(
      builder: (context) {
        return _LocationPermissionDialogContent(
          showForAllUsers: showForAllUsers,
        );
      },
    );
  }

  Future<geolocator.Position> getCurrentLocation({
    BuildContext? context,
  }) async {
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
      // Show permission dialog if context is available
      if (context != null) {
        if (!context.mounted) {
          return Future.error('Location permissions are denied');
        }

        final granted = await requestLocationPermissionWithDialog(context);
        if (!granted) {
          return Future.error('Location permissions are denied');
        }

        if (!context.mounted) {
          return Future.error('Location permissions are denied');
        }
        permission = await geolocator.Geolocator.checkPermission();
      } else {
        permission = await geolocator.Geolocator.requestPermission();
        if (permission == geolocator.LocationPermission.denied) {
          return Future.error('Location permissions are denied');
        }
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

/// Internal dialog widget for location permission
class _LocationPermissionDialogContent extends StatefulWidget {
  final bool showForAllUsers;

  const _LocationPermissionDialogContent({required this.showForAllUsers});

  @override
  State<_LocationPermissionDialogContent> createState() =>
      _LocationPermissionDialogContentState();
}

class _LocationPermissionDialogContentState
    extends State<_LocationPermissionDialogContent> {
  bool _isLoading = false;

  Future<void> _requestLocationPermission() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final permission = await geolocator.Geolocator.requestPermission();

      if (!mounted) return;

      if (permission == geolocator.LocationPermission.denied ||
          permission == geolocator.LocationPermission.deniedForever) {
        _showSettingsRedirect();
      } else if (permission == geolocator.LocationPermission.whileInUse ||
          permission == geolocator.LocationPermission.always) {
        Navigator.of(context).pop(true);
      } else {
        Navigator.of(context).pop(false);
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(false);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showSettingsRedirect() {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (settingsContext) => AlertDialog(
        title: const Text('Location Access Required'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Location permission has been denied. Please grant permission in your app settings.',
            ),
            SizedBox(height: 16),
            Text('Steps:', style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text('1. Tap "Open Settings"'),
            Text('2. Find and tap "Permissions"'),
            Text('3. Tap "Location"'),
            Text('4. Select "Allow while using the app"'),
            Text('5. Return to FieldCheck'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(settingsContext);
              Navigator.pop(context, false);
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(settingsContext);
              final navigator = Navigator.of(context);
              final messenger = ScaffoldMessenger.of(context);
              try {
                await geolocator.Geolocator.openLocationSettings();
                // Brief delay to allow settings app to close
                await Future.delayed(const Duration(milliseconds: 500));

                if (!mounted) return;

                final permission =
                    await geolocator.Geolocator.checkPermission();
                if (permission == geolocator.LocationPermission.whileInUse ||
                    permission == geolocator.LocationPermission.always) {
                  navigator.pop(true);
                } else {
                  _showSettingsRedirect();
                }
              } catch (e) {
                if (mounted) {
                  messenger.showSnackBar(
                    SnackBar(content: Text('Could not open settings: $e')),
                  );
                }
              }
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.location_on,
                size: 40,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Enable Location Access',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'FieldCheck needs access to your device location to provide real-time tracking and verification.',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            if (_isLoading)
              const SizedBox(
                height: 40,
                child: Center(child: CircularProgressIndicator()),
              )
            else
              Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _requestLocationPermission,
                      icon: const Icon(Icons.location_on),
                      label: const Text('Grant Location Access'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.of(context).pop(false);
                      },
                      child: const Text('Not Now'),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
