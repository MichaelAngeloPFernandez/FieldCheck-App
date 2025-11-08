class GeofenceRegion {
  final String id;
  final dynamic center;
  final double radius;
  final Map<String, dynamic>? data;

  GeofenceRegion.circular({
    required this.id,
    required this.center,
    required this.radius,
    this.data,
  });
}

class LatLng {
  final double latitude;
  final double longitude;

  LatLng(this.latitude, this.longitude);
}