import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/geofence_model.dart';
import 'dart:math' as math;

class CustomMap extends StatefulWidget {
  final double width;
  final double height;
  final List<Geofence> geofences;
  final UserLocation? currentLocation;
  final Function(double, double)? onTap;
  final bool isEditable;

  const CustomMap({
    super.key,
    this.width = double.infinity,
    this.height = 300,
    this.geofences = const [],
    this.currentLocation,
    this.onTap,
    this.isEditable = false,
  });

  @override
  State<CustomMap> createState() => _CustomMapState();
}

class _CustomMapState extends State<CustomMap> {
  final MapController _mapController = MapController();

  double _zoomForRadius(double r) {
    if (r <= 75) return 18;
    if (r <= 150) return 17;
    if (r <= 300) return 16;
    if (r <= 600) return 15;
    if (r <= 1200) return 14;
    return 13;
  }

  LatLngBounds? _boundsForGeofences() {
    if (widget.geofences.isEmpty) return null;
    LatLngBounds? bounds;
    for (final g in widget.geofences) {
      final lat = g.latitude;
      final lng = g.longitude;
      final center = LatLng(lat, lng);
      // Approximate meters to degrees
      final metersPerDegreeLat = 111320.0;
      final rad = lat * (3.141592653589793 / 180.0);
      final metersPerDegreeLng = 111320.0 * (math.cos(rad).abs());
      final dLat = g.radius / metersPerDegreeLat;
      final dLng = g.radius / (metersPerDegreeLng == 0 ? 1e-6 : metersPerDegreeLng);
      final p1 = LatLng(lat + dLat, lng + dLng);
      final p2 = LatLng(lat - dLat, lng - dLng);
      final p3 = LatLng(lat + dLat, lng - dLng);
      final p4 = LatLng(lat - dLat, lng + dLng);
      bounds ??= LatLngBounds(p1, p2);
      bounds.extend(p1);
      bounds.extend(p2);
      bounds.extend(p3);
      bounds.extend(p4);
      bounds.extend(center);
    }
    // Also include current location if available
    if (widget.currentLocation != null) {
      bounds!.extend(LatLng(widget.currentLocation!.latitude, widget.currentLocation!.longitude));
    }
    return bounds;
  }

  void _fitAllGeofences({EdgeInsets padding = const EdgeInsets.all(24)}) {
    final bounds = _boundsForGeofences();
    if (bounds == null) return;
    try {
      final fit = CameraFit.bounds(bounds: bounds, padding: padding);
      _mapController.fitCamera(fit);
    } catch (_) {
      // Fallback: move to center of bounds
      final center = bounds.center;
      _mapController.move(center, 14);
    }
  }

  @override
  void initState() {
    super.initState();
    // Auto-fit after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) => _fitAllGeofences());
  }

  @override
  void didUpdateWidget(covariant CustomMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If geofences changed, refit
    if (oldWidget.geofences.length != widget.geofences.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitAllGeofences());
    } else {
      // If any radius/center changed, try refit too
      final changed = oldWidget.geofences.asMap().entries.any((entry) {
        final i = entry.key;
        if (i >= widget.geofences.length) return true;
        final a = entry.value;
        final b = widget.geofences[i];
        return a.latitude != b.latitude || a.longitude != b.longitude || a.radius != b.radius;
      });
      if (changed) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _fitAllGeofences());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Better initial centering based on current location or first geofence
    final LatLng initialCenter = widget.currentLocation != null
        ? LatLng(widget.currentLocation!.latitude, widget.currentLocation!.longitude)
        : (widget.geofences.isNotEmpty
            ? LatLng(widget.geofences.first.latitude, widget.geofences.first.longitude)
            : const LatLng(0, 0));
    final double initialZoom = widget.geofences.isNotEmpty
        ? _zoomForRadius(widget.geofences.first.radius)
        : (widget.currentLocation != null ? 16.0 : 2.0);

    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        border: Border.all(color: Colors.grey),
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: initialCenter,
          initialZoom: initialZoom,
          onTap: (tapPosition, latlng) {
            if (widget.isEditable) {
              _mapController.move(latlng, 18.0);
              if (widget.onTap != null) {
                widget.onTap!(latlng.latitude, latlng.longitude);
              }
            }
          },
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
            subdomains: const ['a', 'b', 'c'],
            userAgentPackageName: 'field_check',
          ),
          CircleLayer(
            circles: [
              for (var geofence in widget.geofences)
                CircleMarker(
                  point: LatLng(geofence.latitude, geofence.longitude),
                  radius: geofence.radius,
                  useRadiusInMeter: true,
                  color: geofence.isActive
                      ? Colors.blue.withAlpha((0.3 * 255).round())
                      : Colors.red.withAlpha((0.3 * 255).round()),
                  borderColor: geofence.isActive ? Colors.blue : Colors.red,
                  borderStrokeWidth: 2,
                ),
            ],
          ),
          if (widget.currentLocation != null)
            MarkerLayer(
              markers: [
                Marker(
                  point: LatLng(widget.currentLocation!.latitude,
                      widget.currentLocation!.longitude),
                  width: 80,
                  height: 80,
                  child: const Icon(
                    Icons.location_on,
                    color: Colors.blue,
                    size: 40,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}