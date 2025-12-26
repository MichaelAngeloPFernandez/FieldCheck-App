import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';
import '../services/user_service.dart';

/// AuthProvider manages authentication state globally
/// - Tracks login state
/// - Persists JWT token to device
/// - Auto-loads saved token on app startup
/// - Handles logout
class AuthProvider with ChangeNotifier {
  final UserService _userService = UserService();
  SharedPreferences? _prefs;

  // State variables
  UserModel? _user;
  String? _token;
  bool _isLoading = false;
  String? _error;
  bool _isInitialized = false;

  // Getters
  UserModel? get user => _user;
  String? get token => _token;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAuthenticated => _token != null && _user != null;
  bool get isInitialized => _isInitialized;
  bool get isAdmin => _user?.role == 'admin';

  /// Initialize the provider - should be called on app startup
  Future<void> initialize() async {
    try {
      _isLoading = true;
      notifyListeners();

      // Get SharedPreferences instance
      _prefs = await SharedPreferences.getInstance();

      // Try to load saved token from device
      final savedToken = _prefs?.getString('auth_token');

      if (savedToken != null) {
        _token = savedToken;

        // Try to fetch current user profile using saved token
        try {
          final profile = await _userService.getProfile();
          _user = profile;
          _error = null;
          debugPrint('✅ Auto-login successful: ${_user?.name}');
        } catch (e) {
          final refreshed = await _userService.refreshAccessToken();
          if (refreshed) {
            try {
              final profile = await _userService.getProfile();
              _user = profile;
              _error = null;
              debugPrint('✅ Auto-login refreshed: ${_user?.name}');
            } catch (_) {
              await logout();
              debugPrint('⚠️ Refreshed token failed, cleared');
            }
          } else {
            await logout();
            debugPrint('⚠️ Saved token expired, cleared');
          }
        }
      }

      _isInitialized = true;
    } catch (e) {
      _error = e.toString();
      debugPrint('❌ Initialization error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Login user with email/username and password
  Future<bool> login(String identifier, String password) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      // Call backend login
      final user = await _userService.loginIdentifier(identifier, password);

      // Get token from user service (it stores it)
      final token = await _userService.getToken();

      if (token == null) {
        throw Exception('No token returned from login');
      }

      // Save state
      _user = user;
      _token = token;

      // Save token to device for persistence
      await _prefs?.setString('auth_token', token);

      debugPrint('✅ Login successful: ${user.name}');
      return true;
    } catch (e) {
      _error = e.toString();
      debugPrint('❌ Login failed: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Register new user
  Future<bool> register(
    String name,
    String email,
    String password,
    String role, {
    String? username,
  }) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      await _userService.register(
        name,
        email,
        password,
        role: role,
        username: username,
      );

      // Don't auto-login after registration - user needs to verify email first
      _error = null;
      debugPrint('✅ Registration successful: $email');
      return true;
    } catch (e) {
      _error = e.toString();
      debugPrint('❌ Registration failed: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Request password reset email
  Future<bool> requestPasswordReset(String email) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      await _userService.forgotPassword(email);

      debugPrint('✅ Password reset email sent to: $email');
      return true;
    } catch (e) {
      _error = e.toString();
      debugPrint('❌ Password reset request failed: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Reset password with token
  Future<bool> resetPassword(String token, String newPassword) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      await _userService.resetPassword(token, newPassword);

      debugPrint('✅ Password reset successful');
      return true;
    } catch (e) {
      _error = e.toString();
      debugPrint('❌ Password reset failed: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Update user profile
  Future<bool> updateProfile({
    String? name,
    String? email,
    String? username,
    String? avatarUrl,
  }) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final updatedUser = await _userService.updateMyProfile(
        name: name,
        email: email,
        username: username,
        avatarUrl: avatarUrl,
      );

      _user = updatedUser;

      debugPrint('✅ Profile updated');
      return true;
    } catch (e) {
      _error = e.toString();
      debugPrint('❌ Profile update failed: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Logout user
  Future<void> logout() async {
    try {
      _isLoading = true;
      notifyListeners();

      try {
        await _userService.markOffline();
      } catch (_) {}

      // Clear backend token
      await _userService.logout();

      await _prefs?.remove('auth_token');
      await _prefs?.remove('refresh_token');

      // Clear state
      _user = null;
      _token = null;
      _error = null;

      debugPrint('✅ Logout successful');
    } catch (e) {
      _error = e.toString();
      debugPrint('❌ Logout error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Clear error message
  void clearError() {
    _error = null;
    notifyListeners();
  }
}
