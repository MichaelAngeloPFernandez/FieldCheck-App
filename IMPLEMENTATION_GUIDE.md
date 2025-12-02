# FieldCheck App - UI/UX Polish Implementation Guide

## Quick Start for Developers

This guide explains how to use the new design system and components when working on FieldCheck screens.

---

## 📚 Core Files Reference

### 1. Design System
**File:** `lib/utils/app_theme.dart`

Contains all design tokens:
- Colors (primary, secondary, accent, error, warning)
- Spacing constants (xs, sm, md, lg, xl, xxl)
- Border radius constants (radiusSm, radiusMd, radiusLg, radiusXl)
- Typography styles (headingXl through bodySm)
- Complete light and dark themes

**Usage:**
```dart
import 'package:field_check/utils/app_theme.dart';

// Use colors
Color myColor = AppTheme.primaryColor;

// Use spacing
SizedBox(height: AppTheme.lg);

// Use typography
Text('Title', style: AppTheme.headingMd);
```

### 2. Reusable Components
**File:** `lib/widgets/app_widgets.dart`

Contains pre-built UI components:
- Cards and containers
- Buttons (primary, secondary, text)
- Input fields
- Loading states
- Error and empty states
- Feedback (snackbars)
- Layout components (dividers, headers, list tiles)
- Badges

**Usage:**
```dart
import 'package:field_check/widgets/app_widgets.dart';

// Create a button
AppWidgets.primaryButton(
  label: 'Save',
  onPressed: () => _save(),
  icon: Icons.save,
);

// Show success message
AppWidgets.showSuccessSnackbar(context, 'Saved successfully!');

// Display loading state
AppWidgets.loadingIndicator(message: 'Loading...');
```

### 3. Logging System
**File:** `lib/utils/logger.dart`

Comprehensive logging for debugging:
- Multiple log levels (debug, info, warning, error, success)
- Predefined tags for categorization
- Color-coded output with emojis

**Usage:**
```dart
import 'package:field_check/utils/logger.dart';

AppLogger.info(AppLogger.tagAuth, 'User logged in');
AppLogger.error(AppLogger.tagAPI, 'API call failed', exception);
AppLogger.success(AppLogger.tagTask, 'Task completed');
```

---

## 🎨 Design System Usage

### Colors

**Primary Colors:**
```dart
AppTheme.primaryColor        // #2688d4 (Main Blue)
AppTheme.primaryDark         // #1a5fa0 (Darker Blue)
AppTheme.primaryLight        // #5ba3e8 (Lighter Blue)
```

**Status Colors:**
```dart
AppTheme.accentColor         // #4CAF50 (Success - Green)
AppTheme.warningColor        // #FFA726 (Warning - Orange)
AppTheme.errorColor          // #E53935 (Error - Red)
```

**Text Colors:**
```dart
AppTheme.textPrimary         // #212121 (Dark text)
AppTheme.textSecondary       // #757575 (Medium text)
AppTheme.textTertiary        // #BDBDBD (Light text)
```

**Background Colors:**
```dart
AppTheme.backgroundColor     // #F5F5F5 (Light background)
AppTheme.darkBackgroundColor // #121212 (Dark background)
AppTheme.surfaceColor        // #FFFFFF (White surface)
AppTheme.surfaceDark         // #1E1E1E (Dark surface)
```

### Spacing

**Use these constants instead of hardcoded values:**
```dart
// Instead of: SizedBox(height: 4)
SizedBox(height: AppTheme.xs);    // 4px

// Instead of: SizedBox(height: 8)
SizedBox(height: AppTheme.sm);    // 8px

// Instead of: SizedBox(height: 12)
SizedBox(height: AppTheme.md);    // 12px

// Instead of: SizedBox(height: 16)
SizedBox(height: AppTheme.lg);    // 16px

// Instead of: SizedBox(height: 24)
SizedBox(height: AppTheme.xl);    // 24px

// Instead of: SizedBox(height: 32)
SizedBox(height: AppTheme.xxl);   // 32px
```

### Border Radius

**Use these constants for consistent rounding:**
```dart
BorderRadius.circular(AppTheme.radiusSm);   // 4px
BorderRadius.circular(AppTheme.radiusMd);   // 8px
BorderRadius.circular(AppTheme.radiusLg);   // 12px
BorderRadius.circular(AppTheme.radiusXl);   // 16px
```

### Typography

