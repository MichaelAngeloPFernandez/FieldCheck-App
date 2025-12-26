class UserModel {
  final String id;
  final String name;
  final String email;
  final String? phone;
  final String role;
  final String? employeeId;
  final String? avatarUrl;
  final String? username;
  final bool isActive;
  final bool isVerified;
  final double? lastLatitude;
  final double? lastLongitude;
  final DateTime? lastLocationUpdate;
  final bool? isOnline;
  final int? activeTaskCount;
  final double? workloadWeight;

  UserModel({
    required this.id,
    required this.name,
    required this.email,
    this.phone,
    required this.role,
    this.employeeId,
    this.avatarUrl,
    this.username,
    this.isActive = true,
    this.isVerified = true,
    this.lastLatitude,
    this.lastLongitude,
    this.lastLocationUpdate,
    this.isOnline,
    this.activeTaskCount,
    this.workloadWeight,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['_id'] ?? json['id'] ?? '',
      name: json['name'] ?? json['username'] ?? '',
      email: json['email'] ?? '',
      phone: json['phone'],
      role: json['role'] ?? 'employee',
      employeeId: json['employeeId'],
      avatarUrl: json['avatarUrl'],
      username: json['username'],
      isActive: json['isActive'] is bool
          ? json['isActive'] as bool
          : (json['isActive'] == null ? true : json['isActive'] == true),
      isVerified: json['isVerified'] is bool
          ? json['isVerified'] as bool
          : (json['isVerified'] == null ? true : json['isVerified'] == true),
      lastLatitude: json['lastLatitude'] is num
          ? (json['lastLatitude'] as num).toDouble()
          : null,
      lastLongitude: json['lastLongitude'] is num
          ? (json['lastLongitude'] as num).toDouble()
          : null,
      lastLocationUpdate: json['lastLocationUpdate'] != null
          ? DateTime.tryParse(json['lastLocationUpdate'].toString())
          : null,
      isOnline: json['isOnline'] is bool ? json['isOnline'] as bool : false,
      activeTaskCount: json['activeTaskCount'] is int
          ? json['activeTaskCount'] as int
          : 0,
      workloadWeight: json['workloadWeight'] is num
          ? (json['workloadWeight'] as num).toDouble()
          : 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'phone': phone,
      'role': role,
      'employeeId': employeeId,
      'avatarUrl': avatarUrl,
      'username': username,
      'isActive': isActive,
      'isVerified': isVerified,
      'lastLatitude': lastLatitude,
      'lastLongitude': lastLongitude,
      'lastLocationUpdate': lastLocationUpdate?.toIso8601String(),
      'isOnline': isOnline,
      'activeTaskCount': activeTaskCount,
      'workloadWeight': workloadWeight,
    };
  }
}
