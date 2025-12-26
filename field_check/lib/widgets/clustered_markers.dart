import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

/// Marker cluster data
class MarkerCluster {
  final List<ClusteredMarker> markers;
  final LatLng center;
  final int count;
  final double radius;

  MarkerCluster({
    required this.markers,
    required this.center,
    required this.count,
    this.radius = 50,
  });

  /// Check if point is within cluster
  bool contains(LatLng point) {
    final distance = Distance().as(LengthUnit.Meter, center, point);
    return distance <= radius;
  }
}

/// Individual clustered marker
class ClusteredMarker {
  final String id;
  final String name;
  final LatLng position;
  final String status;
  final String color;
  final String icon;

  ClusteredMarker({
    required this.id,
    required this.name,
    required this.position,
    required this.status,
    required this.color,
    required this.icon,
  });
}

/// Marker clustering algorithm
class MarkerClusteringService {
  /// Cluster markers using grid-based clustering
  static List<MarkerCluster> clusterMarkers(
    List<ClusteredMarker> markers, {
    double gridSize = 100, // pixels
  }) {
    if (markers.isEmpty) return [];

    final clusters = <MarkerCluster>[];
    final processed = <String>{};

    for (final marker in markers) {
      if (processed.contains(marker.id)) continue;

      final clusterMarkers = <ClusteredMarker>[marker];
      processed.add(marker.id);

      // Find nearby markers
      for (final other in markers) {
        if (processed.contains(other.id)) continue;

        final distance = Distance().as(
          LengthUnit.Meter,
          marker.position,
          other.position,
        );

        if (distance <= gridSize) {
          clusterMarkers.add(other);
          processed.add(other.id);
        }
      }

      // Calculate cluster center
      final avgLat =
          clusterMarkers.fold<double>(
            0,
            (sum, m) => sum + m.position.latitude,
          ) /
          clusterMarkers.length;

      final avgLng =
          clusterMarkers.fold<double>(
            0,
            (sum, m) => sum + m.position.longitude,
          ) /
          clusterMarkers.length;

      clusters.add(
        MarkerCluster(
          markers: clusterMarkers,
          center: LatLng(avgLat, avgLng),
          count: clusterMarkers.length,
        ),
      );
    }

    return clusters;
  }

  /// Get cluster color based on count
  static Color getClusterColor(int count) {
    if (count <= 1) return Colors.green;
    if (count <= 5) return Colors.blue;
    if (count <= 10) return Colors.orange;
    return Colors.red;
  }

  /// Get cluster size based on count
  static double getClusterSize(int count) {
    if (count <= 1) return 40;
    if (count <= 5) return 50;
    if (count <= 10) return 60;
    return 70;
  }
}

/// Cluster widget for map display
class ClusterMarkerWidget extends StatelessWidget {
  final MarkerCluster cluster;
  final VoidCallback onTap;

  const ClusterMarkerWidget({
    super.key,
    required this.cluster,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = MarkerClusteringService.getClusterColor(cluster.count);
    final size = MarkerClusteringService.getClusterSize(cluster.count);

    if (cluster.count == 1) {
      // Single marker
      final marker = cluster.markers.first;
      return GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _getStatusColor(marker.status),
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: _getStatusColor(
                      marker.status,
                    ).withValues(alpha: 0.5),
                    blurRadius: 8,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Icon(
                _getStatusIcon(marker.status),
                color: Colors.white,
                size: size * 0.5,
              ),
            ),
            const SizedBox(height: 2),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(3),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 2,
                  ),
                ],
              ),
              child: Text(
                marker.name.split(' ').first,
                style: const TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    } else {
      // Clustered markers
      return GestureDetector(
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.5),
                blurRadius: 8,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  cluster.count.toString(),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: size * 0.4,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'employees',
                  style: TextStyle(color: Colors.white, fontSize: size * 0.15),
                ),
              ],
            ),
          ),
        ),
      );
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'available':
        return Colors.green;
      case 'moving':
        return Colors.blue;
      case 'busy':
        return Colors.red;
      case 'offline':
        return Colors.grey;
      default:
        return Colors.blueGrey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'available':
        return Icons.check_circle;
      case 'moving':
        return Icons.directions_run;
      case 'busy':
        return Icons.schedule;
      case 'offline':
        return Icons.cloud_off;
      default:
        return Icons.location_on;
    }
  }
}
