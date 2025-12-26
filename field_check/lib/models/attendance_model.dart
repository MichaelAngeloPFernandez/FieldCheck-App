// ignore_for_file: constant_identifier_names
import 'package:field_check/models/user_model.dart';
import 'package:field_check/models/geofence_model.dart';

class Attendance {
  static const String statusPending = 'pending';
  static const String statusInProgress = 'in_progress';
  static const String statusCompleted = 'completed';

  final String id;
  final UserModel user;
  final Geofence geofence;
  final DateTime timestamp;
  final String status;
  final DateTime? checkIn;
  final DateTime? checkOut;
  final double? duration;

  Attendance({
    required this.id,
    required this.user,
    required this.geofence,
    required this.timestamp,
    required this.status,
    this.checkIn,
    this.checkOut,
    this.duration,
  });

  factory Attendance.fromJson(Map<String, dynamic> json) {
    return Attendance(
      id: json['_id'],
      user: UserModel.fromJson(json['user']),
      geofence: Geofence.fromJson(json['geofence']),
      timestamp: DateTime.parse(json['timestamp']),
      status: json['status'],
      checkIn: json['checkIn'] != null ? DateTime.parse(json['checkIn']) : null,
      checkOut: json['checkOut'] != null ? DateTime.parse(json['checkOut']) : null,
      duration: json['duration']?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      '_id': id,
      'user': user.toJson(),
      'geofence': geofence.toJson(),
      'timestamp': timestamp.toIso8601String(),
      'status': status,
      'checkIn': checkIn?.toIso8601String(),
      'checkOut': checkOut?.toIso8601String(),
      'duration': duration,
    };
  }
}