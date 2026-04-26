# FieldCheck Quick Start & Testing Guide

**This guide helps you test and deploy FieldCheck in 30 minutes.**

---

## 🚀 Quick Start (Local Development)

### Step 1: Clone & Setup Backend (5 minutes)

```bash
cd FieldCheck-App/backend

# Install dependencies
npm install

# Verify .env file has MongoDB connection
cat .env | grep MONGO_URI
# Should output: MONGO_URI=mongodb+srv://...

# Start server
npm start

# Expected output:
# ✅ Starting server initialization...
# ✅ Socket.io initialized
# ✅ Server running on port 3002
# ✅ MongoDB connected
```

### Step 2: Test Backend API (3 minutes)

**Health Check:**
```bash
curl http://localhost:3002/api/health
# {"status":"ok","message":"FieldCheck API v1.0",...}
```

**Create User Account:**
```bash
curl -X POST http://localhost:3002/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "email":"test@example.com",
    "password":"TestPassword123!",
    "name":"Test User"
  }'
# {"token":"eyJhbGciOiJIUzI1NiIs...","user":{"_id":"...","email":"test@example.com"}}
```

**Get Aircon Template:**
```bash
TEMPLATE_ID="69ee24041e2b350202ee2d61"

curl -X GET http://localhost:3002/api/templates/$TEMPLATE_ID \
  -H "Authorization: Bearer YOUR_TOKEN_FROM_ABOVE"
# Returns complete template with 20 fields
```

### Step 3: Setup Flutter App (5 minutes)

```bash
cd FieldCheck-App/field_check

# Install dependencies
flutter pub get

# Ensure device/emulator is running
flutter devices
# Should show at least one device

# Run app in debug mode
flutter run

# Should see FieldCheck app launch on device
```

### Step 4: Test Ticket Creation (5 minutes)

1. **Open app** - You should see login screen
2. **Login** - Use credentials from Step 2 (test@example.com / TestPassword123!)
3. **View Dashboard** - Should see "Browse Services" tab with templates
4. **Create Ticket**:
   - Tap "Create" button
   - Select "Aircon Cleaning Service"
   - Fill form with sample data:
     ```
     Customer Name: John Tan
     Email: john@example.com
     Phone: 81234567
     Address: Block 123, Tampines Ave 5
     Building Type: Residential
     Unit Count: 2
     Brand: Daikin
     Issues: Minor
     Notes: Filters need replacing
     ```
   - Tap "Submit"
   - Should see: "✓ Ticket AC-0001 created"

### Step 5: Test Features (5 minutes)

**Test Offline Draft:**
1. Create new ticket
2. Fill a few fields
3. Close app (without submit)
4. Reopen app
5. Should see "Recover Draft?" dialog
6. Tap "Recover" - all fields restored

**Test Image Upload:**
1. In ticket form, tap "Camera" button
2. Take a photo or select from gallery
3. Should see image compressed to <500KB
4. Upload progress visible
5. Success confirmation

**Test Dark Mode:**
1. Device Settings → Display → Dark Mode (ON)
2. Switch back to app
3. App automatically switches to dark theme

---

## 🧪 Manual Testing Scenarios

### Scenario 1: Complete Aircon Service Ticket

**Time:** 5 minutes

1. Open app, login
2. Dashboard → Browse Services → Aircon Cleaning
3. Fill form:
   ```
   Customer: Sarah Lim
   Email: sarah@gmail.com
   Phone: 91234567
   Address: 42 Clementi Drive, Singapore
   Building: Commercial
   Units: 5
   Brand: Fujitsu
   Checklist: ✓ All 7 tasks
   Issues: Major - Refrigerant leak
   Parts: 1x Compressor ($500)
   Labor: 4 hours ($300)
   Follow-up: Yes, 2026-05-26
   Notes: Replaced compressor, system tested
   ```
4. Attach 3 photos from gallery
5. Submit → Verify ticket created (AC-0002)

### Scenario 2: Network Retry (Slow Connection)

**Time:** 3 minutes

1. Android: Settings → Developer Options → Simulate slow network (2G)
2. Create ticket with large image (10MB)
3. Upload should:
   - Show progress bar
   - Might timeout and retry
   - Eventually succeed
   - Badge showing "Retrying..." visible

