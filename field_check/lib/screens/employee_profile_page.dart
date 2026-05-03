// ignore_for_file: use_build_context_synchronously
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:field_check/services/user_service.dart';
import 'package:field_check/models/user_model.dart';
import 'package:field_check/widgets/app_widgets.dart';

/// Dedicated profile page for comprehensive profile editing
/// Implements Requirements 5.1, 5.2, 5.3, 5.4, 15.2, 15.3, 15.4
class EmployeeProfilePage extends StatefulWidget {
  const EmployeeProfilePage({super.key});

  @override
  State<EmployeeProfilePage> createState() => _EmployeeProfilePageState();
}

class _EmployeeProfilePageState extends State<EmployeeProfilePage> {
  final UserService _userService = UserService();
  final _formKey = GlobalKey<FormState>();

  UserModel? _userProfile;
  bool _isLoading = true;
  bool _hasUnsavedChanges = false;
  bool _isSaving = false;
  Uint8List? _pickedAvatarBytes;
  String? _pickedAvatarFilename;
  StreamSubscription<UserModel?>? _profileSub;

  // Form controllers
  late TextEditingController _nameController;
  late TextEditingController _emailController;
  late TextEditingController _usernameController;
  late TextEditingController _phoneController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _emailController = TextEditingController();
    _usernameController = TextEditingController();
    _phoneController = TextEditingController();

    // Add listeners to track changes
    _nameController.addListener(_onFieldChanged);
    _emailController.addListener(_onFieldChanged);
    _usernameController.addListener(_onFieldChanged);
    _phoneController.addListener(_onFieldChanged);

