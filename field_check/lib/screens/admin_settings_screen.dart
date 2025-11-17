// ignore_for_file: use_build_context_synchronously, library_prefixes
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import '../services/user_service.dart';
import 'manage_employees_screen.dart';
import 'manage_admins_screen.dart';
import 'admin_geofence_screen.dart';
import '../utils/export_util_stub.dart'
    if (dart.library.io) '../utils/export_util_io.dart'
    if (dart.library.html) '../utils/export_util_web.dart' as export_util;
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../services/settings_service.dart';
import 'package:field_check/config/api_config.dart';

class AdminSettingsScreen extends StatefulWidget {
  const AdminSettingsScreen({super.key});

  @override
  State<AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends State<AdminSettingsScreen> {
  bool _allowOfflineMode = true;
  bool _requireBeaconVerification = false;
  bool _enableLocationTracking = true;
  int _geofenceRadius = 100;
  String _syncFrequency = 'Every 15 minutes';

  final UserService _userService = UserService();
  final SettingsService _settingsService = SettingsService();
  late io.Socket _socket;

  @override
  void initState() {
    super.initState();
    _initSocket();
    _loadSettings();
  }

  void _initSocket() {
    // Add Authorization header and reconnection/backoff settings
    final baseOptions = io.OptionBuilder()
        .setTransports(['websocket'])
        .enableAutoConnect()
        .setTimeout(20000)
        .build();
    baseOptions['reconnection'] = true;
    baseOptions['reconnectionAttempts'] = 999999;
    baseOptions['reconnectionDelay'] = 500;
    baseOptions['reconnectionDelayMax'] = 10000;

    _userService.getToken().then((token) {
      final options = Map<String, dynamic>.from(baseOptions);
      if (token != null) {
        options['extraHeaders'] = {'Authorization': 'Bearer $token'};
      }
      _socket = io.io(ApiConfig.baseUrl, options);

      _socket.onConnect((_) {
        debugPrint('Connected to settings socket');
      });

      _socket.on('settingsUpdated', (data) async {
        // data can be an object of all settings or a single key update
        if (data is Map) {
          final prefs = await SharedPreferences.getInstance();
          setState(() {
            if (data.containsKey('geofenceRadius')) {
              _geofenceRadius = (data['geofenceRadius'] as num).toInt();
              prefs.setInt('geofenceRadius', _geofenceRadius);
            }
            if (data.containsKey('allowOfflineMode')) {
              _allowOfflineMode = data['allowOfflineMode'] == true;
              prefs.setBool('allowOfflineMode', _allowOfflineMode);
            }
            if (data.containsKey('requireBeaconVerification')) {
              _requireBeaconVerification = data['requireBeaconVerification'] == true;
              prefs.setBool('requireBeaconVerification', _requireBeaconVerification);
            }
            if (data.containsKey('enableLocationTracking')) {
              _enableLocationTracking = data['enableLocationTracking'] == true;
              prefs.setBool('enableLocationTracking', _enableLocationTracking);
            }
            if (data.containsKey('syncFrequency')) {
              _syncFrequency = data['syncFrequency'] as String;
              prefs.setString('syncFrequency', _syncFrequency);
            }
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Settings synced in real-time')),
          );
        }
      });

      _socket.onDisconnect((_) {
        debugPrint('Settings socket disconnected');
      });
      _socket.on('reconnect_attempt', (_) => debugPrint('Settings socket reconnect attempt'));
      _socket.on('reconnect', (_) => debugPrint('Settings socket reconnected'));
      _socket.on('reconnect_error', (err) => debugPrint('Settings socket reconnect error: $err'));
      _socket.on('reconnect_failed', (_) => debugPrint('Settings socket reconnect failed'));
    });
  }

  @override
  void dispose() {
    _socket.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await _settingsService.fetchSettings();
      if (settings.isNotEmpty) {
        setState(() {
          _allowOfflineMode = settings['allowOfflineMode'] ?? _allowOfflineMode;
          _requireBeaconVerification = settings['requireBeaconVerification'] ?? _requireBeaconVerification;
          _enableLocationTracking = settings['enableLocationTracking'] ?? _enableLocationTracking;
          _geofenceRadius = (settings['geofenceRadius'] as num?)?.toInt() ?? _geofenceRadius;
          _syncFrequency = settings['syncFrequency'] ?? _syncFrequency;
        });
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('allowOfflineMode', _allowOfflineMode);
        await prefs.setBool('requireBeaconVerification', _requireBeaconVerification);
        await prefs.setBool('enableLocationTracking', _enableLocationTracking);
        await prefs.setInt('geofenceRadius', _geofenceRadius);
        await prefs.setString('syncFrequency', _syncFrequency);
      } else {
        // Fallback to local if backend not available
        final prefs = await SharedPreferences.getInstance();
        setState(() {
          _allowOfflineMode = prefs.getBool('allowOfflineMode') ?? _allowOfflineMode;
          _requireBeaconVerification = prefs.getBool('requireBeaconVerification') ?? _requireBeaconVerification;
          _enableLocationTracking = prefs.getBool('enableLocationTracking') ?? _enableLocationTracking;
          _geofenceRadius = prefs.getInt('geofenceRadius') ?? _geofenceRadius;
          _syncFrequency = prefs.getString('syncFrequency') ?? _syncFrequency;
        });
      }
    } catch (e) {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _allowOfflineMode = prefs.getBool('allowOfflineMode') ?? _allowOfflineMode;
        _requireBeaconVerification = prefs.getBool('requireBeaconVerification') ?? _requireBeaconVerification;
        _enableLocationTracking = prefs.getBool('enableLocationTracking') ?? _enableLocationTracking;
        _geofenceRadius = prefs.getInt('geofenceRadius') ?? _geofenceRadius;
        _syncFrequency = prefs.getString('syncFrequency') ?? _syncFrequency;
      });
    }
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('allowOfflineMode', _allowOfflineMode);
    await prefs.setBool('requireBeaconVerification', _requireBeaconVerification);
    await prefs.setBool('enableLocationTracking', _enableLocationTracking);
    await prefs.setInt('geofenceRadius', _geofenceRadius);
    await prefs.setString('syncFrequency', _syncFrequency);