### Scenario 3: Offline Draft Recovery

**Time:** 3 minutes

1. Airplane mode: ON
2. Create new plumbing ticket
3. Fill 10 fields with data
4. Close app completely
5. Airplane mode: OFF
6. Reopen app
7. Should see "Recover Draft?" dialog
8. Recover → All data restored
9. Submit (now online) → Ticket created

---

## 🔍 Verification Tests

### Backend Verification

**Run all checks:**
```bash
cd backend

# Check connection
npm start

# In another terminal:
# 1. Health check
curl http://localhost:3002/api/health

# 2. List templates
TOKEN="your_jwt_token_here"
curl http://localhost:3002/api/templates \
  -H "Authorization: Bearer $TOKEN"

# Expected: 3 templates (Aircon, Plumbing, Electrical)

# 3. Check database
# Go to MongoDB Atlas → FieldCheck cluster
# Collections should have:
#   - users (1+ documents)
#   - tickets (0-5 documents after testing)
#   - tickettemplates (3 documents)
#   - attachments (0-10 documents)
```

### Frontend Verification

**Check build:**
```bash
cd field_check

# Verify no build errors
flutter analyze

# Should output: No issues found!

# Build production APK
flutter build apk --release

# Check file size
ls -lh build/app/outputs/flutter-app.apk
# Should be 40-100MB

# Check compilation
flutter build apk --split-per-abi --release
# Should create 4 separate APKs (~30MB each)
```

---

## 🐛 Troubleshooting

### Issue: "MongoDB Connection Failed"

**Solution:**
```bash
# Check MONGO_URI in .env
cat backend/.env | grep MONGO_URI

# Verify connection in MongoDB Atlas:
# 1. Go to https://cloud.mongodb.com
# 2. Select Cluster0
# 3. Click "Connect"
# 4. Copy connection string
# 5. Update .env MONGO_URI
# 6. Restart server: npm start
```

### Issue: "API Connection Failed" in Flutter

**Solution:**
```dart
// Check backend URL in field_check/lib/services/api_client.dart
// Should be:
// - Local dev: http://localhost:3002
// - Production: https://fieldcheck-backend.onrender.com

// Debug network calls:
// 1. Flutter: flutter logs (watch for HTTP requests)
// 2. Backend: npm start (watch for incoming requests)
```

### Issue: "Form Validation Error"

**Solution:**
```dart
// Validation uses JSON Schema v7
// Check error details:
// - Email must match pattern
// - Phone must be 10+ digits
// - Required fields can't be empty
// - Numbers must be in min/max range

// Test with curl:
curl -X POST http://localhost:3002/api/tickets \
  -H "Content-Type: application/json" \
  -d '{
    "templateId":"69ee24041e2b350202ee2d61",
    "data":{...}
  }'
# Will show validation errors if any
```

### Issue: "Image Not Compressing"

**Solution:**
```dart
// Check image_compression_service.dart
// - Image library must be installed: flutter pub add image
// - Ensure file is JPEG/PNG
// - Check console for compression logs

// Test compression manually:
// 1. Pick large image (>5MB)
// 2. Check console for: "📷 Compressing image: X MB"
// 3. Verify output: "✅ Compressed: Y KB"
// 4. Upload should be fast (<10 seconds)
```

### Issue: "App Crashes on Startup"

**Solution:**
```bash
# Check logs
flutter logs --follow

# Look for error messages, common issues:
# - API URL wrong
# - Missing SharedPreferences init
# - Dart/Flutter version mismatch

# Try:
flutter clean
flutter pub get
flutter run
```

---

## 📊 Performance Checklist

### Backend Performance
- [ ] Health check responds in <100ms
- [ ] Template load in <500ms
- [ ] Ticket creation in <1s
- [ ] File upload starts within <2s

### Frontend Performance
- [ ] App launch in <3s
- [ ] Dashboard loads in <1s
- [ ] Form renders in <500ms
- [ ] Image compression in <5s

