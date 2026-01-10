import 'package:flutter/material.dart';
import 'package:field_check/main.dart';
import 'package:field_check/services/user_service.dart';
import 'package:field_check/utils/logger.dart';
import 'package:field_check/widgets/app_widgets.dart';

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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Account'),
        actions: [
          IconButton(
            tooltip: 'Toggle theme',
            icon: Icon(
              Theme.of(context).brightness == Brightness.dark
                  ? Icons.dark_mode
                  : Icons.light_mode,
            ),
            onPressed: () => MyApp.of(context)?.toggleTheme(),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Card(
            elevation: 8,
            margin: const EdgeInsets.symmetric(vertical: 12),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12.0),
                        child: Text(
                          _error!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Full Name',
                        prefixIcon: Icon(Icons.badge),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter your full name';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _usernameController,
                      decoration: const InputDecoration(
                        labelText: 'Username (optional)',
                        hintText: 'e.g. employee1',
                        prefixIcon: Icon(Icons.person),
                      ),
                      validator: (value) {
                        // optional; if provided, enforce minimum length
                        if (value != null &&
                            value.isNotEmpty &&
                            value.length < 3) {
                          return 'Username must be at least 3 characters';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _emailController,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.email),
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
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordController,
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        prefixIcon: Icon(Icons.lock),
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
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _employeeIdController,
                        decoration: const InputDecoration(
                          labelText: 'Employee ID',
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
                    const SizedBox(height: 16),
                    SwitchListTile(
                      value: _isAdmin,
                      title: const Text('Register as Admin'),
                      subtitle: const Text(
                        'Toggle to register admin vs employee',
                      ),
                      onChanged: (val) => setState(() => _isAdmin = val),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _register,
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Create Account'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
