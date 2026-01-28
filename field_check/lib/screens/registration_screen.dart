import 'package:flutter/material.dart';
import 'package:field_check/main.dart';
import 'package:field_check/services/user_service.dart';
import 'package:field_check/utils/logger.dart';
import 'package:field_check/widgets/app_widgets.dart';
import 'package:field_check/utils/app_theme.dart';
import 'package:field_check/widgets/app_page.dart';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _employeeIdController = TextEditingController();
  bool _isLoading = false;
  String? _error;
  bool _isAdmin =
      false; // simple toggle to mirror previous quick role selection

  final _userService = UserService();

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final role = _isAdmin ? 'admin' : 'employee';
      AppLogger.info(
        AppLogger.tagAuth,
        'Registration attempt for: ${_emailController.text.trim()} (role: $role)',
      );

      await _userService.register(
        _nameController.text.trim(),
        _emailController.text.trim(),
        _passwordController.text,
        role: role,
        employeeId: _isAdmin ? null : _employeeIdController.text.trim(),
        username: _usernameController.text.trim().isEmpty
            ? null
            : _usernameController.text.trim(),
      );
      if (!mounted) return;

      AppLogger.success(
        AppLogger.tagAuth,
        'Registration successful for: ${_emailController.text.trim()}',
      );
      AppWidgets.showSuccessSnackbar(
        context,
        'Registration successful. Check your email to activate your account.',
      );
      Navigator.pop(context);
    } catch (e) {
      AppLogger.error(AppLogger.tagAuth, 'Registration failed', e);
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
      });
      if (mounted) {
        AppWidgets.showErrorSnackbar(context, _error ?? 'Registration failed');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _usernameController.dispose();
    _employeeIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppPage(
      appBarTitle: 'Create Account',
      showBack: true,
      actions: [
        IconButton(
          tooltip: 'Toggle theme',
          icon: Icon(
            Theme.of(context).brightness == Brightness.dark
                ? Icons.light_mode
                : Icons.dark_mode,
          ),
          onPressed: () => MyApp.of(context)?.toggleTheme(),
        ),
      ],
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.lg),
      child: Column(
        children: [
          const SizedBox(height: AppTheme.xl),
          AppWidgets.roundedContainer(
            padding: const EdgeInsets.all(AppTheme.xl),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_error != null)
                    Container(
                      padding: const EdgeInsets.all(AppTheme.md),
                      margin: const EdgeInsets.only(bottom: AppTheme.lg),
                      decoration: BoxDecoration(
                        color: AppTheme.errorColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                        border: Border.all(
                          color: AppTheme.errorColor.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.error_outline,
                            color: AppTheme.errorColor,
                            size: 20,
                          ),
                          const SizedBox(width: AppTheme.md),
                          Expanded(
                            child: Text(
                              _error!,
                              style: AppTheme.bodySm.copyWith(
                                color: AppTheme.errorColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Text('Full Name', style: AppTheme.labelLg),
                  const SizedBox(height: AppTheme.sm),
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      hintText: 'Enter your full name',
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter your full name';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: AppTheme.lg),
                  Text('Username (optional)', style: AppTheme.labelLg),
                  const SizedBox(height: AppTheme.sm),
                  TextFormField(
                    controller: _usernameController,
                    decoration: const InputDecoration(
                      hintText: 'e.g. employee1',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    validator: (value) {
                      if (value != null &&
                          value.isNotEmpty &&
                          value.length < 3) {
                        return 'Username must be at least 3 characters';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: AppTheme.lg),
                  Text('Email', style: AppTheme.labelLg),
                  const SizedBox(height: AppTheme.sm),
                  TextFormField(
                    controller: _emailController,
                    decoration: const InputDecoration(
                      hintText: 'Enter your email',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                    keyboardType: TextInputType.emailAddress,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter your email';
                      }
                      if (!value.contains('@')) {
                        return 'Enter a valid email';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: AppTheme.lg),
                  Text('Password', style: AppTheme.labelLg),
                  const SizedBox(height: AppTheme.sm),
                  TextFormField(
                    controller: _passwordController,
                    decoration: const InputDecoration(
                      hintText: 'Create a password',
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                    obscureText: true,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter a password';
                      }
                      if (value.length < 6) {
                        return 'Password must be at least 6 characters';
                      }
                      return null;
                    },
                  ),
                  if (!_isAdmin) ...[
                    const SizedBox(height: AppTheme.lg),
                    Text('Employee ID', style: AppTheme.labelLg),
                    const SizedBox(height: AppTheme.sm),
                    TextFormField(
                      controller: _employeeIdController,
                      decoration: const InputDecoration(
                        hintText: 'Enter your employee ID',
                        prefixIcon: Icon(Icons.badge_outlined),
                      ),
                      validator: (value) {
                        if (_isAdmin) return null;
                        if (value == null || value.trim().isEmpty) {
                          return 'Employee ID is required';
                        }
                        return null;
                      },
                    ),
                  ],
                  const SizedBox(height: AppTheme.lg),
                  SwitchListTile(
                    value: _isAdmin,
                    title: const Text('Register as Admin'),
                    subtitle: const Text(
                      'Toggle to register admin vs employee',
                    ),
                    onChanged: (val) => setState(() => _isAdmin = val),
                    contentPadding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: AppTheme.xl),
                  AppWidgets.primaryButton(
                    label: 'Create Account',
                    onPressed: _register,
                    isLoading: _isLoading,
                    isEnabled: !_isLoading,
                    icon: Icons.person_add_alt_1,
                    width: double.infinity,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppTheme.xl),
        ],
      ),
    );
  }
}
