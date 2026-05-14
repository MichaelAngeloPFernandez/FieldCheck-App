# Deploy FieldCheck Flutter App (Android APK)

## Overview
This guide covers building and distributing the FieldCheck Flutter app as an Android APK.

**Build Time:** ~10 minutes  
**Distribution:** Direct APK or Google Play Store  
**Target:** Android 5.0+ (SDK 21+)

---

## Prerequisites

✅ Flutter SDK installed  
✅ Android SDK installed  
✅ Backend deployed to Render (with API URL)  
✅ Google Play Developer account (optional, for store distribution)  

---

## Step 1: Update Frontend Configuration

### 1.1 Update API Base URL
**File:** `field_check/lib/services/api_client.dart` (or your main API config)

Find:
```dart
static const String baseURL = 'http://localhost:5000';
```

Replace with:
```dart
static const String baseURL = 'https://fieldcheck-backend.onrender.com';
```

### 1.2 Update App Branding
**File:** `field_check/android/app/src/main/AndroidManifest.xml`

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="com.fieldcheck.app">
    
    <application
        android:label="FieldCheck"
        android:icon="@mipmap/ic_launcher"
        ...>
```

### 1.3 Update App Version
**File:** `field_check/pubspec.yaml`

```yaml
version: 1.0.0+1  # Format: major.minor.patch+buildNumber
```

---

## Step 2: Build Release APK

### 2.1 Clean Previous Builds
```bash
cd field_check
flutter clean
flutter pub get
```

### 2.2 Build APK (Release Mode)
```bash
flutter build apk --release
```

**Output:** APK is saved to:
```
field_check/build/app/outputs/flutter-app.apk
```

Or find it with:
```bash
# Windows
cd field_check/build/app/outputs/flutter-app.release
dir *.apk

# macOS/Linux
cd field_check/build/app/outputs/flutter-app.release
ls *.apk
```

### 2.3 Build APK (Split by ABI for Smaller Size)
```bash
# Build separate APKs for different processor types
flutter build apk --release --split-per-abi
```

**Output:** Multiple APKs (~30MB each instead of ~100MB)
```
fieldcheck-app-armeabi-v7a-release.apk    (ARM 32-bit)
fieldcheck-app-arm64-v8a-release.apk      (ARM 64-bit)
fieldcheck-app-x86-release.apk            (Intel x86)
fieldcheck-app-x86_64-release.apk         (Intel x86 64-bit)
```

### 2.4 Build App Bundle (For Google Play Store)
```bash
flutter build appbundle --release
```

**Output:**
```
field_check/build/app/outputs/bundle/release/app-release.aab
```

---

## Step 3: Test APK Locally

### 3.1 Connect Android Device
```bash
flutter devices
```

Expected output:
```
2 connected devices:
Emulator • emulator-5554 • android • Android 13 (API 33)
SM-G970F • 1234567890abcdef • android • Android 12 (API 31)
```

### 3.2 Install APK on Device
```bash
# Install to connected device
flutter install --release

# Or install specific APK:
adb install -r field_check/build/app/outputs/flutter-app.apk
```

### 3.3 Test Core Flows
1. **Launch app** - Check branding/icon
2. **Create ticket** - Test form submission to production backend
3. **Upload attachment** - Verify compression + upload
4. **Check offline mode** - Verify draft auto-save
5. **Test dark mode** - Toggle device dark mode
6. **Check responsive** - Rotate device to landscape

### 3.4 Check Logs
```bash
flutter logs
```

Look for:
- ✅ API connection successful
- ✅ No validation errors
- ✅ Attachments uploading (compressed)

---

## Step 4: Prepare for Distribution

### 4.1 Sign APK

Generate keystore (one-time):
```bash
keytool -genkey -v -keystore field-check.jks -keyalg RSA \
  -keysize 2048 -validity 10000 \
  -alias field-check \
  -dname "CN=FieldCheck, O=Your Company, L=City, ST=State, C=US"
