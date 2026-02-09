// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:field_check/screens/login_screen.dart';
import 'package:field_check/services/user_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:field_check/services/location_sync_service.dart';
import 'package:field_check/main.dart';
import 'package:field_check/models/user_model.dart';
import 'package:field_check/utils/app_theme.dart';
import 'package:field_check/widgets/app_page.dart';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:field_check/utils/manila_time.dart';
import 'package:field_check/widgets/app_widgets.dart';

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
  String? _profileError;
  bool _isSyncing = false;
  Uint8List? _pickedAvatarBytes;
  String? _pickedAvatarFilename;

  @override
  void initState() {
    super.initState();
    _loadUserPreferences();
    _loadProfile();
  }

  String _formatTime(DateTime time) {
    return formatManilaTimeOfDay(context, time);
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
    setState(() {
      _loadingProfile = true;
      _profileError = null;
    });
    try {
      final profile = await _userService.getProfile();
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _loadingProfile = false;
        _profileError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingProfile = false;
        _profileError = 'Failed to load profile: $e';
      });
    }
  }

  Widget _buildSectionHeader(
    String title, {
    String? subtitle,
    Widget? trailing,
  }) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing,
      ],
    );
  }

  Widget _buildSurfaceCard({
    required Widget child,
    EdgeInsetsGeometry? padding,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: padding ?? const EdgeInsets.all(AppTheme.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildStatusPill({
    required String label,
    required Color color,
    IconData? icon,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingTile({
    required String title,
    String? subtitle,
    Widget? subtitleWidget,
    required Widget trailing,
    IconData? icon,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.md,
        vertical: AppTheme.md,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Container(
              padding: const EdgeInsets.all(AppTheme.sm),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 18, color: theme.colorScheme.primary),
            ),
            const SizedBox(width: AppTheme.md),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (subtitleWidget != null) ...[
                  const SizedBox(height: AppTheme.sm),
                  DefaultTextStyle(
                    style:
                        theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.75,
                          ),
                          fontWeight: FontWeight.w600,
                        ) ??
                        const TextStyle(),
                    child: subtitleWidget,
                  ),
                ] else if (subtitle != null) ...[
                  const SizedBox(height: AppTheme.sm),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.75,
                      ),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppTheme.md),
          Align(alignment: Alignment.centerRight, child: trailing),
        ],
      ),
    );
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
                      child: tempPickedAvatarBytes != null
                          ? ClipOval(
                              child: Image.memory(
                                tempPickedAvatarBytes!,
                                width: 80,
                                height: 80,
                                fit: BoxFit.cover,
                              ),
                            )
                          : AppWidgets.userAvatar(
                              radius: 40,
                              avatarUrl: _profile?.avatarUrl,
                              initials: (_profile?.name ?? '').trim().isNotEmpty
                                  ? _profile!.name.characters.first
                                        .toUpperCase()
                                  : '?',
                              fallbackIcon: Icons.person,
                              backgroundColor: const Color(0xFF2688d4),
                            ),
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
    if (_isSyncing) return;
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
      setState(() {
        _isSyncing = true;
      });
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

      final remaining = await syncService.getOfflineData();
      final syncedCount = pending.length - remaining.length;

      if (mounted) {
        if (syncedCount > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Sync completed: $syncedCount synced, ${remaining.length} remaining',
              ),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Sync finished, but no records were synced (${remaining.length} still pending)',
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }
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
    } finally {
      if (mounted) {
        setState(() {
          _isSyncing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profileRole = _profile?.role.toUpperCase();
    final profileId = _profile?.role == 'admin'
        ? (_profile?.id ?? '—')
        : (_profile?.employeeId ?? _profile?.id ?? '—');
    return AppPage(
      useScaffold: false,
      useSafeArea: false,
      padding: const EdgeInsets.fromLTRB(
        AppTheme.lg,
        AppTheme.lg,
        AppTheme.lg,
        AppTheme.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionHeader(
                  'Profile',
                  subtitle: 'Your account details and access status.',
                  trailing: profileRole == null
                      ? null
                      : _buildStatusPill(
                          label: profileRole,
                          color: theme.colorScheme.primary,
                          icon: Icons.badge_outlined,
                        ),
                ),
                const SizedBox(height: AppTheme.lg),
                Row(
                  children: [
                    CircleAvatar(
                      radius: 32,
                      backgroundColor: theme.colorScheme.primary,
                      child: _pickedAvatarBytes != null
                          ? ClipOval(
                              child: Image.memory(
                                _pickedAvatarBytes!,
                                width: 64,
                                height: 64,
                                fit: BoxFit.cover,
                              ),
                            )
                          : AppWidgets.userAvatar(
                              radius: 32,
                              avatarUrl: _profile?.avatarUrl,
                              initials: (_profile?.name ?? '').trim().isNotEmpty
                                  ? _profile!.name.characters.first
                                        .toUpperCase()
                                  : '?',
                              fallbackIcon: Icons.person,
                              backgroundColor: theme.colorScheme.primary,
                            ),
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
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (_profileError != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              _profileError!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.error,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              onPressed: _loadProfile,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Retry'),
                            ),
                          ],
                          if (_profileError == null) ...[
                            const SizedBox(height: 6),
                            Text(
                              _loadingProfile ? '' : (_profile?.email ?? ''),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface.withValues(
                                  alpha: 0.75,
                                ),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _loadingProfile ? '' : 'ID: $profileId',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface.withValues(
                                  alpha: 0.7,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppTheme.lg),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _showEditProfileDialog,
                    icon: const Icon(Icons.edit),
                    label: const Text('Edit profile'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      textStyle: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppTheme.md),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pushNamedAndRemoveUntil(
                        '/dashboard',
                        (route) => false,
                        arguments: 1,
                      );
                    },
                    icon: const Icon(Icons.map),
                    label: const Text('Open map'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppTheme.lg),
          _buildSurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionHeader(
                  'Appearance',
                  subtitle: 'Customize how the app looks.',
                ),
                const SizedBox(height: AppTheme.md),
                _buildSettingTile(
                  title: 'Theme mode',
                  subtitle: 'Choose light, dark, or system default.',
                  icon: Icons.brightness_6_outlined,
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTheme.md,
                      vertical: AppTheme.sm,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                      border: Border.all(
                        color: theme.colorScheme.primary.withValues(
                          alpha: 0.35,
                        ),
                      ),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<ThemeMode>(
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
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppTheme.lg),
          _buildSurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionHeader(
                  'App Settings',
                  subtitle: 'Control tracking, offline, and device options.',
                ),
                const SizedBox(height: AppTheme.md),
                _buildSettingTile(
                  title: 'Offline mode',
                  subtitle: 'Store attendance data locally when offline.',
                  icon: Icons.cloud_off_outlined,
                  trailing: Switch.adaptive(
                    value: _offlineMode,
                    onChanged: (value) async {
                      setState(() {
                        _offlineMode = value;
                      });
                      await _saveUserPreference('user.offlineMode', value);
                    },
                  ),
                ),
                const SizedBox(height: AppTheme.md),
                _buildSettingTile(
                  title: 'Live location sharing',
                  subtitleWidget: ValueListenableBuilder<DateTime?>(
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
                  icon: Icons.location_searching,
                  trailing: Switch.adaptive(
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
                ),
                const SizedBox(height: AppTheme.md),
                _buildSettingTile(
                  title: 'Bluetooth beacons',
                  subtitle: 'Enhance location accuracy with Bluetooth beacons.',
                  icon: Icons.bluetooth_searching,
                  trailing: Switch.adaptive(
                    value: _useBluetoothBeacons,
                    onChanged: (value) async {
                      setState(() {
                        _useBluetoothBeacons = value;
                      });
                      await _saveUserPreference(
                        'user.useBluetoothBeacons',
                        value,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppTheme.lg),
          _buildSurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionHeader(
                  'Sync & Account',
                  subtitle: 'Keep your data updated and secure.',
                ),
                const SizedBox(height: AppTheme.md),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _isSyncing ? null : _syncData,
                    icon: _isSyncing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.sync),
                    label: const Text('Sync data'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      textStyle: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppTheme.md),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _logout,
                    icon: const Icon(Icons.logout),
                    label: const Text('Logout'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
