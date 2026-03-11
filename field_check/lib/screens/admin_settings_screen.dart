// ignore_for_file: use_build_context_synchronously, library_prefixes
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import '../services/user_service.dart';
import '../models/user_model.dart';
import 'manage_employees_screen.dart';
import 'manage_admins_screen.dart';
import 'admin_geofence_screen.dart';
import '../utils/export_util_stub.dart'
    if (dart.library.io) '../utils/export_util_io.dart'
    if (dart.library.html) '../utils/export_util_web.dart'
    as export_util;
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../services/settings_service.dart';
import 'package:field_check/services/notification_service.dart';
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

  static const int _taskMaxActivePerEmployee = 3;

  bool _settingsLoadedFromBackend = true;
  bool _isSavingSettings = false;

  bool _smsTaskAssignmentEnabled = true;
  bool _smsAttendanceEnabled = true;
  bool _smsOverdueEnabled = true;

  final UserService _userService = UserService();
  final SettingsService _settingsService = SettingsService();
  final NotificationService _notificationService = NotificationService();
  final TextEditingController _urgentMessageController =
      TextEditingController();
  bool _isSendingUrgent = false;

  String _urgentRecipientMode = 'all';

  List<UserModel> _urgentEmployees = <UserModel>[];
  UserModel? _selectedUrgentEmployee;
  bool _isLoadingUrgentEmployees = false;
  late io.Socket _socket;

  int _selectedSectionIndex = 0;

  static const List<(String label, IconData icon)> _sections = [
    ('General', Icons.tune),
    ('Geofence', Icons.location_on_outlined),
    ('Users', Icons.group_outlined),
    ('System', Icons.settings_outlined),
    ('Notifications', Icons.notifications_active_outlined),
  ];

  @override
  void initState() {
    super.initState();
    _initSocket();
    _loadSettings();
    _loadUrgentEmployees();
  }

  Future<void> _loadUrgentEmployees() async {
    if (_isLoadingUrgentEmployees) return;
    setState(() {
      _isLoadingUrgentEmployees = true;
    });

    try {
      final employees = await _userService.fetchEmployees();
      if (!mounted) return;
      employees.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      setState(() {
        _urgentEmployees = employees;
        if (_selectedUrgentEmployee != null) {
          final match = employees
              .where((e) => e.id == _selectedUrgentEmployee!.id)
              .cast<UserModel?>()
              .firstWhere((_) => true, orElse: () => null);
          _selectedUrgentEmployee = match;
        }
        _isLoadingUrgentEmployees = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _urgentEmployees = <UserModel>[];
        _selectedUrgentEmployee = null;
        _isLoadingUrgentEmployees = false;
      });
    }
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
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await _settingsService.fetchSettings();
      if (settings.isNotEmpty) {
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
          _settingsLoadedFromBackend = true;

          _smsTaskAssignmentEnabled =
              settings[SettingsService.smsTaskAssignmentEnabledKey] ??
              _smsTaskAssignmentEnabled;
          _smsAttendanceEnabled =
              settings[SettingsService.smsAttendanceEnabledKey] ??
              _smsAttendanceEnabled;
          _smsOverdueEnabled =
              settings[SettingsService.smsOverdueEnabledKey] ??
              _smsOverdueEnabled;
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
          _settingsLoadedFromBackend = false;
        });
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
        _settingsLoadedFromBackend = false;
      });
    }
  }

  Future<void> _saveSettings() async {
    if (_isSavingSettings) return;

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
    final windowWidth = MediaQuery.sizeOf(context).width;

    return AppPage(
      useScaffold: false,
      useSafeArea: false,
      scroll: false,
      padding: EdgeInsets.zero,
      maxContentWidth: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxWidth;
          final contentWidth = maxWidth;
          final isDesktop = windowWidth >= 980;

          const gap = 16.0;
          const sidebarWidth = 280.0;
          final rightWidth = isDesktop
              ? (contentWidth - sidebarWidth - gap)
              : contentWidth;

          Widget cardShell({
            required String title,
            required IconData icon,
            required List<Widget> children,
          }) {
            return Card(
              elevation: 1,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: theme.brightness == Brightness.dark ? 0.5 : 0.35,
                  ),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withValues(
                              alpha: theme.brightness == Brightness.dark
                                  ? 0.22
                                  : 0.10,
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(icon, color: theme.colorScheme.primary),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            title,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ...children,
                  ],
                ),
              ),
            );
          }

          Widget sectionHeader(String title, {String? subtitle}) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.74,
                      ),
                    ),
                  ),
                ],
              ],
            );
          }

          Widget buildBackendSyncBanner() {
            if (_settingsLoadedFromBackend) return const SizedBox.shrink();
            return Container(
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
                          style: theme.textTheme.bodySmall,
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
            );
          }

          Widget buildSaveButton({required bool compact}) {
            return FilledButton.icon(
              onPressed: _isSavingSettings ? null : _saveSettings,
              icon: _isSavingSettings
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.save),
              label: Text(compact ? 'Save' : 'Save Settings'),
            );
          }

          Widget buildSidebar() {
            return Card(
              elevation: 1,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: theme.brightness == Brightness.dark ? 0.5 : 0.35,
                  ),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
                      child: Text(
                        'Settings',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    const SizedBox(height: 6),
                    ...List.generate(_sections.length, (i) {
                      final s = _sections[i];
                      final selected = _selectedSectionIndex == i;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: ListTile(
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          selected: selected,
                          selectedTileColor: theme.colorScheme.primary
                              .withValues(alpha: 0.10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          leading: Icon(
                            s.$2,
                            color: selected
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurface.withValues(
                                    alpha: 0.74,
                                  ),
                          ),
                          title: Text(
                            s.$1,
                            style: TextStyle(
                              fontWeight: selected
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                            ),
                          ),
                          onTap: () {
                            setState(() {
                              _selectedSectionIndex = i;
                            });
                          },
                        ),
                      );
                    }),
                  ],
                ),
              ),
            );
          }

          Widget buildGeneralSection() {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                sectionHeader(
                  'General',
                  subtitle:
                      'Core behavior for verification and synchronization.',
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: cardShell(
                    title: 'Verification Settings',
                    icon: Icons.verified_user,
                    children: [
                      _buildSwitchSetting(
                        title: 'Allow Offline Mode',
                        subtitle:
                            'Employees can check in/out without internet connection',
                        value: _allowOfflineMode,
                        onChanged: (value) {
                          setState(() {
                            _allowOfflineMode = value;
                            if (value) {
                              _enableLocationTracking = true;
                            }
                          });
                        },
                      ),
                      const Divider(height: 18),
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
                      const Divider(height: 18),
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
                    ],
                  ),
                ),
                const SizedBox(height: gap),
                SizedBox(
                  width: double.infinity,
                  child: cardShell(
                    title: 'Synchronization Settings',
                    icon: Icons.sync,
                    children: [
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
                    ],
                  ),
                ),
              ],
            );
          }

          Widget buildGeofenceSection() {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                sectionHeader(
                  'Geofence',
                  subtitle:
                      'Radius defaults and geofence management shortcuts.',
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: cardShell(
                    title: 'Geofence Settings',
                    icon: Icons.location_on,
                    children: [
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
                      const Divider(height: 18),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Manage Geofences'),
                        subtitle: const Text(
                          'Add, edit, enable/disable geofence areas',
                        ),
                        leading: const Icon(Icons.map),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const AdminGeofenceScreen(),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            );
          }

          Widget buildUsersSection() {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                sectionHeader(
                  'Users',
                  subtitle:
                      'Account administration shortcuts for employees and admins.',
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: cardShell(
                    title: 'User Management',
                    icon: Icons.group,
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Manage Employees'),
                        subtitle: const Text(
                          'Add, edit, or remove employee accounts',
                        ),
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
                      const Divider(height: 18),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Manage Administrators'),
                        subtitle: const Text(
                          'Add, edit, or remove administrator accounts',
                        ),
                        leading: const Icon(Icons.admin_panel_settings),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ManageAdminsScreen(),
                            ),
                          );
                        },
                      ),
                      const Divider(height: 18),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Reactivate Account'),
                        subtitle: const Text(
                          'Enable a previously deactivated account',
                        ),
                        leading: const Icon(Icons.person),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: () => _openRoleChooserAndNavigate('reactivate'),
                      ),
                      const Divider(height: 18),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Delete Account'),
                        subtitle: const Text(
                          'Permanently remove a user account and all associated data',
                        ),
                        leading: const Icon(Icons.delete_forever),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: () => _openRoleChooserAndNavigate('delete'),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }

          Widget buildSystemSection() {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                sectionHeader(
                  'System',
                  subtitle: 'Backup, restore, and export utilities.',
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: cardShell(
                    title: 'System',
                    icon: Icons.settings,
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Backup Data'),
                        subtitle: const Text('Export users to JSON (web)'),
                        leading: const Icon(Icons.backup),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: _exportUsersWebJson,
                      ),
                      const Divider(height: 18),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Restore Data'),
                        subtitle: const Text('Import users from JSON'),
                        leading: const Icon(Icons.restore),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: _importUsersJsonPicker,
                      ),
                      const Divider(height: 18),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Export to Excel'),
                        subtitle: const Text('Export users to Excel file'),
                        leading: const Icon(Icons.table_chart),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: _exportUsersExcel,
                      ),
                    ],
                  ),
                ),
              ],
            );
          }

          Widget buildNotificationsSection() {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                sectionHeader(
                  'Notifications',
                  subtitle: 'Send urgent announcements to active employees.',
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: cardShell(
                    title: 'In-app Notifications',
                    icon: Icons.notifications_active_outlined,
                    children: const [
                      Text(
                        'Urgent messages are delivered inside the app (notification bell). Employees must open the app to see them.',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: cardShell(
                    title: 'Urgent Notifications',
                    icon: Icons.sms_failed_outlined,
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: _urgentRecipientMode,
                        isExpanded: true,
                        items: const [
                          DropdownMenuItem(
                            value: 'single_employee',
                            child: Text('Single employee'),
                          ),
                          DropdownMenuItem(
                            value: 'all',
                            child: Text('All active employees'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() {
                            _urgentRecipientMode = value;
                            if (_urgentRecipientMode != 'single_employee') {
                              _selectedUrgentEmployee = null;
                            }
                          });
                        },
                        decoration: const InputDecoration(
                          labelText: 'Recipients',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (_urgentRecipientMode == 'single_employee') ...[
                        DropdownButtonFormField<UserModel>(
                          initialValue: _selectedUrgentEmployee,
                          isExpanded: true,
                          items: _urgentEmployees
                              .map(
                                (e) => DropdownMenuItem<UserModel>(
                                  value: e,
                                  child: Text(
                                    e.name,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: _isLoadingUrgentEmployees
                              ? null
                              : (value) {
                                  setState(() {
                                    _selectedUrgentEmployee = value;
                                  });
                                },
                          decoration: InputDecoration(
                            labelText: 'Recipient employee (for SMS composer)',
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              tooltip: 'Refresh employee list',
                              onPressed: _isLoadingUrgentEmployees
                                  ? null
                                  : _loadUrgentEmployees,
                              icon: _isLoadingUrgentEmployees
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.refresh),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
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
                                  _urgentMessageController.text
                                      .trim()
                                      .isEmpty ||
                                  (_urgentRecipientMode == 'single_employee' &&
                                      _selectedUrgentEmployee == null)
                              ? null
                              : () async {
                                  final text = _urgentMessageController.text
                                      .trim();
                                  setState(() {
                                    _isSendingUrgent = true;
                                  });
                                  try {
                                    final employeeId =
                                        _urgentRecipientMode ==
                                            'single_employee'
                                        ? _selectedUrgentEmployee?.id
                                        : null;

                                    final result = await _notificationService
                                        .sendUrgentInAppOnly(
                                          message: text,
                                          recipientMode: _urgentRecipientMode,
                                          employeeId: employeeId,
                                        );

                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          (result.isNotEmpty)
                                              ? 'Urgent notification sent: ${jsonEncode(result)}'
                                              : 'Urgent notification sent.',
                                        ),
                                      ),
                                    );
                                    _urgentMessageController.clear();
                                  } catch (e) {
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Failed to send urgent notification: $e',
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
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
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
              ],
            );
          }

          Widget buildRightPanel() {
            final selectedLabel = _sections[_selectedSectionIndex].$1;
            return SizedBox(
              width: rightWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          isDesktop ? 'System Settings' : selectedLabel,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      if (isDesktop) buildSaveButton(compact: true),
                    ],
                  ),
                  const SizedBox(height: 12),
                  buildBackendSyncBanner(),
                  const SizedBox(height: 16),
                  if (!isDesktop) ...[
                    DropdownButtonFormField<int>(
                      initialValue: _selectedSectionIndex,
                      items: List.generate(
                        _sections.length,
                        (i) => DropdownMenuItem(
                          value: i,
                          child: Row(
                            children: [
                              Icon(_sections[i].$2, size: 18),
                              const SizedBox(width: 10),
                              Text(_sections[i].$1),
                            ],
                          ),
                        ),
                      ),
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() {
                          _selectedSectionIndex = v;
                        });
                      },
                      decoration: const InputDecoration(
                        labelText: 'Section',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (_selectedSectionIndex == 0) buildGeneralSection(),
                  if (_selectedSectionIndex == 1) buildGeofenceSection(),
                  if (_selectedSectionIndex == 2) buildUsersSection(),
                  if (_selectedSectionIndex == 3) buildSystemSection(),
                  if (_selectedSectionIndex == 4) buildNotificationsSection(),
                  if (!isDesktop) ...[
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: buildSaveButton(compact: false),
                    ),
                  ],
                ],
              ),
            );
          }

          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: contentWidth),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppTheme.lg,
                  AppTheme.lg,
                  AppTheme.lg,
                  AppTheme.xl,
                ),
                child: isDesktop
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(width: sidebarWidth, child: buildSidebar()),
                          const SizedBox(width: gap),
                          Expanded(child: buildRightPanel()),
                        ],
                      )
                    : buildRightPanel(),
              ),
            ),
          );
        },
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