```

Create signing config:
**File:** `field_check/android/key.properties`
```properties
storeFile=../field-check.jks
storePassword=YourStorePassword
keyAlias=field-check
keyPassword=YourKeyPassword
```

**File:** `field_check/android/app/build.gradle`

Find:
```gradle
buildTypes {
    release {
        signingConfig signingConfigs.debug
    }
}
```

Replace with:
```gradle
signingConfigs {
    release {
        keyAlias keystoreProperties['keyAlias']
        keyPassword keystoreProperties['keyPassword']
        storeFile file(keystoreProperties['storeFile'])
        storePassword keystoreProperties['storePassword']
    }
}

buildTypes {
    release {
        signingConfig signingConfigs.release
    }
}
```

Rebuild:
```bash
flutter build apk --release
```

### 4.2 Prepare Store Listing (Google Play)
Create `PLAY_STORE_LISTING.md`:

```markdown
# FieldCheck - Service Request Management

## Short Description
Mobile app for managing field service requests with offline support and real-time updates.

## Full Description
FieldCheck is a comprehensive field service management platform that enables:

- Create service requests from customizable templates
- Real-time ticket tracking and assignment
- Offline form drafts with auto-save
- Image compression for fast uploads
- Automatic retry on connection issues
- Dark mode support
- Responsive design for all devices

Perfect for HVAC, Plumbing, Electrical, and other service businesses.

## Screenshots
1. Dashboard with service templates
2. Service request creation form
3. Ticket tracking and status
4. Attachment management

## Privacy
We respect your privacy. All data is encrypted and stored securely.

## Support
Email: support@fieldcheck.com
Website: https://fieldcheck.com
```

---

## Step 5: Upload to Google Play Store

### 5.1 Setup Google Play Developer Account
1. Go to https://play.google.com/console
2. Create developer account ($25 one-time fee)
3. Verify payment method
4. Accept Developer Agreement

### 5.2 Create App Listing
1. **Click "Create app"**
2. **App name:** `FieldCheck`
3. **Default language:** English
4. **App category:** Business
5. **Accept policies**
6. **Click "Create"**

### 5.3 Fill in Store Listing
1. **App info → Title & description**
   - Title: "FieldCheck"
   - Subtitle: "Field Service Management"
   - Full description: (from PLAY_STORE_LISTING.md above)

2. **Graphics → Screenshots**
   - Upload 2-8 screenshots (1080×1920px)
   - Show key features

3. **Graphics → Icon**
   - Upload 512×512px PNG

4. **Graphics → Feature graphic**
   - Upload 1024×500px image

5. **Content rating**
   - Fill out content questionnaire
   - Should be 3+ (business app)

### 5.4 Upload Build

1. **Release → Production**
2. **Create new release**
3. **Upload APK/AAB**
   - Select `app-release.aab` (recommended)
4. **Fill in release notes:**
   ```
   v1.0.0 - Initial Release
   - Service request creation and tracking
   - Offline form support with auto-save
   - Image compression and upload
   - Dark mode and responsive design
   - Real-time status updates
   ```
5. **Set pricing:** Free or Paid
6. **Target countries:** All
7. **Review and publish**

### 5.5 Submit for Review
- **Check all requirements:** Green checkmarks
- **Click "Send for review"**
- **Wait 24-48 hours** for app review
- **Once approved:** App is live in Play Store!

---

## Step 6: Direct APK Distribution (Alternative)

If you don't want to go through Play Store:

### 6.1 Host APK on Server
```bash
# Copy APK to your server
scp field_check/build/app/outputs/flutter-app.apk \
  user@yourdomain.com:/var/www/downloads/

# Create download link:
# https://yourdomain.com/downloads/fieldcheck-app.apk
```

### 6.2 Create Distribution Page
**File:** `fieldcheck-app-download.html`
```html
<!DOCTYPE html>
<html>
<head>
    <title>FieldCheck - Download</title>
