// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:field_check/services/user_service.dart';
import 'package:field_check/utils/app_theme.dart';
import 'package:field_check/widgets/app_page.dart';
import 'package:field_check/widgets/app_widgets.dart';

class ResetPasswordScreen extends StatefulWidget {
  final String? token;

  const ResetPasswordScreen({super.key, this.token});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final UserService _userService = UserService();
  final TextEditingController _tokenController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  bool _isLoading = false;
  bool _showPassword = false;
  bool _showConfirmPassword = false;
  String? _errorMessage;
  String? _successMessage;
  int _passwordStrength = 0;

  @override
  void initState() {
    super.initState();
    if (widget.token != null) {
      _tokenController.text = widget.token!;
    }
  }

  @override
  void dispose() {
    _tokenController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _resetPassword() async {
    // Validation
    if (_tokenController.text.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter the reset token from your email';
      });
      return;
    }

    if (_passwordController.text.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter a new password';
      });
      return;
    }

    if (_passwordController.text.length < 8) {
      setState(() {
        _errorMessage = 'Password must be at least 8 characters long';
      });
      return;
    }

    if (!_isStrongPassword(_passwordController.text)) {
      setState(() {
        _errorMessage =
            'Password must contain uppercase, lowercase, number, and special character';
      });
      return;
    }

    if (_passwordController.text != _confirmPasswordController.text) {
      setState(() {
        _errorMessage = 'Passwords do not match';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _userService.resetPassword(
        _tokenController.text,
        _passwordController.text,
      );

      setState(() {
        _isLoading = false;
        _successMessage = 'Password reset successfully!';
      });

      // Show success dialog
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Password Reset Successful'),
          content: const Text(
            'Your password has been reset successfully. '
            'Please log in with your new password.',
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context);
                Navigator.pop(context);
              },
              child: const Text('Go to Login'),
            ),
          ],
        ),
      );
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  bool _isStrongPassword(String password) {
    final hasUppercase = password.contains(RegExp(r'[A-Z]'));
    final hasLowercase = password.contains(RegExp(r'[a-z]'));
    final hasDigit = password.contains(RegExp(r'[0-9]'));
    final hasSpecialChar = password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'));

    return hasUppercase && hasLowercase && hasDigit && hasSpecialChar;
  }

  void _updatePasswordStrength() {
    final password = _passwordController.text;
    int strength = 0;

    if (password.length >= 8) strength++;
    if (password.length >= 12) strength++;
    if (password.contains(RegExp(r'[a-z]')) &&
        password.contains(RegExp(r'[A-Z]'))) {
      strength++;
    }
    if (password.contains(RegExp(r'[0-9]'))) strength++;
    if (password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'))) strength++;

    setState(() {
      _passwordStrength = strength;
    });
  }

  Color _getStrengthColor() {
    switch (_passwordStrength) {
      case 0:
      case 1:
        return Colors.red;
      case 2:
        return Colors.orange;
      case 3:
        return Colors.yellow.shade700;
      case 4:
        return Colors.lightGreen;
      default:
        return Colors.green;
    }
  }

  String _getStrengthText() {
    switch (_passwordStrength) {
      case 0:
      case 1:
        return 'Weak';
      case 2:
        return 'Fair';
      case 3:
        return 'Good';
      case 4:
        return 'Strong';
      default:
        return 'Very Strong';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppPage(
      appBarTitle: 'Create New Password',
      showBack: true,
      child: Column(
        children: [
          const SizedBox(height: AppTheme.xl),
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: AppTheme.accentColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppTheme.radiusXl),
            ),
            child: const Icon(
              Icons.lock_outline,
              size: 56,
              color: AppTheme.accentColor,
            ),
          ),
          const SizedBox(height: AppTheme.xl),
          Text(
            'Create a New Password',
            style: AppTheme.headingMd,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppTheme.md),
          Text(
            'Enter the reset token from your email and create a strong new password.',
            style: AppTheme.bodySm,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppTheme.xl),
          AppWidgets.roundedContainer(
            padding: const EdgeInsets.all(AppTheme.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_errorMessage != null)
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
                            _errorMessage!,
                            style: AppTheme.bodySm.copyWith(
                              color: AppTheme.errorColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_successMessage != null)
                  Container(
                    padding: const EdgeInsets.all(AppTheme.md),
                    margin: const EdgeInsets.only(bottom: AppTheme.lg),
                    decoration: BoxDecoration(
                      color: AppTheme.accentColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                      border: Border.all(
                        color: AppTheme.accentColor.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.check_circle_outline,
                          color: AppTheme.accentColor,
                          size: 20,
                        ),
                        const SizedBox(width: AppTheme.md),
                        Expanded(
                          child: Text(
                            _successMessage!,
                            style: AppTheme.bodySm.copyWith(
                              color: AppTheme.accentColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                Text('Reset Token', style: AppTheme.labelLg),
                const SizedBox(height: AppTheme.sm),
                TextField(
                  controller: _tokenController,
                  enabled: !_isLoading && _successMessage == null,
                  decoration: const InputDecoration(
                    hintText: 'Paste the token from your email',
                    prefixIcon: Icon(Icons.vpn_key_outlined),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: AppTheme.lg),
                Text('New Password', style: AppTheme.labelLg),
                const SizedBox(height: AppTheme.sm),
                TextField(
                  controller: _passwordController,
                  enabled: !_isLoading && _successMessage == null,
                  obscureText: !_showPassword,
                  onChanged: (_) => _updatePasswordStrength(),
                  decoration: InputDecoration(
                    hintText: 'Create a strong password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _showPassword ? Icons.visibility : Icons.visibility_off,
                      ),
                      onPressed: () {
                        setState(() {
                          _showPassword = !_showPassword;
                        });
                      },
                    ),
                  ),
                ),
                if (_passwordController.text.isNotEmpty) ...[
                  const SizedBox(height: AppTheme.lg),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Password Strength', style: AppTheme.labelLg),
                      Text(
                        _getStrengthText(),
                        style: AppTheme.labelLg.copyWith(
                          color: _getStrengthColor(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppTheme.sm),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                    child: LinearProgressIndicator(
                      value: _passwordStrength / 5,
                      minHeight: 6,
                      backgroundColor: Theme.of(
                        context,
                      ).dividerColor.withValues(alpha: 0.35),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        _getStrengthColor(),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppTheme.sm),
                  _buildPasswordRequirement(
                    'At least 8 characters',
                    _passwordController.text.length >= 8,
                  ),
                  _buildPasswordRequirement(
                    'Uppercase and lowercase letters',
                    _passwordController.text.contains(RegExp(r'[a-z]')) &&
                        _passwordController.text.contains(RegExp(r'[A-Z]')),
                  ),
                  _buildPasswordRequirement(
                    'Number (0-9)',
                    _passwordController.text.contains(RegExp(r'[0-9]')),
                  ),
                  _buildPasswordRequirement(
                    'Special character required',
                    _passwordController.text.contains(
                      RegExp(r'[!@#$%^&*(),.?":{}|<>]'),
                    ),
                  ),
                ],
                const SizedBox(height: AppTheme.lg),
                Text('Confirm Password', style: AppTheme.labelLg),
                const SizedBox(height: AppTheme.sm),
                TextField(
                  controller: _confirmPasswordController,
                  enabled: !_isLoading && _successMessage == null,
                  obscureText: !_showConfirmPassword,
                  decoration: InputDecoration(
                    hintText: 'Re-enter your password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _showConfirmPassword
                            ? Icons.visibility
                            : Icons.visibility_off,
                      ),
                      onPressed: () {
                        setState(() {
                          _showConfirmPassword = !_showConfirmPassword;
                        });
                      },
                    ),
                  ),
                ),
                const SizedBox(height: AppTheme.xl),
                AppWidgets.primaryButton(
                  label: 'Reset Password',
                  onPressed: _resetPassword,
                  isLoading: _isLoading,
                  isEnabled: !_isLoading && _successMessage == null,
                  icon: Icons.lock_reset,
                  width: double.infinity,
                ),
                const SizedBox(height: AppTheme.lg),
                Center(
                  child: AppWidgets.textButton(
                    label: 'Cancel',
                    onPressed: _isLoading
                        ? () {}
                        : () => Navigator.pop(context),
                    icon: Icons.close,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppTheme.xl),
        ],
      ),
    );
  }

  Widget _buildPasswordRequirement(String text, bool isMet) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            isMet ? Icons.check_circle : Icons.circle_outlined,
            size: 18,
            color: isMet ? Colors.green : onSurface.withValues(alpha: 0.55),
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isMet ? Colors.green : onSurface.withValues(alpha: 0.75),
            ),
          ),
        ],
      ),
    );
  }
}