**Text Styles Hierarchy:**
```dart
// Page Titles
Text('Main Title', style: AppTheme.headingXl);      // 32px, bold

// Section Headers
Text('Section', style: AppTheme.headingLg);         // 28px, bold
Text('Subsection', style: AppTheme.headingMd);      // 24px, w600
Text('Card Title', style: AppTheme.headingSm);      // 20px, w600

// Body Text
Text('Body', style: AppTheme.bodyLg);               // 16px, w500
Text('Secondary', style: AppTheme.bodyMd);          // 14px, w400
Text('Tertiary', style: AppTheme.bodySm);           // 12px, w400

// Labels
Text('Label', style: AppTheme.labelLg);             // 14px, w600
Text('Small Label', style: AppTheme.labelMd);       // 12px, w600
```

---

## 🧩 Component Usage Examples

### Buttons

**Primary Button (Main Action):**
```dart
AppWidgets.primaryButton(
  label: 'Save',
  onPressed: () => _save(),
  icon: Icons.save,
  isLoading: _isSaving,
  isEnabled: _isFormValid,
);
```

**Secondary Button (Alternative Action):**
```dart
AppWidgets.secondaryButton(
  label: 'Cancel',
  onPressed: () => Navigator.pop(context),
  icon: Icons.close,
);
```

**Text Button (Lightweight):**
```dart
AppWidgets.textButton(
  label: 'Learn More',
  onPressed: () => _openLink(),
  icon: Icons.info,
  color: AppTheme.primaryColor,
);
```

### Cards & Containers

**Modern Card:**
```dart
AppWidgets.modernCard(
  child: Column(
    children: [
      Text('Card Title', style: AppTheme.headingSm),
      SizedBox(height: AppTheme.md),
      Text('Card content here', style: AppTheme.bodyMd),
    ],
  ),
  onTap: () => _onCardTap(),
  elevation: 2,
);
```

**Rounded Container:**
```dart
AppWidgets.roundedContainer(
  padding: const EdgeInsets.all(AppTheme.lg),
  backgroundColor: AppTheme.surfaceColor,
  borderRadius: AppTheme.radiusLg,
  child: Text('Content', style: AppTheme.bodyMd),
);
```

### Loading & Error States

**Loading Indicator:**
```dart
if (_isLoading) {
  AppWidgets.loadingIndicator(
    message: 'Loading data...',
    color: AppTheme.primaryColor,
  );
}
```

**Error Message:**
```dart
if (_error != null) {
  AppWidgets.errorMessage(
    message: _error!,
    onRetry: () => _retry(),
    icon: Icons.error_outline,
  );
}
```

**Empty State:**
```dart
if (_items.isEmpty) {
  AppWidgets.emptyState(
    title: 'No Items',
    message: 'You haven\'t created any items yet.',
    icon: Icons.inbox_outlined,
    onAction: () => _createItem(),
    actionLabel: 'Create Item',
  );
}
```

### Feedback

**Success Snackbar:**
```dart
AppWidgets.showSuccessSnackbar(
  context,
  'Operation completed successfully!',
);
```

**Error Snackbar:**
```dart
AppWidgets.showErrorSnackbar(
  context,
  'Something went wrong. Please try again.',
);
```

**Warning Snackbar:**
```dart
AppWidgets.showWarningSnackbar(
  context,
  'This action cannot be undone.',
);
```

### Layout Components

**Screen Header:**
```dart
AppWidgets.screenHeader(
  title: 'Tasks',
  subtitle: 'Manage your tasks',
  trailing: IconButton(
    icon: const Icon(Icons.add),
    onPressed: () => _addTask(),
  ),
);
```

**List Tile:**
```dart
AppWidgets.listTile(
  title: 'Task Name',
  subtitle: 'Task description',
  leadingIcon: Icons.task,
  trailing: Icon(Icons.arrow_forward),
  onTap: () => _openTask(),
);
```

**Divider:**
```dart
AppWidgets.divider(label: 'Or');  // With label
AppWidgets.divider();              // Without label
```

**Badge:**
```dart
AppWidgets.badge(
  label: 'Active',
  backgroundColor: AppTheme.accentColor,
  textColor: Colors.white,
  icon: Icons.check_circle,
);
```

---

## 📝 Logging Examples

### Authentication
```dart
AppLogger.info(AppLogger.tagAuth, 'Login attempt for user: $email');
AppLogger.success(AppLogger.tagAuth, 'Login successful');
AppLogger.error(AppLogger.tagAuth, 'Login failed', exception);
```

