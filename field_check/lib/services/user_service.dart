import 'dart:convert';
import 'dart:io'; // Import for File
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';
import '../config/api_config.dart';

class UserService {
  static final String _baseUrl = '${ApiConfig.baseUrl}/api';
  // Add cached profile and getter
  UserModel? _cachedProfile;
  UserModel? get currentUser => _cachedProfile;

  Future<String> uploadAvatar(File imageFile) async {
    try {
      final token = await getToken();
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$_baseUrl/upload/avatar'),
      );
      request.files.add(
        await http.MultipartFile.fromPath('avatar', imageFile.path),
      );
      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }
      var response = await request.send();
      if (response.statusCode == 200) {
        final responseData = await http.Response.fromStream(response);
        final data = json.decode(responseData.body);
        return data['avatarUrl'] ?? '';
      } else {
        throw Exception('Failed to upload avatar: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Avatar upload error: $e');
    }
  }

  Future<List<UserModel>> fetchEmployees() async {
    final token = await getToken();
    final response = await http.get(
      Uri.parse('$_baseUrl/users?role=employee'),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
    );
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.map((j) => UserModel.fromJson(j)).toList();
    } else {
      throw Exception('Failed to load employees');
    }
  }

  Future<List<UserModel>> fetchAdmins() async {
    final token = await getToken();
    final response = await http.get(
      Uri.parse('$_baseUrl/users?role=admin'),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
    );
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.map((j) => UserModel.fromJson(j)).toList();
    } else {
      throw Exception('Failed to load administrators');
    }
  }

  Future<UserModel> loginIdentifier(String identifier, String password) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/users/login'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'identifier': identifier, 'password': password}),
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final token = data['token'] as String?;
        final refreshToken = data['refreshToken'] as String?;
        final prefs = await SharedPreferences.getInstance();
        if (token != null) {
          await prefs.setString('auth_token', token);
        }
        if (refreshToken != null) {
          await prefs.setString('refresh_token', refreshToken);
        }
        _cachedProfile = UserModel.fromJson(data);
        return _cachedProfile!;
      } else {
        // Parse server error into a friendly message
        String message = 'Login failed';
        try {
          final dynamic err = json.decode(response.body);
          if (err is Map<String, dynamic>) {
            message = (err['message'] ?? message).toString();
          } else {
            message = err.toString();
          }
        } catch (_) {
          // Not JSON, keep generic
        }
        // Common case from backend: invalid credentials
        if (response.statusCode == 401 || response.statusCode == 400) {
          if (message.toLowerCase().contains('invalid')) {
            message = 'Invalid email/username or password';
          }
        }
        throw Exception(message);
      }
    } on http.ClientException catch (_) {
      throw Exception(
        'Cannot reach server at ${ApiConfig.baseUrl}. Please check the backend.',
      );
    } on SocketException catch (_) {
      throw Exception(
        'Network error. Please confirm you are online and try again.',
      );
    } on TimeoutException catch (_) {
      throw Exception('Request timed out. Server may be busy or unreachable.');
    }
  }

  Future<UserModel> login(String email, String password) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/users/login'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'identifier': email, 'password': password}),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final token = data['token'] as String?;
        final refreshToken = data['refreshToken'] as String?;
        final prefs = await SharedPreferences.getInstance();
        if (token != null) {
          await prefs.setString('auth_token', token);
        }
        if (refreshToken != null) {
          await prefs.setString('refresh_token', refreshToken);
        }
        _cachedProfile = UserModel.fromJson(data);
        return _cachedProfile!;
      } else {
        String message = 'Login failed';
        try {
          final dynamic err = json.decode(response.body);
          if (err is Map<String, dynamic>) {
            message = (err['message'] ?? message).toString();
          } else {
            message = err.toString();
          }
        } catch (_) {}
        if (response.statusCode == 401 || response.statusCode == 400) {
          if (message.toLowerCase().contains('invalid')) {
            message = 'Invalid email/username or password';
          }
        }
        throw Exception(message);
      }
    } on http.ClientException catch (_) {
      throw Exception(
        'Cannot reach server at ${ApiConfig.baseUrl}. Please check the backend.',
      );
    } on SocketException catch (_) {
      throw Exception(
        'Network error. Please confirm you are online and try again.',
      );
    } on TimeoutException catch (_) {
      throw Exception('Request timed out. Server may be busy or unreachable.');
    }
  }

  Future<UserModel> register(
    String name,
    String email,
    String password, {
    String role = 'employee',
    String? username,
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/users'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'name': name,
        'username': username,
        'email': email,
        'password': password,
        'role': role,
      }),
    );
    if (response.statusCode == 201 || response.statusCode == 200) {
      final data = json.decode(response.body);
      return UserModel.fromJson(data);
    } else {
      throw Exception('Registration failed: ${response.body}');
    }
  }

  Future<void> forgotPassword(String email) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/users/forgot-password'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'email': email}),
      );
      if (response.statusCode == 404) {
        throw Exception('Email not found');
      }
      if (response.statusCode != 200) {
        throw Exception('Failed to send reset email: ${response.body}');
      }
    } catch (e) {
      if (e is http.ClientException) {
        throw Exception('Server unreachable. Please try again later.');
      }
      rethrow;
    }
  }

  Future<void> resetPassword(String token, String newPassword) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/users/reset-password/$token'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'password': newPassword}),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to reset password: ${response.body}');
    }
  }

  Future<UserModel> getProfile() async {
    final token = await getToken();
    final response = await http.get(
      Uri.parse('$_baseUrl/users/profile'),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
    );
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final profile = UserModel.fromJson(data);
      _cachedProfile = profile;
      return profile;
    } else if (response.statusCode == 401) {
      final refreshed = await refreshAccessToken();
      if (!refreshed) {
        throw Exception('Session expired');
      }
      final token2 = await getToken();
      final response2 = await http.get(
        Uri.parse('$_baseUrl/users/profile'),
        headers: {
          'Content-Type': 'application/json',
          if (token2 != null) 'Authorization': 'Bearer $token2',
        },
      );
      if (response2.statusCode == 200) {
        final data = json.decode(response2.body);
        final profile = UserModel.fromJson(data);
        _cachedProfile = profile;
        return profile;
      }
      throw Exception('Failed to load profile: ${response2.body}');
    } else {
      throw Exception('Failed to load profile: ${response.body}');
    }
  }

  Future<UserModel> updateMyProfile({
    String? name,
    String? email,
    String? avatarUrl,
    String? username,
  }) async {
    final token = await getToken();
    final payload = <String, dynamic>{};
    if (name != null) payload['name'] = name;
    if (email != null) payload['email'] = email;
    if (username != null) payload['username'] = username;
    if (avatarUrl != null)
      payload['avatarUrl'] = avatarUrl; // Add avatarUrl to payload

    final response = await http.put(
      Uri.parse('$_baseUrl/users/profile'),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
      body: json.encode(payload),
    );
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return UserModel.fromJson(data);
    } else if (response.statusCode == 401) {
      final refreshed = await refreshAccessToken();
      if (!refreshed) {
        throw Exception('Session expired');
      }
      final token2 = await getToken();
      final response2 = await http.put(
        Uri.parse('$_baseUrl/users/profile'),
        headers: {
          'Content-Type': 'application/json',
          if (token2 != null) 'Authorization': 'Bearer $token2',
        },
        body: json.encode(payload),
      );
      if (response2.statusCode == 200) {
        final data = json.decode(response2.body);
        return UserModel.fromJson(data);
      }
      throw Exception('Failed to update profile: ${response2.body}');
    } else {
      throw Exception('Failed to update profile: ${response.body}');
    }
  }

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token');
  }

  Future<String?> getRefreshToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('refresh_token');
  }

  Future<bool> refreshAccessToken() async {
    final refreshToken = await getRefreshToken();
    if (refreshToken == null) return false;
    final res = await http.post(
      Uri.parse('$_baseUrl/users/refresh-token'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'refreshToken': refreshToken}),
    );
    if (res.statusCode == 200) {
      final data = json.decode(res.body);
      final prefs = await SharedPreferences.getInstance();
      final token = data['token'] as String?;
      final refreshToken2 = data['refreshToken'] as String?;
      if (token != null) await prefs.setString('auth_token', token);
      if (refreshToken2 != null)
        await prefs.setString('refresh_token', refreshToken2);
      return true;
    }
    return false;
  }

  Future<void> logout() async {
    final token = await getToken();
    try {
      await http.post(
        Uri.parse('$_baseUrl/users/logout'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      );
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('refresh_token');
    _cachedProfile = null;
  }

  // Admin-only operations
  Future<void> deleteUser(String id) async {
    final token = await getToken();
    final response = await http.delete(
      Uri.parse('$_baseUrl/users/$id'),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to delete user: ${response.body}');
    }
  }

  Future<void> deactivateUser(String id) async {
    final token = await getToken();
    final response = await http.put(
      Uri.parse('$_baseUrl/users/$id/deactivate'),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to deactivate user: ${response.body}');
    }
  }

  Future<void> reactivateUser(String id) async {
    // Reactivate via admin update endpoint
    await updateUserByAdmin(id, isActive: true);
  }

  Future<UserModel> updateUserByAdmin(
    String userModelId, {
    String? name,
    String? email,
    String? role,
    bool? isActive,
    String? username,
  }) async {
    final token = await getToken();
    final payload = <String, dynamic>{};
    if (name != null) payload['name'] = name;
    if (email != null) payload['email'] = email;
    if (role != null) payload['role'] = role;
    if (isActive != null) payload['isActive'] = isActive;
    if (username != null) payload['username'] = username;

    final response = await http.put(
      Uri.parse('$_baseUrl/users/$userModelId'),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
      body: json.encode(payload),
    );
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return UserModel.fromJson(data);
    } else {
      throw Exception('Failed to update user: ${response.body}');
    }
  }

  Future<List<UserModel>> fetchUsers({String? role}) async {
    final token = await getToken();
    final uri = Uri.parse(
      '$_baseUrl/users${role != null ? '?role=$role' : ''}',
    );
    final response = await http.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
    );
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.map((j) => UserModel.fromJson(j)).toList();
    } else {
      throw Exception('Failed to fetch users: ${response.body}');
    }
  }

  Future<Map<String, dynamic>> importUsersJson(String jsonStr) async {
    final token = await getToken();
    final response = await http.post(
      Uri.parse('$_baseUrl/users/import'),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
      body: jsonStr,
    );
    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception('Failed to import users: ${response.body}');
    }
  }
}
