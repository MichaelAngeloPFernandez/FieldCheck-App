import 'package:flutter/material.dart';
import 'package:field_check/services/location_tracking_engine.dart';

class LocationTrackerIndicator extends StatefulWidget {
  final bool isCheckedIn;
  final VoidCallback? onTap;

  const LocationTrackerIndicator({
    super.key,
    required this.isCheckedIn,
    this.onTap,
  });

  @override
  State<LocationTrackerIndicator> createState() =>
      _LocationTrackerIndicatorState();
}

class _LocationTrackerIndicatorState extends State<LocationTrackerIndicator> {
  final LocationTrackingEngine _trackingEngine = LocationTrackingEngine();
  bool _gpsEnabled = false;
  double _accuracy = 0;
  DateTime? _lastUpdate;

  @override
  void initState() {
    super.initState();
    _initializeTracking();
  }

  Future<void> _initializeTracking() async {
    final initialized = await _trackingEngine.initialize();
    if (initialized && widget.isCheckedIn) {
      await _trackingEngine.startTracking();
    }

    // Listen to GPS status
    _trackingEngine.gpsStatusStream.listen((enabled) {
      if (mounted) {
        setState(() {
          _gpsEnabled = enabled;
        });
      }
    });

    // Listen to accuracy updates
    _trackingEngine.accuracyStream.listen((accuracy) {
      if (mounted) {
        setState(() {
          _accuracy = accuracy;
          _lastUpdate = DateTime.now();
        });
      }
    });
  }

  @override
  void didUpdateWidget(LocationTrackerIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isCheckedIn && !oldWidget.isCheckedIn) {
      _trackingEngine.startTracking();
    } else if (!widget.isCheckedIn && oldWidget.isCheckedIn) {
      _trackingEngine.stopTracking();
    }
  }

  @override
  void dispose() {
    _trackingEngine.stopTracking();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _gpsEnabled ? Colors.green : Colors.red;
    final statusText = _gpsEnabled ? 'GPS ON' : 'GPS OFF';
    final accuracyText = _accuracy > 0
        ? '${_accuracy.toStringAsFixed(1)}m'
        : 'N/A';
    final lastUpdateText = _lastUpdate != null
        ? 'Updated ${_formatTime(_lastUpdate!)}'
        : 'No updates';
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: statusColor.withValues(alpha: 0.1),
          border: Border.all(color: statusColor, width: 1.5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.location_on, color: statusColor, size: 18),
                const SizedBox(width: 6),
                Text(
                  'Location Tracker',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildInfoRow('Status', statusText, statusColor),
                  const SizedBox(height: 4),
                  _buildInfoRow('Accuracy', accuracyText, Colors.blue),
                  const SizedBox(height: 4),
                  _buildInfoRow(
                    'Last Update',
                    lastUpdateText,
                    onSurface.withValues(alpha: 0.75),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inSeconds < 60) {
      return 'now';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else {
      return '${diff.inHours}h ago';
    }
  }
}
