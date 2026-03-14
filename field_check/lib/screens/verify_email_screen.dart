// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:field_check/services/user_service.dart';
import 'package:field_check/utils/app_theme.dart';
import 'package:field_check/widgets/app_page.dart';
import 'package:field_check/widgets/app_widgets.dart';

class VerifyEmailScreen extends StatefulWidget {
  final String? token;

  const VerifyEmailScreen({super.key, this.token});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  final UserService _userService = UserService();

  bool _isVerifying = true;
  bool _verified = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runVerification();
    });
  }

  Future<void> _runVerification() async {
    final token = (widget.token ?? '').trim();
    if (token.isEmpty) {
      setState(() {
        _isVerifying = false;
        _verified = false;
        _errorMessage = 'Missing verification token.';
      });
      return;
    }

    setState(() {
      _isVerifying = true;
      _verified = false;
      _errorMessage = null;
    });

    try {
      await _userService.verifyEmail(token);
      if (!mounted) return;
      setState(() {
        _isVerifying = false;
        _verified = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isVerifying = false;
        _verified = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final Color iconColor = _isVerifying
        ? AppTheme.primaryColor
        : _verified
            ? AppTheme.accentColor
            : AppTheme.errorColor;

    final IconData icon = _isVerifying
        ? Icons.mark_email_read_outlined
        : _verified
            ? Icons.verified_outlined
            : Icons.error_outline;

    final String title = _isVerifying
        ? 'Verifying your email'
        : _verified
            ? 'Email verified'
            : 'Verification failed';

    final String subtitle = _isVerifying
        ? 'Please wait. This should only take a moment.'
        : _verified
            ? 'Your FieldCheck account is now active. You can safely close this page or continue to login.'
            : (_errorMessage ?? 'The verification link is invalid or has expired.');

    return AppPage(
      appBarTitle: 'Email Verification',
      showBack: !_isVerifying,
      child: Column(
        children: [
          const SizedBox(height: AppTheme.xl),
          Container(
            width: 104,
            height: 104,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppTheme.radiusXl),
              border: Border.all(color: iconColor.withValues(alpha: 0.18)),
            ),
            child: Icon(icon, size: 58, color: iconColor),
          ),
          const SizedBox(height: AppTheme.xl),
          Text(
            title,
            style: AppTheme.headingMd,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppTheme.md),
          Text(
            subtitle,
            style: AppTheme.bodySm.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.78),
              height: 1.35,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppTheme.xl),
          AppWidgets.roundedContainer(
            padding: const EdgeInsets.all(AppTheme.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_isVerifying)
                  Row(
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            theme.colorScheme.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppTheme.md),
                      Expanded(
                        child: Text(
                          'Confirming your account...',
                          style: AppTheme.bodySm.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                if (!_isVerifying && !_verified)
                  Container(
                    padding: const EdgeInsets.all(AppTheme.md),
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
                          Icons.info_outline,
                          size: 20,
                          color: AppTheme.errorColor,
                        ),
                        const SizedBox(width: AppTheme.md),
                        Expanded(
                          child: Text(
                            _errorMessage ??
                                'Your verification link may have expired. Please request a new one from an admin.',
                            style: AppTheme.bodySm.copyWith(
                              color: AppTheme.errorColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: AppTheme.lg),
                AppWidgets.primaryButton(
                  label: _verified ? 'Continue to Login' : 'Go to Login',
                  onPressed: _isVerifying
                      ? () {}
                      : () => Navigator.of(context).pushNamedAndRemoveUntil(
                            '/landing',
                            (route) => false,
                          ),
                  isLoading: false,
                  isEnabled: !_isVerifying,
                  icon: Icons.login,
                  width: double.infinity,
                ),
                if (!_isVerifying && !_verified) ...[
                  const SizedBox(height: AppTheme.md),
                  AppWidgets.primaryButton(
                    label: 'Try again',
                    onPressed: _runVerification,
                    isLoading: false,
                    isEnabled: true,
                    icon: Icons.refresh,
                    width: double.infinity,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppTheme.xl),
        ],
      ),
    );
  }
}
