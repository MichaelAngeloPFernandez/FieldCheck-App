// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:field_check/main.dart';
import 'package:field_check/screens/dashboard_screen.dart';
import 'package:field_check/services/user_service.dart';
import 'package:field_check/services/realtime_service.dart';
import 'package:field_check/services/location_sync_service.dart';
import 'package:field_check/services/employee_location_service.dart';
import 'package:field_check/utils/app_theme.dart';
import 'package:field_check/utils/logger.dart';
import 'package:field_check/widgets/app_widgets.dart';

class EmployeeLoginScreen extends StatefulWidget {
  const EmployeeLoginScreen({super.key});

  @override
  State<EmployeeLoginScreen> createState() => _EmployeeLoginScreenState();
}

class _EmployeeLoginScreenState extends State<EmployeeLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _error;

  final _userService = UserService();

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final user = _usernameController.text.trim();
      final pass = _passwordController.text;

      AppLogger.info(
        AppLogger.tagAuth,
        'Employee login attempt for user: $user',
      );

      // Ensure we don't reuse stale sockets/caches from a previous login in the same app session.
      try {
        RealtimeService().reset();
      } catch (_) {}
      try {
        LocationSyncService().dispose();
      } catch (_) {}
      try {
        EmployeeLocationService().reset();
      } catch (_) {}

      final loggedIn = await _userService.loginIdentifier(user, pass);
      if (!mounted) return;

      if (loggedIn.role.toLowerCase() == 'admin') {
        AppWidgets.showErrorSnackbar(
          context,
          'This login is for employees only.',
        );
        await _userService.logout();
        if (!mounted) return;
        setState(() {
          _error = 'This login is for employees only.';
        });
        return;
      }

      AppLogger.success(
        AppLogger.tagAuth,
        'Employee login successful for user: $user',
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const DashboardScreen()),
      );
    } catch (e) {
      AppLogger.error(AppLogger.tagAuth, 'Login failed', e);
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
      });
      if (mounted) {
        AppWidgets.showErrorSnackbar(context, _error ?? 'Login failed');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _backToLanding() {
    Navigator.of(context).pushNamedAndRemoveUntil('/landing', (r) => false);
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        leading: IconButton(
          tooltip: 'Back to Landing',
          icon: const Icon(Icons.arrow_back),
          onPressed: _backToLanding,
        ),
        title: const Text('Employee Login'),
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
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.lg),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(height: MediaQuery.of(context).size.height * 0.08),
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryLight.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(AppTheme.radiusXl),
                  ),
                  child: const Icon(
                    Icons.badge_outlined,
                    size: 60,
                    color: AppTheme.primaryColor,
                  ),
                ),
                const SizedBox(height: AppTheme.xl),
                Text(
                  'FieldCheck',
                  style: AppTheme.headingXl.copyWith(
                    color: AppTheme.primaryColor,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppTheme.md),
                Text(
                  'Employee Access',
                  textAlign: TextAlign.center,
                  style: AppTheme.bodyMd.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
                SizedBox(height: MediaQuery.of(context).size.height * 0.06),
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
                              color: AppTheme.errorColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(
                                AppTheme.radiusMd,
                              ),
                              border: Border.all(
                                color: AppTheme.errorColor.withOpacity(0.3),
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
                        Text('Username or Email', style: AppTheme.labelLg),
                        const SizedBox(height: AppTheme.sm),
                        TextFormField(
                          controller: _usernameController,
                          decoration: const InputDecoration(
                            hintText: 'Enter your username or email',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                          keyboardType: TextInputType.emailAddress,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter your username or email';
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
                            hintText: 'Enter your password',
                            prefixIcon: Icon(Icons.lock_outline),
                          ),
                          obscureText: true,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter your password';
                            }
                            if (value.length < 4) {
                              return 'Password must be at least 4 characters';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: AppTheme.xl),
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton.icon(
                            onPressed: _isLoading ? null : _login,
                            icon: _isLoading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
                                  )
                                : const Icon(Icons.login),
                            label: Text(
                              _isLoading ? 'Logging in...' : 'Login',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppTheme.lg),
                        Center(
                          child: AppWidgets.textButton(
                            label: 'Forgot Password?',
                            onPressed: () {
                              Navigator.of(
                                context,
                              ).pushNamed('/forgot-password');
                            },
                            icon: Icons.help_outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: MediaQuery.of(context).size.height * 0.08),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