    // Push to backend for real-time sync across accounts
    try {
      await _settingsService.updateSettings({
        'allowOfflineMode': _allowOfflineMode,
        'requireBeaconVerification': _requireBeaconVerification,
        'enableLocationTracking': _enableLocationTracking,
        'geofenceRadius': _geofenceRadius.toDouble(),
        'syncFrequency': _syncFrequency,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved and synced')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save settings: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24 + kBottomNavigationBarHeight),
          children: [
            const Text(
              'System Settings',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            
            // Geofence Settings
            _buildSectionHeader('Geofence Settings'),
            _buildSliderSetting(
              title: 'Default Geofence Radius',
              value: _geofenceRadius.toDouble(),
              min: 50,
              max: 500,
              divisions: 9,
              unit: 'm',
              onChanged: (value) {
                setState(() {
                  _geofenceRadius = value.round();
                });
              },
            ),
            ListTile(
              title: const Text('Manage Geofences'),
              subtitle: const Text('Add, edit, enable/disable geofence areas'),
              leading: const Icon(Icons.map),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AdminGeofenceScreen()),
                );
              },
            ),
            
            // Verification Settings
            _buildSectionHeader('Verification Settings'),
            _buildSwitchSetting(
              title: 'Allow Offline Mode',
              subtitle: 'Employees can check in/out without internet connection',
              value: _allowOfflineMode,
              onChanged: (value) {
                setState(() {
                  _allowOfflineMode = value;
                  // Coupling: enabling offline mode ensures location tracking is enabled
                  if (value) {
                    _enableLocationTracking = true;
                  }
                });
              },
            ),
            _buildSwitchSetting(
              title: 'Require Beacon Verification',
              subtitle: 'Use Bluetooth beacons for additional location verification',
              value: _requireBeaconVerification,
              onChanged: (value) {
                setState(() {
                  _requireBeaconVerification = value;
                });
              },
            ),
            _buildSwitchSetting(
              title: 'Enable Location Tracking',
              subtitle: 'Track employee location during work hours',
              value: _enableLocationTracking,
              onChanged: (value) {
                setState(() {
                  _enableLocationTracking = value;
                });
              },
            ),
            
            // Synchronization Settings
            _buildSectionHeader('Synchronization Settings'),
            _buildDropdownSetting(
              title: 'Sync Frequency',
              value: _syncFrequency,
              items: const [
                'Every 5 minutes',
                'Every 15 minutes',
                'Every 30 minutes',
                'Every hour',
                'Manual only'
              ],
              onChanged: (value) {
                setState(() {
                  _syncFrequency = value!;
                });
              },
            ),
            
            // User Management
            _buildSectionHeader('User Management'),
            ListTile(
              title: const Text('Manage Employees'),
              subtitle: const Text('Add, edit, or remove employee accounts'),
              leading: const Icon(Icons.people),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ManageEmployeesScreen()),
                );
              },
            ),
            ListTile(
              title: const Text('Manage Administrators'),
              subtitle: const Text('Add, edit, or remove administrator accounts'),
              leading: const Icon(Icons.admin_panel_settings),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ManageAdminsScreen()),
                );
              },
            ),
            ListTile(
              title: const Text('Reactivate Account'),
              subtitle: const Text('Enable a previously deactivated account'),
              leading: const Icon(Icons.person),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => _openRoleChooserAndNavigate('reactivate'),
            ),
            ListTile(
              title: const Text('Delete Account'),
              subtitle: const Text('Permanently remove a user account and all associated data'),
              leading: const Icon(Icons.delete_forever),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => _openRoleChooserAndNavigate('delete'),
            ),
            
            // System Settings
            _buildSectionHeader('System'),
            ListTile(
              title: const Text('Backup Data'),
              subtitle: const Text('Export users to JSON (web)'),
              leading: const Icon(Icons.backup),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: _exportUsersWebJson,
            ),
            ListTile(
              title: const Text('Restore Data'),
              subtitle: const Text('Import users from JSON'),
              leading: const Icon(Icons.restore),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: _importUsersJsonPicker,
            ),
            
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _saveSettings,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2688d4),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: const Text('Save Settings'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2688d4),
            ),
          ),
          const Divider(),
        ],
      ),
    );
  }

  Widget _buildSwitchSetting({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return ListTile(
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeThumbColor: const Color(0xFF2688d4),
      ),
    );
  }

  Widget _buildSliderSetting({
    required String title,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String unit,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: value,
                  min: min,
                  max: max,
                  divisions: divisions,
                  activeColor: const Color(0xFF2688d4),
                  onChanged: onChanged,
                ),
              ),
              Text('$value $unit', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(width: 16),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDropdownSetting({
    required String title,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(title),
          ),
          Expanded(
            flex: 3,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(4),
              ),
              child: DropdownButton<String>(
                value: value,
                isExpanded: true,
                underline: Container(),
                items: items.map((item) {
                  return DropdownMenuItem<String>(
                    value: item,
                    child: Text(item),
                  );
                }).toList(),
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportUsersWebJson() async {
    try {
      final users = await _userService.fetchUsers();
      final jsonStr = jsonEncode(users.map((u) => u.toJson()).toList());

      await export_util.saveUsersJson(jsonStr);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(kIsWeb
            ? 'Backup exported: users-backup.json'
            : 'Backup saved as users-backup.json')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Backup failed: $e')),
      );
    }
  }

  Future<void> _importUsersJsonPicker() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No file data captured. Please try again.')),
        );
        return;
      }
      final content = utf8.decode(bytes);
      final res = await _userService.importUsersJson(content);
      if (!mounted) return;
      final imported = res['imported'] ?? 0;
      final updated = res['updated'] ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Import complete: $imported new, $updated updated')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Import failed: $e')),
      );
    }
  }

  void _openRoleChooserAndNavigate(String action) {
    showModalBottomSheet(
      context: context,
    builder: (context) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.people),
              title: const Text('Employees'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ManageEmployeesScreen(
                      showInactiveOnly: action == 'reactivate',
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.admin_panel_settings),
              title: const Text('Administrators'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ManageAdminsScreen(
                      showInactiveOnly: action == 'reactivate',
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      );
    },
  );
}
}