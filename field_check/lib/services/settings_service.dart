// ignore_for_file: avoid_print
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:field_check/utils/http_util.dart';

class SettingsService {
  static const String _settingsPath = '/api/settings';

  Future<Map<String, String>> _buildHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // Get settings from backend
  Future<Map<String, dynamic>> fetchSettings() async {
    try {
      final headers = await _buildHeaders();
      final response = await HttpUtil().get(_settingsPath, headers: headers);
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to load settings');
      }
    } catch (e) {
      print('Error fetching settings: $e');
      return {};
    }
  }

  // Update settings on backend
  Future<void> updateSettings(Map<String, dynamic> settings) async {
    try {
      final headers = await _buildHeaders();
      final response = await HttpUtil().put(_settingsPath, headers: headers, body: settings);
      if (response.statusCode != 200) {
        throw Exception('Failed to update settings');
      }
    } catch (e) {
      print('Error updating settings: $e');
      rethrow;
    }
  }

  // Get a specific setting from backend
  Future<dynamic> getSetting(String key) async {
    try {
      final headers = await _buildHeaders();
      final response = await HttpUtil().get('$_settingsPath/$key', headers: headers);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['value'];
      } else {
        throw Exception('Setting not found');
      }
    } catch (e) {
      print('Error fetching setting $key: $e');
      return null;
    }
  }

  // Update a specific setting on backend
  Future<void> updateSetting(String key, dynamic value) async {
    try {
      final headers = await _buildHeaders();
      final response = await HttpUtil().put('$_settingsPath/$key', headers: headers, body: {'value': value});
      if (response.statusCode != 200) {
        throw Exception('Failed to update setting');
      }
    } catch (e) {
      print('Error updating setting $key: $e');
      rethrow;
    }
  }

  // Sync local settings with backend
  Future<void> syncSettingsWithBackend() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final settings = {
        'geofenceRadius': prefs.getInt('geofenceRadius')?.toDouble() ?? 100.0,
        'allowOfflineMode': prefs.getBool('allowOfflineMode') ?? true,
        'requireBeaconVerification': prefs.getBool('requireBeaconVerification') ?? false,
        'enableLocationTracking': prefs.getBool('enableLocationTracking') ?? true,
        'syncFrequency': prefs.getString('syncFrequency') ?? 'Every 15 minutes',
      };
      await updateSettings(settings);
    } catch (e) {
      print('Error syncing settings with backend: $e');
    }
  }

  // Load settings from backend to local storage
  Future<void> loadSettingsFromBackend() async {
    try {
      final settings = await fetchSettings();
      final prefs = await SharedPreferences.getInstance();
      
      if (settings.containsKey('geofenceRadius')) {
        await prefs.setInt('geofenceRadius', (settings['geofenceRadius'] as num).toInt());
      }
      if (settings.containsKey('allowOfflineMode')) {
        await prefs.setBool('allowOfflineMode', settings['allowOfflineMode']);
      }
      if (settings.containsKey('requireBeaconVerification')) {
        await prefs.setBool('requireBeaconVerification', settings['requireBeaconVerification']);
      }
      if (settings.containsKey('enableLocationTracking')) {
        await prefs.setBool('enableLocationTracking', settings['enableLocationTracking']);
      }
      if (settings.containsKey('syncFrequency')) {
        await prefs.setString('syncFrequency', settings['syncFrequency']);
      }
    } catch (e) {
      print('Error loading settings from backend: $e');
    }
  }
}