### Network Performance
- [ ] Image: 5MB → 300KB (16x compression)
- [ ] Photo upload: <10s (on good network)
- [ ] Failed upload retries: automatic
- [ ] Offline mode: forms auto-save

---

## 🚀 Deployment Checklist

### Pre-Deployment

Backend:
- [ ] `npm install` successful
- [ ] `.env` file configured
- [ ] `npm start` runs without errors
- [ ] MongoDB connection verified
- [ ] Health endpoint responds
- [ ] All 3 templates seeded
- [ ] Rate limiting configured
- [ ] CORS settings appropriate

Frontend:
- [ ] `flutter pub get` successful
- [ ] `flutter analyze` shows no issues
- [ ] API URL updated to production
- [ ] `flutter build apk --release` succeeds
- [ ] Dark mode tested
- [ ] Responsive design verified
- [ ] Offline mode tested
- [ ] Image compression tested

### Deployment

Backend (Render):
1. Push to GitHub: `git push origin main`
2. Create Render service (see DEPLOYMENT_GUIDE_RENDER_BACKEND.md)
3. Set environment variables
4. Click "Create Web Service"
5. Wait 3-5 minutes for deployment
6. Test health endpoint

Frontend (Google Play):
1. Build release APK: `flutter build apk --release`
2. Create Google Play Developer account ($25)
3. Create app listing
4. Upload APK
5. Fill store details
6. Submit for review
7. Wait 24-48 hours

---

## 📈 Monitoring After Launch

### Daily Checks

```bash
# Backend health
curl https://fieldcheck-backend.onrender.com/api/health

# Check Render logs
# Go to https://dashboard.render.com → fieldcheck-backend → Logs

# Check MongoDB
# Go to https://cloud.mongodb.com → Cluster0 → Metrics
```

### Weekly Checks

- [ ] Verify no critical errors in logs
- [ ] Check user feedback/bug reports
- [ ] Monitor API response times
- [ ] Verify database size
- [ ] Check backup status

### Monthly Checks

- [ ] Update dependencies: `npm update`
- [ ] Review analytics
- [ ] Plan feature updates
- [ ] Security audit
- [ ] Database optimization

---

## 🆘 Emergency Procedures

### Backend Down

**Steps:**
1. Check Render dashboard
2. Review logs for errors
3. Restart service: Click "Manual Deploy"
4. Verify health: `curl https://fieldcheck-backend.onrender.com/api/health`
5. If still down: Check MongoDB connection

### Database Issues

**Steps:**
1. Go to MongoDB Atlas
2. Check connection status
3. Verify IP whitelist includes Render
4. Review connection logs
5. May need to restart cluster

### Mass User Registration Issues

**Steps:**
1. Check email service (Nodemailer)
2. Verify Gmail app password
3. Check rate limiting settings
4. Review email logs
5. May need to increase API limits

---

## 📞 Getting Help

**For Backend Issues:**
- Check Render logs
- Test with cURL
- Review .env file
- Check MongoDB Atlas

**For Frontend Issues:**
- Run `flutter logs`
- Check API URL
- Verify network connection
- Try `flutter clean` and `flutter pub get`

**For Deployment Issues:**
- Read DEPLOYMENT_GUIDE_RENDER_BACKEND.md
- Read DEPLOYMENT_GUIDE_FLUTTER_APK.md
- Check Render documentation
- Check Flutter documentation

---

## ✨ Success Indicators

You'll know FieldCheck is working when:

✅ Backend:
- Health endpoint responds
- Tickets created with sequential numbers (AC-0001, AC-0002)
- Attachments upload and store in MongoDB
- Templates load with correct fields

✅ Frontend:
- App launches without crashes
- Forms render all field types
- Images compress before upload
- Offline drafts persist
- Dark mode toggles

✅ Integration:
- Create ticket end-to-end works
- Attachments appear in database
- No validation errors
- Real-time updates appear

---

## 🎉 You're Ready!

**Everything is configured and tested. Ready to:**

1. Deploy backend to Render
2. Build Flutter APK
3. Upload to Google Play
4. Announce to users
5. Monitor and iterate

**Questions? Check the comprehensive documentation files!**

---

**Last Updated:** April 26, 2026  
**Version:** 1.0.0
