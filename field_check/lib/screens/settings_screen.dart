// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:field_check/screens/login_screen.dart';
import 'package:field_check/services/user_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:field_check/main.dart';
import 'package:field_check/models/user_model.dart';
import 'package:image_picker/image_picker.dart'; // Import image_picker
import 'dart:io'; // Import dart:io for File
import 'package:field_check/screens/map_screen.dart';

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
  File? _pickedImage; // Add _pickedImage variable

  @override
  void initState() {
    super.initState();
    _loadUserPreferences();
    _loadProfile();
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
      File? tempPickedImage =
          _pickedImage; // Use a temporary variable for the dialog

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
                      final picker = ImagePicker();
                      final pickedFile = await picker.pickImage(
                        source: ImageSource.gallery,
                      );
                      if (pickedFile != null) {
                        setState(() {
                          tempPickedImage = File(pickedFile.path);
                        });
                      }
                    },
                    child: CircleAvatar(
                      radius: 40,
                      backgroundColor: const Color(0xFF2688d4),
                      backgroundImage: tempPickedImage != null
                          ? FileImage(tempPickedImage!)
                          : (_profile?.avatarUrl?.isNotEmpty == true
                                ? NetworkImage(_profile!.avatarUrl!)
                                      as ImageProvider
                                : null),
                      child:
                          tempPickedImage == null &&
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
        if (tempPickedImage != null) {
          try {
            newAvatarUrl = await _userService.uploadAvatar(tempPickedImage!);
          } catch (e) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to upload avatar: $e')),
            );
            return; // Stop if avatar upload fails
          }
        }

        await _userService.updateMyProfile(
          name: nameController.text.trim(),
          email: emailController.text.trim(),
          avatarUrl: newAvatarUrl, // Pass the new avatar URL
        );
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Profile updated')));
        await _loadProfile();
        setState(() {
          _pickedImage =
              tempPickedImage; // Update the main _pickedImage after successful save
        });
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Sync service unavailable')));
      return;
    }
    final pending = await syncService.getOfflineData();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Syncing ${pending.length} records...')),
    );
    await syncService.syncOfflineData();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Sync attempt completed'),
        backgroundColor: Colors.green,
      ),
    );
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
                      backgroundImage: _pickedImage != null
                          ? FileImage(_pickedImage!)
                          : (_profile?.avatarUrl?.isNotEmpty == true
                                ? NetworkImage(_profile!.avatarUrl!)
                                      as ImageProvider
                                : null),
                      child:
                          _pickedImage == null &&
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
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _loadingProfile ? '' : (_profile?.role ?? ''),
                            style: const TextStyle(color: Colors.grey),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _loadingProfile ? '' : 'ID: ${_profile?.id ?? '—'}',
                            style: const TextStyle(color: Colors.grey),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _loadingProfile ? '' : (_profile?.email ?? ''),
                            style: const TextStyle(color: Colors.grey),
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
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
                    DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
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
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          const SizedBox(height: 8),

          SwitchListTile(
            title: const Text('Offline Mode'),
            subtitle: const Text('Store attendance data locally when offline'),
            value: _offlineMode,
            onChanged: (value) async {
              setState(() {
                _offlineMode = value;
              });
              await _saveUserPreference('user.offlineMode', value);
            },
          ),

          SwitchListTile(
            title: const Text('Location Tracking'),
            subtitle: const Text(
              'Allow continuous location tracking during work hours',
            ),
            value: _locationTracking,
            onChanged: (value) async {
              setState(() {
                _locationTracking = value;
              });
              await _saveUserPreference('user.locationTrackingEnabled', value);
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