    _loadUserData();
    _profileSub = _userService.profileStream.listen((profile) {
      if (!mounted || profile == null) return;
      setState(() {
        _userProfile = profile;
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

  void _onFieldChanged() {
    if (_userProfile == null) return;
    final hasChanges = _nameController.text != _userProfile!.name ||
        _emailController.text != _userProfile!.email ||
        _usernameController.text != (_userProfile!.username ?? '') ||
        _phoneController.text != (_userProfile!.phone ?? '') ||
        _pickedAvatarBytes != null;

    if (hasChanges != _hasUnsavedChanges) {
      setState(() {
        _hasUnsavedChanges = hasChanges;
      });
    }
  }

  Future<void> _loadUserData() async {
    try {
      final profile = await _userService.getProfile();

      if (mounted) {
        setState(() {
          _userProfile = profile;
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

  Future<void> _pickAvatar() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        type: FileType.image,
        withData: true,
      );
      final file = result?.files.isNotEmpty == true ? result!.files.first : null;
      if (file?.bytes == null) return;
      if (!mounted) return;
      setState(() {
        _pickedAvatarBytes = file!.bytes;
        _pickedAvatarFilename = file.name;
        _hasUnsavedChanges = true;
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

  /// Navigation handling with unsaved changes warning (Requirement 15.2, 15.4)
  Future<bool> _onWillPop() async {
    if (!_hasUnsavedChanges) {
      return true;
    }

    final shouldPop = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unsaved Changes'),
        content: const Text(
          'You have unsaved changes. Are you sure you want to leave without saving?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('Discard'),
          ),
        ],
      ),
    );

    return shouldPop ?? false;
  }

  /// Profile save functionality (Requirement 5.4)
  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

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
          setState(() {
            _isSaving = false;
          });
          return;
        }
      }

      final updated = await _userService.updateMyProfile(
        name: _nameController.text.trim(),
        email: _emailController.text.trim(),
        username: _usernameController.text.trim(),
        phone: _phoneController.text.trim(),
        avatarUrl: newAvatarUrl,
      );

      if (mounted) {
        setState(() {
          _userProfile = updated;
          _nameController.text = updated.name;
          _emailController.text = updated.email;
          _usernameController.text = updated.username ?? '';
          _phoneController.text = updated.phone ?? '';
          _pickedAvatarBytes = null;
          _pickedAvatarFilename = null;
          _hasUnsavedChanges = false;
          _isSaving = false;
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
        setState(() {
          _isSaving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating profile: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildSectionHeader(String title, {String? subtitle}) {
    final theme = Theme.of(context);
    return Column(
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
                onTap: _pickAvatar,
                child: Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    CircleAvatar(
                      radius: 38,
                      backgroundColor: Colors.white,
                      child: ClipOval(
                        child: SizedBox(
                          width: 76,
                          height: 76,
                          child: _pickedAvatarBytes != null
                              ? Image.memory(
                                  _pickedAvatarBytes!,
                                  fit: BoxFit.cover,
                                )
                              : (hasAvatar
                                    ? AppWidgets.userAvatar(
                                        radius: 38,
                                        avatarUrl: avatarUrl,
                                        initials: initials,
                                        backgroundColor: Colors.white,
                                        foregroundColor: theme.colorScheme.primary,
                                      )
                                    : Center(
                                        child: Text(
                                          initials,
                                          style: theme.textTheme.headlineMedium?.copyWith(
                                            color: theme.colorScheme.primary,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      )),
                        ),
                      ),
                    ),
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
        ],
      ),
    );
  }

  /// Phone number validation (Requirement 5.3)
  String? _validatePhoneNumber(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null; // Phone is optional
    }

    final trimmed = value.trim();
    // Basic phone number validation - allows international formats
    // Accepts: digits, spaces, hyphens, parentheses, and + prefix
    final phoneRegex = RegExp(r'^\+?[\d\s\-\(\)]+$');

    if (!phoneRegex.hasMatch(trimmed)) {
      return 'Please enter a valid phone number';
    }

    // Check minimum length (at least 7 digits)
    final digitsOnly = trimmed.replaceAll(RegExp(r'[^\d]'), '');
    if (digitsOnly.length < 7) {
      return 'Phone number must have at least 7 digits';
    }

    return null;
  }

  Widget _buildProfileField(
    String label,
    TextEditingController controller,
    IconData icon, {
    String? Function(String?)? validator,
    TextInputType? keyboardType,
  }) {
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
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          validator: validator,
          decoration: InputDecoration(
            prefixIcon: Icon(icon, size: 18),
            border: baseBorder,
            enabledBorder: baseBorder,
            focusedBorder: baseBorder.copyWith(
              borderSide: BorderSide(color: theme.colorScheme.primary),
            ),
            errorBorder: baseBorder.copyWith(
              borderSide: const BorderSide(color: Colors.red),
            ),
            focusedErrorBorder: baseBorder.copyWith(
              borderSide: const BorderSide(color: Colors.red, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
          ),
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_userProfile == null) {
      return const Scaffold(
        body: Center(child: Text('Failed to load profile')),
      );
    }

    return PopScope(
      canPop: !_hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'Edit Profile',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          actions: [
            if (_hasUnsavedChanges)
              Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Unsaved',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.orange,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Form(
              key: _formKey,
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
                          'Personal Information',
                          subtitle: 'Keep your contact details up to date.',
                        ),
                        const SizedBox(height: 16),
                        _buildProfileField(
                          'Full Name',
                          _nameController,
                          Icons.person,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Name is required';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        _buildProfileField(
                          'Email',
                          _emailController,
                          Icons.email,
                          keyboardType: TextInputType.emailAddress,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Email is required';
                            }
                            if (!value.contains('@')) {
                              return 'Please enter a valid email';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        _buildProfileField(
                          'Username',
                          _usernameController,
                          Icons.account_box,
                        ),
                        const SizedBox(height: 12),
                        _buildProfileField(
                          'Phone Number (SMS)',
                          _phoneController,
                          Icons.phone,
                          keyboardType: TextInputType.phone,
                          validator: _validatePhoneNumber,
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _isSaving ? null : _saveProfile,
                            icon: _isSaving
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
                                  )
                                : const Icon(Icons.save_outlined),
                            label: Text(_isSaving ? 'Saving...' : 'Save Changes'),
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
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
