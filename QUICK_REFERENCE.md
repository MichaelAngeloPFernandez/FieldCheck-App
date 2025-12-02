# FieldCheck App - Quick Reference Guide

## 🎯 Quick Start

### Import the essentials:
```dart
import 'package:field_check/utils/app_theme.dart';
import 'package:field_check/widgets/app_widgets.dart';
import 'package:field_check/utils/logger.dart';
```

---

## 🎨 Colors

```dart
// Primary
AppTheme.primaryColor       // #2688d4
AppTheme.primaryDark        // #1a5fa0
AppTheme.primaryLight       // #5ba3e8

// Status
AppTheme.accentColor        // Green (Success)
AppTheme.warningColor       // Orange (Warning)
AppTheme.errorColor         // Red (Error)

// Text
AppTheme.textPrimary        // Dark text
AppTheme.textSecondary      // Medium text
AppTheme.textTertiary       // Light text
```

---

## 📏 Spacing

```dart
AppTheme.xs     // 4px
AppTheme.sm     // 8px
AppTheme.md     // 12px
AppTheme.lg     // 16px
AppTheme.xl     // 24px
AppTheme.xxl    // 32px
```

---

## 🔲 Border Radius

```dart
AppTheme.radiusSm   // 4px
AppTheme.radiusMd   // 8px
AppTheme.radiusLg   // 12px
AppTheme.radiusXl   // 16px
```

---

## 📝 Typography

```dart
AppTheme.headingXl      // 32px, bold
AppTheme.headingLg      // 28px, bold
AppTheme.headingMd      // 24px, w600
AppTheme.headingSm      // 20px, w600
AppTheme.bodyLg         // 16px, w500
AppTheme.bodyMd         // 14px, w400
AppTheme.bodySm         // 12px, w400
AppTheme.labelLg        // 14px, w600
AppTheme.labelMd        // 12px, w600
```

---

## 🔘 Buttons

```dart
// Primary
AppWidgets.primaryButton(
  label: 'Save',
  onPressed: () => _save(),
  icon: Icons.save,
);

// Secondary
AppWidgets.secondaryButton(
  label: 'Cancel',
  onPressed: () => Navigator.pop(context),
);

// Text
AppWidgets.textButton(
  label: 'Learn More',
  onPressed: () => _openLink(),
);
```

---

## 📦 Cards & Containers

```dart
// Modern Card
AppWidgets.modernCard(
  child: Text('Content'),
  onTap: () => _onTap(),
);

// Rounded Container
AppWidgets.roundedContainer(
  child: Text('Content'),
  padding: const EdgeInsets.all(AppTheme.lg),
);
```

---

## ⏳ Loading & Error States

```dart
// Loading
AppWidgets.loadingIndicator(message: 'Loading...');

// Error
AppWidgets.errorMessage(
  message: 'Something went wrong',
  onRetry: () => _retry(),
);

// Empty
AppWidgets.emptyState(
  title: 'No Items',
  message: 'Create one to get started',
);
```

---

## 📢 Feedback

```dart
// Success
AppWidgets.showSuccessSnackbar(context, 'Saved!');

// Error
AppWidgets.showErrorSnackbar(context, 'Failed!');

// Warning
AppWidgets.showWarningSnackbar(context, 'Warning!');
```

---

## 📋 Layout

```dart
// Header
AppWidgets.screenHeader(
  title: 'Title',
  subtitle: 'Subtitle',
);

// List Item
AppWidgets.listTile(
  title: 'Item',
  subtitle: 'Description',
  onTap: () => _onTap(),
);

// Divider
AppWidgets.divider(label: 'Or');

// Badge
AppWidgets.badge(
  label: 'Active',
  backgroundColor: AppTheme.accentColor,
);
```

---

## 📝 Logging

```dart
// Info
AppLogger.info(AppLogger.tagAuth, 'User logged in');

// Success
AppLogger.success(AppLogger.tagTask, 'Task completed');

// Warning
AppLogger.warning(AppLogger.tagLocation, 'GPS weak');

// Error
AppLogger.error(AppLogger.tagAPI, 'API failed', exception);

// Debug
AppLogger.debug(AppLogger.tagUI, 'Debug info');
```

