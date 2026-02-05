// ignore_for_file: use_build_context_synchronously, deprecated_member_use
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:field_check/services/user_service.dart';
import 'package:field_check/config/api_config.dart';
import 'package:field_check/services/attendance_service.dart';
import 'package:field_check/models/user_model.dart';
import 'package:field_check/utils/manila_time.dart';

class EmployeeProfileScreen extends StatefulWidget {
  const EmployeeProfileScreen({super.key});

  @override
  State<EmployeeProfileScreen> createState() => _EmployeeProfileScreenState();
}

class _EmployeeProfileScreenState extends State<EmployeeProfileScreen> {
  final UserService _userService = UserService();
  final AttendanceService _attendanceService = AttendanceService();

  UserModel? _userProfile;
  List<AttendanceRecord> _attendanceHistory = [];
  bool _isLoading = true;
  bool _isEditing = false;
  Uint8List? _pickedAvatarBytes;
  String? _pickedAvatarFilename;
  StreamSubscription<UserModel?>? _profileSub;

  late TextEditingController _nameController;
  late TextEditingController _emailController;
  late TextEditingController _usernameController;
  late TextEditingController _phoneController;

  String _normalizeAvatarUrl(String rawPath) {
    final p = rawPath.trim();
    if (p.isEmpty) return p;
    if (p.startsWith('http://') || p.startsWith('https://')) return p;
    if (p.startsWith('/')) return '${ApiConfig.baseUrl}$p';
    return '${ApiConfig.baseUrl}/$p';
  }

