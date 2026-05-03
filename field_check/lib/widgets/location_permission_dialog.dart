import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:app_settings/app_settings.dart';

/// Location Permission Dialog Widget
/// Displays a user-friendly prompt to request location permissions
/// with option to redirect to app settings if denied
class LocationPermissionDialog extends StatefulWidget {
  final VoidCallback? onPermissionGranted;
  final VoidCallback? onPermissionDenied;
  final bool showForAllUsers;

  const LocationPermissionDialog({
    super.key,
    this.onPermissionGranted,
    this.onPermissionDenied,
    this.showForAllUsers = true,
  });

  @override
  State<LocationPermissionDialog> createState() =>
      _LocationPermissionDialogState();
}

class _LocationPermissionDialogState extends State<LocationPermissionDialog> {
  bool _isLoading = false;

  Future<void> _requestLocationPermission() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final permission = await Geolocator.requestPermission();

      if (!mounted) return;

      if (permission == LocationPermission.denied) {
        // Permanently denied - show settings redirect
        _showSettingsRedirect();
      } else if (permission == LocationPermission.deniedForever) {
        // Permanently denied - show settings redirect
        _showSettingsRedirect();
      } else if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        // Permission granted
        Navigator.of(context).pop(true);
        widget.onPermissionGranted?.call();
      } else {
        Navigator.of(context).pop(false);
        widget.onPermissionDenied?.call();
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error requesting permission: $e')),
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

  void _showSettingsRedirect() {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Location Access Required'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Location permission has been denied. To enable location features, please grant permission in your app settings.',
            ),
            SizedBox(height: 16),
            Text('Steps:', style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text('1. Tap "Open Settings"'),
            Text('2. Find and tap "Permissions"'),
            Text('3. Tap "Location"'),
            Text(
              '4. Select "Allow while using the app" or "Allow all the time"',
            ),
            Text('5. Return to FieldCheck'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context, false);
              widget.onPermissionDenied?.call();
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  Future<void> _openAppSettings() async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    try {
      await AppSettings.openLocationSettings();

      // After returning from settings, check permission again
      await Future.delayed(const Duration(milliseconds: 500));

      if (!mounted) return;

      final permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        navigator.pop(true);
        widget.onPermissionGranted?.call();
      } else {
        // Still denied - show dialog again
        _showSettingsRedirect();
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Could not open settings: $e')),
        );
      }
    }
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
              'FieldCheck needs access to your device location to:',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            _buildFeaturePoint(
              theme,
              Icons.check_circle_outline,
              'Track employee location for real-time updates',
            ),
            _buildFeaturePoint(
              theme,
              Icons.check_circle_outline,
              'Verify geofence check-ins and check-outs',
            ),
            _buildFeaturePoint(
              theme,
              Icons.check_circle_outline,
              'Generate accurate location-based reports',
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
                        widget.onPermissionDenied?.call();
                      },
                      child: const Text('Not Now'),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 12),
            Text(
              'You can change this later in Settings',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeaturePoint(ThemeData theme, IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}