</head>
<body>
    <h1>FieldCheck App</h1>
    <p>Download the latest version for Android:</p>
    <a href="https://yourdomain.com/downloads/fieldcheck-app.apk" 
       class="btn">Download APK (v1.0.0)</a>
    
    <p><small>Requires Android 5.0+</small></p>
</body>
</html>
```

### 6.3 Share Installation Link
Users can now:
1. Click download link on their Android device
2. Open file manager and install
3. Grant permissions and launch

---

## Troubleshooting

### Issue: "Build Failed - Missing Dependencies"
```bash
flutter pub get
flutter pub upgrade
flutter clean
flutter build apk --release
```

### Issue: "API Connection Failed"
1. Check backend is running: `curl https://fieldcheck-backend.onrender.com`
2. Verify API URL in Flutter code
3. Check device network connection
4. Check if API requires authentication

### Issue: "APK is Too Large"
```bash
# Use split-per-abi to reduce size
flutter build apk --release --split-per-abi

# Or shrink resources
flutter build apk --release --strip-debug-symbols
```

### Issue: "Certificate Not Trusted"
```bash
# On release, certificate should be valid
# If testing locally:
adb install -r field_check/build/app/outputs/flutter-app.apk
```

### Issue: "Storage Permission Denied"
- Add to `AndroidManifest.xml`:
```xml
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />
```

---

## App Store Comparison

| Platform | Time | Cost | Reach | Requirements |
|----------|------|------|-------|--------------|
| **Google Play** | 24-48h | $25 one-time | 2B+ devices | Developer account |
| **Direct APK** | Instant | Free | Limited | Your server |
| **GitHub Releases** | Instant | Free | Dev users | GitHub account |
| **F-Droid** | 1-2 weeks | Free | Privacy users | Open source required |

---

## Post-Release Monitoring

### 7.1 Crashlytics (Google)
Add Firebase for crash reporting:
```bash
flutter pub add firebase_crashlytics
flutter pub get
```

### 7.2 In-App Updates
```bash
flutter pub add in_app_update
```

### 7.3 Analytics (Google)
```bash
flutter pub add google_analytics_flutter
```

---

## Release Checklist

- ✅ API URL updated to production
- ✅ Version number incremented
- ✅ App tested on physical device
- ✅ Dark mode working
- ✅ Responsive design verified
- ✅ Offline mode tested
- ✅ APK signed with release certificate
- ✅ Store listing filled out
- ✅ Screenshots and branding uploaded
- ✅ Privacy policy linked
- ✅ Support email configured
- ✅ Build submitted for review

---

## Version Management

When releasing updates:

1. **Update version in pubspec.yaml:**
   ```yaml
   version: 1.0.1+2  # Increment buildNumber
   ```

2. **Create release notes:**
   ```
   v1.0.1 - Bug fixes and improvements
   - Fixed dark mode toggle
   - Improved attachment compression
   - Better network error messages
   ```

3. **Build and test:**
   ```bash
   flutter build apk --release
   adb install -r <apk>
   ```

4. **Upload to Play Store:**
   - Release → Production → New Release
   - Select new APK
   - Enter release notes
   - Click Publish

---

## Next Steps

1. ✅ **Backend deployed to Render**
2. ✅ **Build release APK**
3. ⏳ **Test APK on device**
4. ⏳ **Create Google Play Developer account** (if using Play Store)
5. ⏳ **Upload to Google Play Store or host directly**
6. ⏳ **Announce release to users**

---

## Resources

- Flutter Build Docs: https://flutter.dev/docs/deployment/android
- Google Play Console: https://play.google.com/console
- Android App Signing: https://developer.android.com/studio/publish/app-signing
- Firebase Setup: https://firebase.flutter.dev/docs/overview

---

**Ready to ship your app! 🚀**