### Location & Geofence
```dart
AppLogger.debug(AppLogger.tagLocation, 'Current position: $lat, $lng');
AppLogger.info(AppLogger.tagGeofence, 'Nearest geofence: $geofenceName');
AppLogger.warning(AppLogger.tagLocation, 'GPS signal weak');
```

### Tasks & Attendance
```dart
AppLogger.info(AppLogger.tagAttendance, 'Check-in initiated');
AppLogger.success(AppLogger.tagAttendance, 'Check-in successful');
AppLogger.info(AppLogger.tagTask, 'Task marked as complete');
```

### Navigation
```dart
AppLogger.debug(AppLogger.tagNavigation, 'Navigation: Dashboard → Map');
AppLogger.info(AppLogger.tagNavigation, 'User navigated to Settings');
```

### API Calls
```dart
AppLogger.info(AppLogger.tagAPI, 'Fetching user profile...');
AppLogger.success(AppLogger.tagAPI, 'Profile fetched successfully');
AppLogger.error(AppLogger.tagAPI, 'API call failed', exception);
```

---

## ✅ Screen Implementation Checklist

When updating a screen, follow this checklist:

- [ ] Import AppTheme, AppLogger, and AppWidgets
- [ ] Replace hardcoded colors with AppTheme constants
- [ ] Replace hardcoded spacing with AppTheme constants
- [ ] Replace hardcoded border radius with AppTheme constants
- [ ] Replace hardcoded text styles with AppTheme styles
- [ ] Replace custom buttons with AppWidgets buttons
- [ ] Replace custom loading states with AppWidgets.loadingIndicator()
- [ ] Replace custom error states with AppWidgets.errorMessage()
- [ ] Replace custom empty states with AppWidgets.emptyState()
- [ ] Replace custom snackbars with AppWidgets.show*Snackbar()
- [ ] Add logging to key operations (init, load, save, error)
- [ ] Use AppTheme.lg for screen padding
- [ ] Use AppTheme.xl for section spacing
- [ ] Use AppTheme.md for item spacing
- [ ] Verify responsive layout on different screen sizes
- [ ] Test in both light and dark modes
- [ ] Remove unused imports
- [ ] Add comments to complex logic

---

## 🔍 Debugging Tips

### Filter Logs in Android Studio
1. Open Logcat
2. Use filter: `[AUTH]`, `[LOCATION]`, `[API]`, etc.
3. Look for emoji prefixes: 🔵 (debug), ℹ️ (info), ⚠️ (warning), ❌ (error), ✅ (success)

### Common Issues

**Issue: Colors look different in dark mode**
- Solution: Use AppTheme colors instead of hardcoded hex values
- AppTheme automatically adjusts for dark mode

**Issue: Spacing looks inconsistent**
- Solution: Use AppTheme spacing constants instead of hardcoded values
- Never use arbitrary numbers like 15, 18, 22, etc.

**Issue: Text looks different on different screens**
- Solution: Use AppTheme text styles instead of custom TextStyle
- AppTheme styles are optimized for readability

**Issue: Can't find logs in Android Studio**
- Solution: Make sure you're in debug mode
- AppLogger only logs in debug mode (kDebugMode)
- Use Logcat filter to find specific tags

---

## 📱 Responsive Design

**Screen Sizes:**
- Mobile: 360-400dp
- Tablet: 600-800dp
- Large: 900+dp

**Padding Rules:**
- Always use AppTheme.lg (16px) for screen edges
- Use AppTheme.xl (24px) for section spacing
- Use AppTheme.md (12px) for item spacing

**Text Sizing:**
- Headings scale automatically with theme
- Body text is optimized for readability
- Use MediaQuery for responsive layouts when needed

---

## 🎯 Best Practices

1. **Always use AppTheme constants** - Never hardcode colors, spacing, or text styles
2. **Use AppWidgets components** - Don't create custom buttons, cards, or dialogs
3. **Add logging** - Log important operations for debugging
4. **Test both themes** - Verify light and dark mode appearance
5. **Keep spacing consistent** - Use the spacing system throughout
6. **Use semantic colors** - Use accentColor for success, errorColor for errors
7. **Add tooltips** - Help users understand button purposes
8. **Handle loading states** - Always show feedback during async operations
9. **Handle errors gracefully** - Show clear error messages with retry options
10. **Clean up resources** - Dispose controllers and cancel subscriptions

---

## 📞 Questions?

- Check existing screens for implementation examples
- Review AppTheme.dart for available constants
- Review AppWidgets.dart for component documentation
- Check Logger.dart for available tags

---

**Last Updated:** December 2, 2025
**Version:** 1.0
**Status:** Active
