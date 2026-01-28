// ignore_for_file: use_build_context_synchronously, library_prefixes
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import '../services/user_service.dart';
import 'manage_employees_screen.dart';
import 'manage_admins_screen.dart';
import 'admin_geofence_screen.dart';
import '../utils/export_util_stub.dart'
    if (dart.library.io) '../utils/export_util_io.dart'
    if (dart.library.html) '../utils/export_util_web.dart'
    as export_util;
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../services/settings_service.dart';
import '../services/notification_service.dart';
import 'package:field_check/config/api_config.dart';
import 'package:field_check/utils/app_theme.dart';
import 'package:field_check/widgets/app_page.dart';

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

  static const int _taskMaxActivePerEmployeeMin = 1;
  static const int _taskMaxActivePerEmployeeMax = 50;

  int _taskMaxActivePerEmployee = 10;
  final TextEditingController _taskMaxActivePerEmployeeController =
      TextEditingController(text: '10');

  int _clampTaskMaxActivePerEmployee(int value) {
    return value.clamp(
      _taskMaxActivePerEmployeeMin,
      _taskMaxActivePerEmployeeMax,
    );
  }

  int _normalizeTaskMaxActivePerEmployee(int? parsed) {
    if (parsed == null) return _taskMaxActivePerEmployee;
    return _clampTaskMaxActivePerEmployee(parsed);
  }

  bool _settingsLoadedFromBackend = true;
  bool _isSavingSettings = false;

  final UserService _userService = UserService();
  final SettingsService _settingsService = SettingsService();
  final NotificationService _notificationService = NotificationService();
  final TextEditingController _urgentMessageController =
      TextEditingController();
  bool _isSendingUrgent = false;
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
          final Map update =
              (data.containsKey('key') && data.containsKey('value'))
              ? {data['key']: data['value']}
              : data;
          setState(() {
            if (update.containsKey('geofenceRadius')) {
              _geofenceRadius = (update['geofenceRadius'] as num).toInt();
              prefs.setInt('geofenceRadius', _geofenceRadius);
            }
            if (update.containsKey('allowOfflineMode')) {
              _allowOfflineMode = update['allowOfflineMode'] == true;
              prefs.setBool('allowOfflineMode', _allowOfflineMode);
            }
            if (update.containsKey('requireBeaconVerification')) {
              _requireBeaconVerification =
                  update['requireBeaconVerification'] == true;
              prefs.setBool(
                'requireBeaconVerification',
                _requireBeaconVerification,
              );
            }
            if (update.containsKey('enableLocationTracking')) {
              _enableLocationTracking =
                  update['enableLocationTracking'] == true;
              prefs.setBool('enableLocationTracking', _enableLocationTracking);
            }
            if (update.containsKey('syncFrequency')) {
              _syncFrequency = update['syncFrequency'] as String;
              prefs.setString('syncFrequency', _syncFrequency);
            }

            if (update.containsKey('task.maxActivePerEmployee')) {
              final raw = update['task.maxActivePerEmployee'];
              final parsed = raw is num ? raw.toInt() : int.tryParse('$raw');
              if (parsed != null) {
                final normalized = _normalizeTaskMaxActivePerEmployee(parsed);
                _taskMaxActivePerEmployee = normalized;
                prefs.setInt('task.maxActivePerEmployee', normalized);
                _taskMaxActivePerEmployeeController.text = normalized
                    .toString();
              }
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
      _socket.on(
        'reconnect_attempt',
        (_) => debugPrint('Settings socket reconnect attempt'),
      );
      _socket.on('reconnect', (_) => debugPrint('Settings socket reconnected'));
      _socket.on(
        'reconnect_error',
        (err) => debugPrint('Settings socket reconnect error: $err'),
      );
      _socket.on(
        'reconnect_failed',
        (_) => debugPrint('Settings socket reconnect failed'),
      );
    });
  }

  @override
  void dispose() {
    _socket.dispose();
    _urgentMessageController.dispose();
    _taskMaxActivePerEmployeeController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await _settingsService.fetchSettings();
      if (settings.isNotEmpty) {
        final rawTaskMax = settings['task.maxActivePerEmployee'];
        final parsedTaskMax = rawTaskMax is num
            ? rawTaskMax.toInt()
            : int.tryParse(rawTaskMax?.toString() ?? '');
        final normalizedTaskMax = _normalizeTaskMaxActivePerEmployee(
          parsedTaskMax,
        );
        setState(() {
          _allowOfflineMode = settings['allowOfflineMode'] ?? _allowOfflineMode;
          _requireBeaconVerification =
              settings['requireBeaconVerification'] ??
              _requireBeaconVerification;
          _enableLocationTracking =
              settings['enableLocationTracking'] ?? _enableLocationTracking;
          _geofenceRadius =
              (settings['geofenceRadius'] as num?)?.toInt() ?? _geofenceRadius;
          _syncFrequency = settings['syncFrequency'] ?? _syncFrequency;
          _taskMaxActivePerEmployee = normalizedTaskMax;
          _settingsLoadedFromBackend = true;
        });
        _taskMaxActivePerEmployeeController.text = _taskMaxActivePerEmployee
            .toString();
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('allowOfflineMode', _allowOfflineMode);
        await prefs.setBool(
          'requireBeaconVerification',
          _requireBeaconVerification,
        );
        await prefs.setBool('enableLocationTracking', _enableLocationTracking);
        await prefs.setInt('geofenceRadius', _geofenceRadius);
        await prefs.setString('syncFrequency', _syncFrequency);
        await prefs.setInt(
          'task.maxActivePerEmployee',
          _taskMaxActivePerEmployee,
        );
      } else {
        // Fallback to local if backend not available
        final prefs = await SharedPreferences.getInstance();
        setState(() {
          _allowOfflineMode =
              prefs.getBool('allowOfflineMode') ?? _allowOfflineMode;
          _requireBeaconVerification =
              prefs.getBool('requireBeaconVerification') ??
              _requireBeaconVerification;
          _enableLocationTracking =
              prefs.getBool('enableLocationTracking') ??
              _enableLocationTracking;
          _geofenceRadius = prefs.getInt('geofenceRadius') ?? _geofenceRadius;
          _syncFrequency = prefs.getString('syncFrequency') ?? _syncFrequency;
          _taskMaxActivePerEmployee = _normalizeTaskMaxActivePerEmployee(
            prefs.getInt('task.maxActivePerEmployee'),
          );
          _settingsLoadedFromBackend = false;
        });
        _taskMaxActivePerEmployeeController.text = _taskMaxActivePerEmployee
            .toString();
      }
    } catch (e) {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _allowOfflineMode =
            prefs.getBool('allowOfflineMode') ?? _allowOfflineMode;
        _requireBeaconVerification =
            prefs.getBool('requireBeaconVerification') ??
            _requireBeaconVerification;
        _enableLocationTracking =
            prefs.getBool('enableLocationTracking') ?? _enableLocationTracking;
        _geofenceRadius = prefs.getInt('geofenceRadius') ?? _geofenceRadius;
        _syncFrequency = prefs.getString('syncFrequency') ?? _syncFrequency;
        _taskMaxActivePerEmployee = _normalizeTaskMaxActivePerEmployee(
          prefs.getInt('task.maxActivePerEmployee'),
        );
        _settingsLoadedFromBackend = false;
      });
      _taskMaxActivePerEmployeeController.text = _taskMaxActivePerEmployee
          .toString();
    }
  }

  Future<void> _saveSettings() async {
    if (_isSavingSettings) return;

    final before = _taskMaxActivePerEmployee;
    final normalized = _normalizeTaskMaxActivePerEmployee(
      _taskMaxActivePerEmployee,
    );
    if (normalized != before) {
      setState(() {
        _taskMaxActivePerEmployee = normalized;
      });
      _taskMaxActivePerEmployeeController.text = normalized.toString();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Max active tasks per employee was adjusted to $normalized (allowed: $_taskMaxActivePerEmployeeMin-$_taskMaxActivePerEmployeeMax).',
            ),
          ),
        );
      }
    }

    setState(() {
      _isSavingSettings = true;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('allowOfflineMode', _allowOfflineMode);
    await prefs.setBool(
      'requireBeaconVerification',
      _requireBeaconVerification,
    );
    await prefs.setBool('enableLocationTracking', _enableLocationTracking);
    await prefs.setInt('geofenceRadius', _geofenceRadius);
    await prefs.setString('syncFrequency', _syncFrequency);
    await prefs.setInt('task.maxActivePerEmployee', _taskMaxActivePerEmployee);

    // Push to backend for real-time sync across accounts
    try {
      await _settingsService.updateSettings({
        'allowOfflineMode': _allowOfflineMode,
        'requireBeaconVerification': _requireBeaconVerification,
        'enableLocationTracking': _enableLocationTracking,
        'geofenceRadius': _geofenceRadius.toDouble(),
        'syncFrequency': _syncFrequency,
        'task.maxActivePerEmployee': _taskMaxActivePerEmployee,
      });
      if (!mounted) return;
      setState(() {
        _settingsLoadedFromBackend = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved and synced')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _settingsLoadedFromBackend = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save settings: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _isSavingSettings = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppPage(
      useScaffold: false,
      useSafeArea: false,
      scroll: false,
      padding: EdgeInsets.zero,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppTheme.lg,
          AppTheme.lg,
          AppTheme.lg,
          AppTheme.xl,
        ),
        children: [
          Text(
            'System Settings',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          if (!_settingsLoadedFromBackend) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.orange.withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.cloud_off, color: Colors.orange),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Backend sync unavailable',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'You are viewing local settings. Try again when the backend is reachable.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _loadSettings,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
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
            subtitle:
                'Use Bluetooth beacons for additional location verification',
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
              'Manual only',
            ],
            onChanged: (value) {
              setState(() {
                _syncFrequency = value!;
              });
            },
          ),

          _buildSectionHeader('Task Settings'),
          ListTile(
            title: const Text('Max Active Tasks Per Employee'),
            subtitle: const Text(
              'Controls assignment limits and warnings in Admin Task Management',
            ),
            trailing: SizedBox(
              width: 84,
              child: TextField(
                controller: _taskMaxActivePerEmployeeController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textAlign: TextAlign.center,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) {
                  final parsed = int.tryParse(value);
                  if (parsed == null) return;
                  setState(() {
                    _taskMaxActivePerEmployee = parsed;
                  });
                },
                onSubmitted: (value) {
                  final parsed = int.tryParse(value);
                  final normalized = _normalizeTaskMaxActivePerEmployee(parsed);
                  if (!mounted) return;
                  setState(() {
                    _taskMaxActivePerEmployee = normalized;
                  });
                  _taskMaxActivePerEmployeeController.text = normalized
                      .toString();
                  if (parsed != null && parsed != normalized) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Adjusted to $normalized (allowed: $_taskMaxActivePerEmployeeMin-$_taskMaxActivePerEmployeeMax).',
                        ),
                      ),
                    );
                  }
                },
              ),
            ),
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
                MaterialPageRoute(
                  builder: (_) => const ManageEmployeesScreen(),
                ),
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
            subtitle: const Text(
              'Permanently remove a user account and all associated data',
            ),
            leading: const Icon(Icons.delete_forever),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => _openRoleChooserAndNavigate('delete'),
          ),

          // Urgent Notifications
          _buildSectionHeader('Urgent Notifications'),
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Send urgent SMS to all active employees',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _urgentMessageController,
                    maxLines: 3,
                    maxLength: 320,
                    decoration: const InputDecoration(
                      hintText:
                          'Enter urgent message (e.g., system outage, safety alert)...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton.icon(
                      onPressed:
                          _isSendingUrgent ||
                              _urgentMessageController.text.trim().isEmpty
                          ? null
                          : () async {
                              final text = _urgentMessageController.text.trim();
                              final ok =
                                  await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: const Text('Send Urgent SMS'),
                                      content: Text(
                                        'Send this message to all active employees with a phone number?\n\n$text',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(ctx, false),
                                          child: const Text('Cancel'),
                                        ),
                                        ElevatedButton(
                                          onPressed: () =>
                                              Navigator.pop(ctx, true),
                                          child: const Text('Send'),
                                        ),
                                      ],
                                    ),
                                  ) ??
                                  false;
                              if (!ok) return;

                              setState(() {
                                _isSendingUrgent = true;
                              });
                              try {
                                await _notificationService
                                    .sendUrgentSmsToEmployees(text);
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Urgent SMS sent: "${text.length > 40 ? '${text.substring(0, 40)}...' : text}"',
                                    ),
                                  ),
                                );
                                _urgentMessageController.clear();
                              } catch (e) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Failed to send urgent SMS: $e',
                                    ),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              } finally {
                                if (mounted) {
                                  setState(() {
                                    _isSendingUrgent = false;
                                  });
                                }
                              }
                            },
                      icon: _isSendingUrgent
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.sms_failed_outlined),
                      label: const Text('Send Urgent SMS'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
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
          ListTile(
            title: const Text('Export to Excel'),
            subtitle: const Text('Export users to Excel file'),
            leading: const Icon(Icons.table_chart),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: _exportUsersExcel,
          ),

          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _isSavingSettings ? null : _saveSettings,
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            child: _isSavingSettings
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Text('Save Settings'),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTheme.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: theme.colorScheme.primary,
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
        activeThumbColor: Theme.of(context).colorScheme.primary,
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
                  activeColor: Theme.of(context).colorScheme.primary,
                  onChanged: onChanged,
                ),
              ),
              Text(
                '$value $unit',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
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
          Expanded(flex: 2, child: Text(title)),
          Expanded(
            flex: 3,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.25),
                ),
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
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
        const SnackBar(
          content: Text(
            kIsWeb
                ? 'Backup exported: users-backup.json'
                : 'Backup saved as users-backup.json',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Backup failed: $e')));
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
          const SnackBar(
            content: Text('No file data captured. Please try again.'),
          ),
        );
        return;
      }
      final content = utf8.decode(bytes);
      final res = await _userService.importUsersJson(content);
      if (!mounted) return;
      final imported = res['imported'] ?? 0;
      final updated = res['updated'] ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Import complete: $imported new, $updated updated'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Import failed: $e')));
    }
  }

  Future<void> _exportUsersExcel() async {
    try {
      final users = await _userService.fetchUsers();

      // Create CSV format (Excel compatible)
      final csvBuffer = StringBuffer();
      csvBuffer.writeln('ID,Name,Email,Role,Status');

      for (final user in users) {
        final status = user.isActive ? 'Active' : 'Inactive';
        csvBuffer.writeln(
          '${user.id},${user.name},${user.email},${user.role},$status',
        );
      }

      final csvContent = csvBuffer.toString();

      // Save as CSV (Excel compatible)
      await export_util.saveUsersJson(csvContent);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            kIsWeb
                ? 'Excel export completed: users-export.csv'
                : 'Excel export saved as users-export.csv',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Excel export failed: $e')));
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
