class Geofence {
  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final double radius;

  Geofence({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.radius,
  });

  factory Geofence.fromJson(Map<String, dynamic> json) {
    return Geofence(
      id: json['_id'] as String,
      name: json['name'] as String,
      latitude: (json['coordinates'][0] as num).toDouble(),
      longitude: (json['coordinates'][1] as num).toDouble(),
      radius: (json['radius'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      '_id': id,
      'name': name,
      'coordinates': [latitude, longitude],
      'radius': radius,
    };
  }
}