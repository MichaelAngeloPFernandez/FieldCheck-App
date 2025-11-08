class UserModel {
  final String id;
  final String name;
  final String email;
  final String role;
  final String? employeeId; // Add employeeId field
  final String? avatarUrl; // Add avatarUrl field
  final String? username; // Add username field
  final bool isActive;
  final bool isVerified;

  UserModel({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.employeeId,
    this.avatarUrl,
    this.username,
    this.isActive = true,
    this.isVerified = true,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['_id'] ?? json['id'] ?? '',
      name: json['name'] ?? json['username'] ?? '',
      email: json['email'] ?? '',
      role: json['role'] ?? 'employee',
      employeeId: json['employeeId'], // Parse employeeId
      avatarUrl: json['avatarUrl'], // Parse avatarUrl
      username: json['username'], // Parse username
      isActive: json['isActive'] is bool ? json['isActive'] as bool : (json['isActive'] == null ? true : json['isActive'] == true),
      isVerified: json['isVerified'] is bool ? json['isVerified'] as bool : (json['isVerified'] == null ? true : json['isVerified'] == true),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'role': role,
      'employeeId': employeeId, // Include employeeId in toJson
      'avatarUrl': avatarUrl, // Include avatarUrl in toJson
      'username': username, // Include username in toJson
      'isActive': isActive,
      'isVerified': isVerified,
    };
  }
}