  Future<void> _pickAvatar() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        type: FileType.image,
        withData: true,
      );
      final file = result?.files.isNotEmpty == true
          ? result!.files.first
          : null;
      if (file?.bytes == null) return;
      if (!mounted) return;
      setState(() {
        _pickedAvatarBytes = file!.bytes;
        _pickedAvatarFilename = file.name;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to select image: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _emailController = TextEditingController();
    _usernameController = TextEditingController();
    _phoneController = TextEditingController();
    _loadUserData();
    _profileSub = _userService.profileStream.listen((profile) {
      if (!mounted || profile == null) return;
      setState(() {
        _userProfile = profile;
        if (!_isEditing) {
          _nameController.text = profile.name;
          _emailController.text = profile.email;
          _usernameController.text = profile.username ?? '';
          _phoneController.text = profile.phone ?? '';
        }
      });
    });
  }

  @override
  void dispose() {
    _profileSub?.cancel();
    _nameController.dispose();
    _emailController.dispose();
    _usernameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    try {
      final profile = await _userService.getProfile();
      final history = await _attendanceService.getAttendanceHistory();

      if (mounted) {
        setState(() {
          _userProfile = profile;
          _attendanceHistory = history;
          _nameController.text = profile.name;
          _emailController.text = profile.email;
          _usernameController.text = profile.username ?? '';
          _phoneController.text = profile.phone ?? '';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading profile: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _saveProfile() async {
    try {
      String? newAvatarUrl;
      if (_pickedAvatarBytes != null &&
          (_pickedAvatarFilename ?? '').trim().isNotEmpty) {
        try {
          newAvatarUrl = await _userService.uploadAvatarBytes(
            _pickedAvatarBytes!,
            _pickedAvatarFilename!,
          );
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to upload avatar: $e'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
      }

      final updated = await _userService.updateMyProfile(
        name: _nameController.text,
        email: _emailController.text,
        username: _usernameController.text,
        phone: _phoneController.text,
        avatarUrl: newAvatarUrl,
      );

      if (mounted) {
        setState(() {
          _userProfile = updated;
          _isEditing = false;
          _nameController.text = updated.name;
          _emailController.text = updated.email;
          _usernameController.text = updated.username ?? '';
          _phoneController.text = updated.phone ?? '';
          _pickedAvatarBytes = null;
          _pickedAvatarFilename = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile updated successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating profile: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Color _getStatusColorValue(String status) {
    switch (status.toLowerCase()) {
      case 'active':
        return Colors.green;
      case 'pending':
        return Colors.orange;
      case 'suspended':
        return Colors.red;
      default:
        return Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55);
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
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
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

  Widget _buildHeaderPill({required IconData icon, required String label}) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusTile({
    required IconData icon,
    required String title,
    required String message,
    required Color color,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileHeader(UserModel profile) {
    final theme = Theme.of(context);
    final initials = profile.name.trim().isNotEmpty
        ? profile.name
              .trim()
              .split(RegExp(r'\s+'))
              .where((part) => part.isNotEmpty)
              .take(2)
              .map((part) => part.characters.first.toUpperCase())
              .join()
        : '?';
    final avatarUrl = profile.avatarUrl?.trim() ?? '';
    final hasAvatar = _pickedAvatarBytes != null || avatarUrl.isNotEmpty;
    final ImageProvider<Object>? avatarImage = _pickedAvatarBytes != null
        ? MemoryImage(_pickedAvatarBytes!)
        : (avatarUrl.isNotEmpty
              ? NetworkImage(_normalizeAvatarUrl(avatarUrl))
              : null);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primary,
            theme.colorScheme.primaryContainer,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withValues(alpha: 0.28),
            blurRadius: 20,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: _isEditing ? _pickAvatar : null,
                child: Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    CircleAvatar(
                      radius: 38,
                      backgroundColor: Colors.white,
                      backgroundImage: avatarImage,
                      child: hasAvatar
                          ? null
                          : Text(
                              initials,
                              style: theme.textTheme.headlineMedium?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                    ),
                    if (_isEditing)
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 6,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.photo_camera,
                          size: 16,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.name,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      profile.email,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildHeaderPill(
                icon: Icons.badge,
                label: profile.role.toUpperCase(),
              ),
              _buildHeaderPill(
                icon: profile.isVerified ? Icons.verified : Icons.pending,
                label: profile.isVerified
                    ? 'Verified account'
                    : 'Pending verification',
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_userProfile == null) {
      return const Scaffold(
        body: Center(child: Text('Failed to load profile')),
      );
    }

    final employeeCode = (_userProfile!.employeeId ?? '').trim();
    final statusLabel = _userProfile!.isVerified ? 'Active' : 'Pending';
    final statusColor = _getStatusColorValue(
      _userProfile!.isVerified ? 'active' : 'pending',
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Employee Profile',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          IconButton(
            tooltip: _isEditing ? 'Discard changes' : 'Edit profile',
            icon: Icon(_isEditing ? Icons.close : Icons.edit),
            onPressed: () {
              setState(() {
                if (_isEditing) {
                  _nameController.text = _userProfile!.name;
                  _emailController.text = _userProfile!.email;
                  _usernameController.text = _userProfile!.username ?? '';
                  _phoneController.text = _userProfile!.phone ?? '';
                }
                _isEditing = !_isEditing;
              });
            },
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildProfileHeader(_userProfile!),
              const SizedBox(height: 16),
              _buildSurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionHeader(
                      'Account Status',
                      subtitle: 'Verification and access state',
                      trailing: _buildStatusPill(
                        label: statusLabel,
                        color: statusColor,
                        icon: _userProfile!.isVerified
                            ? Icons.verified
                            : Icons.pending,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildStatusTile(
                      icon: _userProfile!.isVerified
                          ? Icons.check_circle
                          : Icons.pending_actions,
                      title: _userProfile!.isVerified
                          ? 'Active and verified'
                          : 'Pending verification',
                      message: _userProfile!.isVerified
                          ? 'Your account is active and ready to use.'
                          : 'Please verify your email to activate your account.',
                      color: statusColor,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _buildSurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionHeader(
                      'Personal Information',
                      subtitle: 'Keep your contact details up to date.',
                      trailing: !_isEditing
                          ? _buildStatusPill(
                              label: employeeCode.isNotEmpty
                                  ? 'ID: $employeeCode'
                                  : 'ID: ${_userProfile!.id.substring(0, 8)}...'
                                        '',
                              color: theme.colorScheme.primary,
                              icon: Icons.badge_outlined,
                            )
                          : null,
                    ),
                    const SizedBox(height: 16),
                    _buildProfileField(
                      'Full Name',
                      _nameController,
                      Icons.person,
                      _isEditing,
                    ),
                    const SizedBox(height: 12),
                    _buildProfileField(
                      'Email',
                      _emailController,
                      Icons.email,
                      _isEditing,
                    ),
                    const SizedBox(height: 12),
                    _buildProfileField(
                      'Username',
                      _usernameController,
                      Icons.account_box,
                      _isEditing,
                    ),
                    const SizedBox(height: 12),
                    _buildProfileField(
                      'Phone (SMS)',
                      _phoneController,
                      Icons.phone,
                      _isEditing,
                    ),
                    if (_isEditing) ...[
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _saveProfile,
                          icon: const Icon(Icons.save_outlined),
                          label: const Text('Save changes'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            textStyle: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _buildSurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionHeader(
                      'Recent Attendance',
                      subtitle: 'Latest check-ins and check-outs.',
                      trailing: _attendanceHistory.isEmpty
                          ? null
                          : _buildStatusPill(
                              label:
                                  '${_attendanceHistory.take(10).length} entries',
                              color: theme.colorScheme.primary,
                              icon: Icons.history,
                            ),
                    ),
                    const SizedBox(height: 12),
                    if (_attendanceHistory.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          vertical: 18,
                          horizontal: 12,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: theme.dividerColor.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              Icons.event_busy,
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.5,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'No attendance records yet',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface.withValues(
                                  alpha: 0.7,
                                ),
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      )
                    else
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _attendanceHistory.take(10).length,
                        itemBuilder: (context, index) {
                          final record = _attendanceHistory[index];
                          return _buildAttendanceRecord(record);
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileField(
    String label,
    TextEditingController controller,
    IconData icon,
    bool isEditing,
  ) {
    final theme = Theme.of(context);
    final baseBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: theme.dividerColor.withValues(alpha: 0.35)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
          ),
        ),
        const SizedBox(height: 6),
        if (isEditing)
          TextField(
            controller: controller,
            decoration: InputDecoration(
              prefixIcon: Icon(icon, size: 18),
              border: baseBorder,
              enabledBorder: baseBorder,
              focusedBorder: baseBorder.copyWith(
                borderSide: BorderSide(color: theme.colorScheme.primary),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
            ),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          )
        else
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: theme.dividerColor.withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    controller.text.isNotEmpty ? controller.text : 'Not set',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: controller.text.isNotEmpty
                          ? theme.colorScheme.onSurface
                          : theme.colorScheme.onSurface.withValues(alpha: 0.55),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildAttendanceRecord(AttendanceRecord record) {
    final theme = Theme.of(context);
    final isCheckIn = record.isCheckIn;
    final accentColor = isCheckIn
        ? Colors.green.shade600
        : theme.colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.dividerColor.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Container(
              height: 40,
              width: 40,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isCheckIn ? Icons.login : Icons.logout,
                color: accentColor,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isCheckIn ? 'Checked In' : 'Checked Out',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    formatManila(record.timestamp, 'yyyy-MM-dd HH:mm:ss'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.75,
                      ),
                    ),
                  ),
                  if (record.geofenceName != null)
                    Text(
                      'Location: ${record.geofenceName}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
            ),
            _buildStatusPill(
              label: isCheckIn ? 'IN' : 'OUT',
              color: accentColor,
            ),
          ],
        ),
      ),
    );
  }
}
