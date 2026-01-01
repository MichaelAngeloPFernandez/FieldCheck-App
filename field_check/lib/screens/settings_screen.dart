// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:field_check/screens/login_screen.dart';
import 'package:field_check/services/user_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:field_check/services/location_sync_service.dart';
import 'package:field_check/main.dart';
import 'package:field_check/models/user_model.dart';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:field_check/screens/map_screen.dart';
import 'package:field_check/utils/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _offlineMode = false;
  bool _locationTracking = true;
  bool _useBluetoothBeacons = false;
  final UserService _userService = UserService();
  UserModel? _profile;
  bool _loadingProfile = true;
  Uint8List? _pickedAvatarBytes;
  String? _pickedAvatarFilename;

  @override
  void initState() {
    super.initState();
    _loadUserPreferences();
    _loadProfile();
  }

  String _formatTime(DateTime time) {
    String two(int v) => v.toString().padLeft(2, '0');
    final local = time.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute;
    final suffix = local.hour >= 12 ? 'PM' : 'AM';
    return '${two(hour)}:${two(minute)} $suffix';
  }

  Future<void> _loadUserPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _offlineMode = prefs.getBool('user.offlineMode') ?? _offlineMode;
      _locationTracking =
          prefs.getBool('user.locationTrackingEnabled') ?? _locationTracking;
      _useBluetoothBeacons =
          prefs.getBool('user.useBluetoothBeacons') ?? _useBluetoothBeacons;
    });
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await _userService.getProfile();
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _loadingProfile = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingProfile = false;
      });
    }
  }

  Future<void> _saveUserPreference(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  Future<void> _logout() async {
    // Best-effort: mark this employee as offline for admin dashboards
    try {
      await _userService.markOffline();
    } catch (_) {}

    await _userService.logout();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
      (route) => false,
    );
  }

  void _showEditProfileDialog() async {
    try {
      final profile = await _userService.getProfile();
      final nameController = TextEditingController(text: profile.name);
      final emailController = TextEditingController(text: profile.email);
      Uint8List? tempPickedAvatarBytes = _pickedAvatarBytes;
      String? tempPickedAvatarFilename = _pickedAvatarFilename;

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Edit Profile'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: () async {
                      final result = await FilePicker.platform.pickFiles(
                        allowMultiple: false,
                        type: FileType.any,
                        withData: true,
                      );

                      final file = result?.files.isNotEmpty == true
                          ? result!.files.first
                          : null;
                      if (file?.bytes != null) {
                        setState(() {
                          tempPickedAvatarBytes = file!.bytes;
                          tempPickedAvatarFilename = file.name;
                        });
                      }
                    },
                    child: CircleAvatar(
                      radius: 40,
                      backgroundColor: const Color(0xFF2688d4),
                      backgroundImage: tempPickedAvatarBytes != null
                          ? MemoryImage(tempPickedAvatarBytes!)
                          : (_profile?.avatarUrl?.isNotEmpty == true
                              ? NetworkImage(_profile!.avatarUrl!)
                                  as ImageProvider
                              : null),
                      child:
                          tempPickedAvatarBytes == null &&
                              (_profile?.avatarUrl?.isEmpty ?? true)
                          ? const Icon(
                              Icons.person,
                              size: 40,
                              color: Colors.white,
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Name'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: emailController,
                    decoration: const InputDecoration(labelText: 'Email'),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        ),
      );
      if (confirmed == true) {
        String? newAvatarUrl;
        if (tempPickedAvatarBytes != null &&
            (tempPickedAvatarFilename ?? '').isNotEmpty) {
          try {
            newAvatarUrl = await _userService.uploadAvatarBytes(
              tempPickedAvatarBytes!,
              tempPickedAvatarFilename!,
            );
          } catch (e) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to upload avatar: $e')),
            );
            return; // Stop if avatar upload fails
          }
        }

        try {
          await _userService.updateMyProfile(
            name: nameController.text.trim(),
            email: emailController.text.trim(),
            avatarUrl: newAvatarUrl, // Pass the new avatar URL
          );
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Profile updated successfully'),
              backgroundColor: Colors.green,
            ),
          );
          await _loadProfile();
          setState(() {
            _pickedAvatarBytes = tempPickedAvatarBytes;
            _pickedAvatarFilename = tempPickedAvatarFilename;
          });
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to update profile: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load profile: $e')));
    }
  }

  void _syncData() async {
    final app = MyApp.of(context);
    final syncService = app?.widget.syncService;
    if (syncService == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sync service unavailable'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      final pending = await syncService.getOfflineData();
      if (pending.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No offline data to sync'),
            backgroundColor: Colors.blue,
          ),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Syncing ${pending.length} records...')),
      );

      await syncService.syncOfflineData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sync completed successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sync failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Settings',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),

            // User profile card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: const Color(0xFF2688d4),
                      backgroundImage: _pickedAvatarBytes != null
                          ? MemoryImage(_pickedAvatarBytes!)
                          : (_profile?.avatarUrl?.isNotEmpty == true
                              ? NetworkImage(_profile!.avatarUrl!)
                                  as ImageProvider
                              : null),
                      child:
                          _pickedAvatarBytes == null &&
                              (_profile?.avatarUrl?.isEmpty ?? true)
                          ? const Icon(
                              Icons.person,
                              size: 30,
                              color: Colors.white,
                            )
                          : null,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _loadingProfile
                                ? 'Loading...'
                                : (_profile?.name ?? '—'),
                            style: AppTheme.headingSm,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _loadingProfile ? '' : (_profile?.role ?? ''),
                            style:
                                AppTheme.bodySm.copyWith(color: AppTheme.textSecondary),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _loadingProfile ? '' : 'ID: ${_profile?.id ?? '—'}',
                            style:
                                AppTheme.bodySm.copyWith(color: AppTheme.textSecondary),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _loadingProfile ? '' : (_profile?.email ?? ''),
                            style:
                                AppTheme.bodySm.copyWith(color: AppTheme.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _showEditProfileDialog,
                icon: const Icon(Icons.edit),
                label: const Text('Edit Profile'),
              ),
            ),

            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const MapScreen()),
                  );
                },
                icon: const Icon(Icons.map),
                label: const Text('Open Map'),
              ),
            ),

            const SizedBox(height: 24),

            // Appearance
            const Text(
              'Appearance',
              style: AppTheme.labelLg,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Expanded(child: Text('Theme Mode')),
                DropdownButton<ThemeMode>(
                  value: MyApp.of(context)?.themeMode ?? ThemeMode.light,
                  items: const [
                    DropdownMenuItem(
                      value: ThemeMode.system,
                      child: Text('System'),
                    ),
                    DropdownMenuItem(
                      value: ThemeMode.light,
                      child: Text('Light'),
                    ),
                    DropdownMenuItem(
                      value: ThemeMode.dark,
                      child: Text('Dark'),
                    ),
                  ],
                  onChanged: (mode) async {
                    if (mode == null) return;
                    await MyApp.of(context)?.setThemeMode(mode);
                    setState(() {});
                  },
                ),
              ],
            ),

            const SizedBox(height: 24),

            // App Settings
            const Text(
              'App Settings',
              style: AppTheme.labelLg,
            ),
            const SizedBox(height: 8),

            SwitchListTile(
              title: const Text('Offline Mode'),
              subtitle: const Text(
                'Store attendance data locally when offline',
              ),
              value: _offlineMode,
              onChanged: (value) async {
                setState(() {
                  _offlineMode = value;
                });
                await _saveUserPreference('user.offlineMode', value);
              },
            ),

            SwitchListTile(
              title: const Text('Share live location with admin'),
              subtitle: ValueListenableBuilder<DateTime?>(
                valueListenable: LocationSyncService().lastSharedListenable,
                builder: (context, value, _) {
                  final last = value == null
                      ? 'Last shared: Never'
                      : 'Last shared: ${_formatTime(value)}';
                  return Text(
                    'Allow admin to see your live location during work hours\n$last',
                  );
                },
              ),
              value: _locationTracking,
              onChanged: (value) async {
                setState(() {
                  _locationTracking = value;
                });
                await _saveUserPreference(
                  'user.locationTrackingEnabled',
                  value,
                );
              },
            ),

            SwitchListTile(
              title: const Text('Use Bluetooth Beacons'),
              subtitle: const Text(
                'Enhance location accuracy with Bluetooth beacons',
              ),
              value: _useBluetoothBeacons,
              onChanged: (value) async {
                setState(() {
                  _useBluetoothBeacons = value;
                });
                await _saveUserPreference('user.useBluetoothBeacons', value);
              },
            ),

            const SizedBox(height: 24),

            // Action buttons
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _syncData,
                icon: const Icon(Icons.sync),
                label: const Text('Sync Data'),
              ),
            ),

            const SizedBox(height: 12),

            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _logout,
                icon: const Icon(Icons.logout),
                label: const Text('Logout'),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