---

## 🏷️ Log Tags

```dart
AppLogger.tagAuth          // Authentication
AppLogger.tagLocation      // GPS/Location
AppLogger.tagGeofence      // Geofence
AppLogger.tagAttendance    // Check-in/out
AppLogger.tagTask          // Tasks
AppLogger.tagMap           // Map
AppLogger.tagAPI           // API calls
AppLogger.tagDatabase      // Database
AppLogger.tagUI            // UI/Screens
AppLogger.tagNavigation    // Navigation
AppLogger.tagSocket        // WebSocket
AppLogger.tagSync          // Sync
AppLogger.tagCache         // Cache
AppLogger.tagAdmin         // Admin
AppLogger.tagReport        // Reports
```

---

## ✅ Screen Checklist

When updating a screen:
- [ ] Import AppTheme, AppLogger, AppWidgets
- [ ] Use AppTheme colors (no hardcoded hex)
- [ ] Use AppTheme spacing (no hardcoded numbers)
- [ ] Use AppTheme typography (no custom TextStyle)
- [ ] Use AppWidgets components (no custom buttons)
- [ ] Add logging to key operations
- [ ] Test light and dark modes
- [ ] Verify responsive layout
- [ ] Remove unused imports

---

## 🔍 Debugging

### Filter logs by tag:
1. Open Logcat in Android Studio
2. Type: `[AUTH]`, `[LOCATION]`, `[API]`, etc.
3. Look for emoji: 🔵 ℹ️ ⚠️ ❌ ✅

### Common issues:
- **Colors wrong?** Use AppTheme constants
- **Spacing off?** Use AppTheme spacing
- **Text weird?** Use AppTheme styles
- **No logs?** Make sure you're in debug mode

---

## 📚 Documentation

- **Full Guide:** `IMPLEMENTATION_GUIDE.md`
- **Summary:** `UI_UX_POLISH_SUMMARY.md`
- **Report:** `FINAL_UI_POLISH_REPORT.md`

---

## 🎨 Common Patterns

### Form with error:
```dart
if (_error != null)
  Container(
    padding: const EdgeInsets.all(AppTheme.md),
    decoration: BoxDecoration(
      color: AppTheme.errorColor.withOpacity(0.1),
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
    ),
    child: Text(_error!, style: AppTheme.bodySm),
  ),
```

### Loading button:
```dart
AppWidgets.primaryButton(
  label: 'Save',
  onPressed: _isLoading ? null : () => _save(),
  isLoading: _isLoading,
);
```

### List with empty state:
```dart
_items.isEmpty
    ? AppWidgets.emptyState(
        title: 'No Items',
        message: 'Create one to get started',
      )
    : ListView.builder(
        itemCount: _items.length,
        itemBuilder: (context, index) => 
          AppWidgets.listTile(
            title: _items[index].name,
          ),
      ),
```

### Screen with header:
```dart
Column(
  children: [
    AppWidgets.screenHeader(
      title: 'Tasks',
      subtitle: 'Manage your tasks',
    ),
    Expanded(
      child: _buildContent(),
    ),
  ],
)
```

---

## 🚀 Pro Tips

1. **Always use constants** - Never hardcode values
2. **Use AppWidgets** - Don't create custom components
3. **Add logging** - Help future debugging
4. **Test both themes** - Light and dark mode
5. **Keep spacing consistent** - Use the system
6. **Use semantic colors** - Green for success, red for error
7. **Add tooltips** - Help users understand
8. **Handle loading** - Always show feedback
9. **Handle errors** - Show clear messages
10. **Clean up** - Dispose resources properly

---

## 📞 Need Help?

- Check existing screens for examples
- Review AppTheme.dart for constants
- Review AppWidgets.dart for components
- Check Logger.dart for tags
- Read IMPLEMENTATION_GUIDE.md for details

---

**Last Updated:** December 2, 2025  
**Version:** 1.0  
**Status:** Ready to Use
