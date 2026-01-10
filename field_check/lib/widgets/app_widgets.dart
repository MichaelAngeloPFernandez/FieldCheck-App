// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:field_check/utils/app_theme.dart';

/// Reusable UI components for consistent design across the app
class AppWidgets {
  // Prevent instantiation
  AppWidgets._();

  static String friendlyErrorMessage(
    Object error, {
    String fallback = 'Error',
  }) {
    final raw = error.toString();
    final cleaned = raw.replaceFirst(RegExp(r'^Exception:\s*'), '').trim();
    if (cleaned.isEmpty) return fallback;
    return cleaned;
  }

  // ============================================================================
  // CARDS & CONTAINERS
  // ============================================================================

  /// Modern card with consistent styling
  static Widget modernCard({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(AppTheme.lg),
    VoidCallback? onTap,
    Color? backgroundColor,
    double? elevation,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Card(
        elevation: elevation ?? 2,
        color: backgroundColor,
        child: Padding(padding: padding, child: child),
      ),
    );
  }

  /// Rounded container with shadow
  static Widget roundedContainer({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(AppTheme.lg),
    Color? backgroundColor,
    double borderRadius = AppTheme.radiusLg,
    BoxBorder? border,
  }) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor ?? AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(borderRadius),
        border: border,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }

  // ============================================================================
  // BUTTONS
  // ============================================================================

  /// Primary action button
  static Widget primaryButton({
    required String label,
    required VoidCallback onPressed,
    bool isLoading = false,
    bool isEnabled = true,
    IconData? icon,
    double? width,
  }) {
    return SizedBox(
      width: width,
      height: 48,
      child: ElevatedButton.icon(
        onPressed: isEnabled && !isLoading ? onPressed : null,
        icon: isLoading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isEnabled ? Colors.white : Colors.grey,
                  ),
                ),
              )
            : Icon(icon ?? Icons.check),
        label: Text(
          isLoading ? 'Loading...' : label,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  /// Secondary action button
  static Widget secondaryButton({
    required String label,
    required VoidCallback onPressed,
    bool isEnabled = true,
    IconData? icon,
    double? width,
  }) {
    return SizedBox(
      width: width,
      height: 48,
      child: OutlinedButton.icon(
        onPressed: isEnabled ? onPressed : null,
        icon: Icon(icon ?? Icons.info),
        label: Text(
          label,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  /// Text action button
  static Widget textButton({
    required String label,
    required VoidCallback onPressed,
    IconData? icon,
    Color? color,
  }) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(
        icon ?? Icons.arrow_forward,
        color: color ?? AppTheme.primaryColor,
      ),
      label: Text(
        label,
        style: TextStyle(
          color: color ?? AppTheme.primaryColor,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  // ============================================================================
  // INPUT FIELDS
  // ============================================================================

  /// Modern text input field
  static Widget textInput({
    required TextEditingController controller,
    required String label,
    String? hint,
    IconData? prefixIcon,
    IconData? suffixIcon,
    VoidCallback? onSuffixIconPressed,
    bool obscureText = false,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      maxLines: maxLines,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: prefixIcon != null ? Icon(prefixIcon) : null,
        suffixIcon: suffixIcon != null
            ? IconButton(icon: Icon(suffixIcon), onPressed: onSuffixIconPressed)
            : null,
      ),
    );
  }

  // ============================================================================
  // LOADING STATES
  // ============================================================================

  /// Loading indicator with message
  static Widget loadingIndicator({String? message, Color? color}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(
              color ?? AppTheme.primaryColor,
            ),
          ),
          if (message != null) ...[
            const SizedBox(height: AppTheme.md),
            Text(message, style: AppTheme.bodyMd, textAlign: TextAlign.center),
          ],
        ],
      ),
    );
  }

  /// Skeleton loading placeholder
  static Widget skeletonLoader({
    double height = 20,
    double width = double.infinity,
    double borderRadius = AppTheme.radiusMd,
  }) {
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }

  // ============================================================================
  // ERROR & EMPTY STATES
  // ============================================================================

  /// Error message display
  static Widget errorMessage({
    required String message,
    VoidCallback? onRetry,
    IconData icon = Icons.error_outline,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: AppTheme.errorColor),
          const SizedBox(height: AppTheme.lg),
          Text('Error', style: AppTheme.headingSm),
          const SizedBox(height: AppTheme.md),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.lg),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: AppTheme.bodyMd,
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: AppTheme.xl),
            primaryButton(
              label: 'Retry',
              onPressed: onRetry,
              icon: Icons.refresh,
            ),
          ],
        ],
      ),
    );
  }

  /// Empty state display
  static Widget emptyState({
    required String title,
    required String message,
    IconData icon = Icons.inbox_outlined,
    VoidCallback? onAction,
    String? actionLabel,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: AppTheme.textTertiary),
          const SizedBox(height: AppTheme.lg),
          Text(title, style: AppTheme.headingSm),
          const SizedBox(height: AppTheme.md),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.lg),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: AppTheme.bodyMd,
            ),
          ),
          if (onAction != null && actionLabel != null) ...[
            const SizedBox(height: AppTheme.xl),
            primaryButton(label: actionLabel, onPressed: onAction),
          ],
        ],
      ),
    );
  }

  // ============================================================================
  // DIALOGS & ALERTS
  // ============================================================================

  /// Success snackbar
  static void showSuccessSnackbar(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: AppTheme.md),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: AppTheme.accentColor,
        duration: duration,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(AppTheme.lg),
      ),
    );
  }

  /// Error snackbar
  static void showErrorSnackbar(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 4),
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error, color: Colors.white),
            const SizedBox(width: AppTheme.md),
            Expanded(
              child: Text(
                message,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        backgroundColor: AppTheme.errorColor,
        showCloseIcon: true,
        closeIconColor: Colors.white,
        duration: duration,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(AppTheme.lg),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        ),
      ),
    );
  }

  /// Warning snackbar
  static void showWarningSnackbar(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.warning, color: Colors.white),
            const SizedBox(width: AppTheme.md),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: AppTheme.warningColor,
        duration: duration,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(AppTheme.lg),
      ),
    );
  }

  // ============================================================================
  // DIVIDERS & SEPARATORS
  // ============================================================================

  /// Horizontal divider with optional label
  static Widget divider({
    String? label,
    EdgeInsets padding = const EdgeInsets.symmetric(vertical: AppTheme.lg),
  }) {
    if (label == null) {
      return Padding(padding: padding, child: const Divider(height: 1));
    }

    return Padding(
      padding: padding,
      child: Row(
        children: [
          const Expanded(child: Divider(height: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.md),
            child: Text(label, style: AppTheme.labelMd),
          ),
          const Expanded(child: Divider(height: 1)),
        ],
      ),
    );
  }

  // ============================================================================
  // HEADERS & TITLES
  // ============================================================================

  /// Screen header with title and optional subtitle
  static Widget screenHeader({
    required String title,
    String? subtitle,
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.lg,
        vertical: AppTheme.lg,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTheme.headingMd),
                if (subtitle != null) ...[
                  const SizedBox(height: AppTheme.xs),
                  Text(subtitle, style: AppTheme.bodySm),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  // ============================================================================
  // LIST ITEMS
  // ============================================================================

  /// Consistent list tile
  static Widget listTile({
    required String title,
    String? subtitle,
    IconData? leadingIcon,
    Widget? trailing,
    VoidCallback? onTap,
    Color? backgroundColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        color: backgroundColor,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.lg,
            vertical: AppTheme.md,
          ),
          child: Row(
            children: [
              if (leadingIcon != null) ...[
                Icon(leadingIcon, color: AppTheme.primaryColor),
                const SizedBox(width: AppTheme.lg),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTheme.bodyLg),
                    if (subtitle != null) ...[
                      const SizedBox(height: AppTheme.xs),
                      Text(subtitle, style: AppTheme.bodySm),
                    ],
                  ],
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================================
  // BADGES & TAGS
  // ============================================================================

  /// Status badge
  static Widget badge({
    required String label,
    Color? backgroundColor,
    Color? textColor,
    IconData? icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.md,
        vertical: AppTheme.xs,
      ),
      decoration: BoxDecoration(
        color: backgroundColor ?? AppTheme.primaryLight,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: textColor ?? Colors.white),
            const SizedBox(width: AppTheme.xs),
          ],
          Text(
            label,
            style: AppTheme.labelMd.copyWith(
              color: textColor ?? Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
