// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:field_check/services/user_service.dart';
import 'package:field_check/utils/app_theme.dart';
import 'package:field_check/widgets/app_page.dart';
import 'package:field_check/widgets/app_widgets.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final UserService _userService = UserService();
  final TextEditingController _emailController = TextEditingController();

  bool _isLoading = false;
  bool _emailSent = false;
  String? _errorMessage;
  String? _successMessage;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _requestPasswordReset() async {
    if (_emailController.text.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter your email address';
      });
      return;
    }

    if (!_isValidEmail(_emailController.text)) {
      setState(() {
        _errorMessage = 'Please enter a valid email address';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _userService.forgotPassword(_emailController.text);

      setState(() {
        _isLoading = false;
        _emailSent = true;
        _successMessage =
            'Password reset link has been sent to your email. Please check your inbox and spam folder.';
      });

      // Show success dialog
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Email Sent Successfully'),
          content: const Text(
            'A password reset link has been sent to your email address. '
            'Please follow the link in the email to reset your password. '
            'The link will expire in 1 hour for security.',
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context);
              },
              child: const Text('Back to Login'),
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

  bool _isValidEmail(String email) {
    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    );
    return emailRegex.hasMatch(email);
  }

  @override
  Widget build(BuildContext context) {
    return AppPage(
      appBarTitle: 'Reset Password',
      showBack: true,
      child: Column(
        children: [
          const SizedBox(height: AppTheme.xl),
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: AppTheme.primaryLight.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppTheme.radiusXl),
            ),
            child: const Icon(
              Icons.lock_reset,
              size: 56,
              color: AppTheme.primaryColor,
            ),
          ),
          const SizedBox(height: AppTheme.xl),
          Text(
            'Reset Your Password',
            style: AppTheme.headingMd,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppTheme.md),
          Text(
            "Enter your email and we'll send a reset link. The link expires in 1 hour.",
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
                Text('Email Address', style: AppTheme.labelLg),
                const SizedBox(height: AppTheme.sm),
                TextField(
                  controller: _emailController,
                  enabled: !_emailSent && !_isLoading,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    hintText: 'Enter your email',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                ),
                const SizedBox(height: AppTheme.xl),
                AppWidgets.primaryButton(
                  label: 'Send Reset Link',
                  onPressed: _requestPasswordReset,
                  isLoading: _isLoading,
                  isEnabled: !_isLoading && !_emailSent,
                  icon: Icons.send,
                  width: double.infinity,
                ),
                const SizedBox(height: AppTheme.lg),
                Center(
                  child: AppWidgets.textButton(
                    label: 'Back to Login',
                    onPressed: _isLoading
                        ? () {}
                        : () => Navigator.pop(context),
                    icon: Icons.arrow_back,
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
}
