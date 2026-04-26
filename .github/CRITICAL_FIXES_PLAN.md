---
name: fieldcheck-critical-fixes
description: "Critical bugs and fixes for FieldCheck-App. Use when: unblocking the app from production, fixing APK issues, or addressing high-priority bugs affecting users."
---

# FieldCheck Critical Fixes & Action Plan

## 🚨 PHASE 1: UNBLOCK THE APP (1-2 hours)

**Status:** APP BLOCKED - APK outdated with 6 unresolved bugs

### Action 1.1: Rebuild APK with Latest Code
```bash
cd field_check
flutter clean
flutter pub get
flutter build apk --release
```

**Why:** Code has been fixed but APK was never rebuilt. Installed app still shows old bugs.

**Expected Result:** 
- ✅ Geofence exceptions fixed
- ✅ Task assignment working
- ✅ Register button hidden
- ✅ Geofence list scrollable
- ✅ Location search working
- ✅ Duplicate FAB removed

**Time:** 15-30 minutes

---

### Action 1.2: Fix Report Query Parameter
**File:** `field_check/lib/services/report_service.dart`

**Problem:** Frontend doesn't pass `?type=attendance` parameter, so backend returns 0 results

**Fix:**
```dart
// Current (WRONG):
Future<List<Report>> getReports() async {
  final response = await http.get(
    Uri.parse('$baseUrl/api/reports'),
    headers: _getHeaders(),
  );
  // Returns empty list!
}

// Fixed (CORRECT):
Future<List<Report>> getReports() async {
  final response = await http.get(
    Uri.parse('$baseUrl/api/reports?type=attendance'),
    headers: _getHeaders(),
  );
  // Now returns actual reports!
}
```

**Verification:** 
```
1. Login as admin
2. Go to Reports tab
3. Should show attendance reports (not empty)
```

**Time:** 5 minutes

---

### Action 1.3: Fix Export Controller Field Names
**File:** `backend/controllers/exportController.js`

**Problem:** Controller uses wrong field names, causing export errors

**Fix:** Map exact MongoDB field names to export columns:
```javascript
// Verify these match your MongoDB schema:
const reportFields = {
  '_id': 'Report ID',
  'employeeId': 'Employee ID',
  'taskId': 'Task ID',
  'date': 'Date',
  'grade': 'Grade',
  'comments': 'Comments',
  'attachments': 'Attachments'
  // Match your actual schema fields!
};
```

**How to verify fields:**
```bash
# Check MongoDB schema in compass or run:
db.reports.findOne() # See actual field names
```

**Time:** 10 minutes

---

## 🔴 PHASE 2: FIX HIGH-PRIORITY VALIDATION (2-3 hours)

### Action 2.1: Add Sync Endpoint Validation
**File:** `backend/server.js` (sync endpoint)

**Problem:** Endpoint accepts any data without validation

**Fix:**
```javascript
app.post('/sync', authenticate, async (req, res) => {
  // VALIDATE input
  const { data } = req.body;
  
  if (!data || !Array.isArray(data)) {
    return res.status(400).json({ error: 'data must be an array' });
  }
  
  if (data.length === 0) {
    return res.status(400).json({ error: 'data cannot be empty' });
  }
  
  // NOW process safe data
  try {
    const results = await Promise.all(data.map(item => saveItem(item)));
    res.json({ success: true, count: results.length });
  } catch (error) {
    console.error('Sync error:', error);
    res.status(500).json({ error: 'Sync failed' });
  }
});
```

**Time:** 15 minutes

---

### Action 2.2: Add HTTP Timeouts to All Requests
**File:** `field_check/lib/services/http_util.dart`

**Problem:** HTTP requests hang forever if server doesn't respond

**Fix:** Add timeout to every HTTP call:
```dart
// Apply to ALL methods: get, post, put, delete
Future<Response> get(String url) async {
  final client = http.Client();
  try {
    return await client.get(
      Uri.parse(url),
      headers: _getHeaders(),
    ).timeout(
      Duration(seconds: 30),
      onTimeout: () => throw TimeoutException('Request timeout'),
    );
  } finally {
    client.close();
  }
}
```

**Files to update:**
- `services/http_util.dart` - ALL HTTP methods
- `services/api_service.dart` - If separate
- Any other service making HTTP calls

**Time:** 20 minutes

---

### Action 2.3: Fix Socket.io Auto-Reconnection
**File:** `field_check/lib/services/geofence_service.dart`

**Problem:** WebSocket disconnects and never reconnects

**Fix:**
```dart
void _initSocket() {
  socket = IO.io(baseUrl, <String, dynamic>{
    'transports': ['websocket'],
    'autoConnect': true,
    'reconnection': true,           // ← ADD THIS
    'reconnectionDelay': 1000,      // ← ADD THIS
    'reconnectionDelayMax': 5000,   // ← ADD THIS
    'reconnectionAttempts': 5,      // ← ADD THIS
  });
  
  socket.on('disconnect', (_) {
    print('Socket disconnected, will auto-reconnect');
  });
}
```

**Time:** 10 minutes

---

## 🟡 PHASE 3: SECURITY & STABILITY (2-3 hours)

### Action 3.1: Secure CORS Configuration
**File:** `backend/server.js`

**Current (INSECURE):**
```javascript
app.use(cors({ origin: '*' })); // ← DANGEROUS
```

**Fixed (SECURE):**
```javascript
app.use(cors({ 
  origin: process.env.NODE_ENV === 'production' 
    ? 'https://your-frontend-domain.com'
    : 'http://localhost:3000',
  credentials: true,
  methods: ['GET', 'POST', 'PUT', 'DELETE'],
  allowedHeaders: ['Content-Type', 'Authorization']
}));
```

**Time:** 5 minutes

---

### Action 3.2: Enable Rate Limiting
**File:** `backend/server.js`

**Add to server startup:**
```javascript
const rateLimit = require('express-rate-limit');

const limiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 100, // limit each IP to 100 requests per windowMs
  message: 'Too many requests, please try again later'
});

app.use(limiter);

// Stricter limit for auth endpoints
const authLimiter = rateLimit({
  windowMs: 60 * 1000, // 1 minute
  max: 5, // 5 attempts per minute
});

app.post('/auth/login', authLimiter, authController.login);
app.post('/auth/register', authLimiter, authController.register);
```

**Time:** 10 minutes

---

### Action 3.3: Add Password Strength Validation
**File:** `backend/controllers/userController.js`

**Add to password creation/reset:**
```javascript
function validatePasswordStrength(password) {
  const regex = /^(?=.*[a-z])(?=.*[A-Z])(?=.*\d).{8,}$/;
  // Requires: 1 lowercase, 1 uppercase, 1 digit, 8+ chars
  
  if (!regex.test(password)) {
    throw new Error('Password must be 8+ characters with uppercase, lowercase, and number');
  }
}

// In register and resetPassword:
validatePasswordStrength(password);
const hashedPassword = await bcrypt.hash(password, 10);
```

**Time:** 10 minutes

---

## 📋 IMPLEMENTATION ORDER

**If you only have 1 hour:** Do Phase 1 only (Actions 1.1, 1.2, 1.3)
- Rebuilding APK fixes 6 bugs immediately
- Report query fix shows data
- Export controller restores functionality

**If you have 3 hours:** Do Phase 1 + Phase 2
- Unblock the app completely
- Add critical error handling
- Prevent request hangs

**If you have 6+ hours:** Do all three phases
- Production-ready security
- Full stability improvements
- Battle-tested configuration

---

## ✅ VERIFICATION CHECKLIST

After each phase, test:

**Phase 1 Complete When:**
- [ ] APK rebuilt successfully
- [ ] Reports tab shows attendance data
- [ ] Export functionality works
- [ ] App installed and tested on device/emulator

**Phase 2 Complete When:**
- [ ] Sync endpoint rejects bad data
- [ ] HTTP timeouts prevent hangs
- [ ] WebSocket reconnects automatically
- [ ] Tested all 3 fixes on running app

**Phase 3 Complete When:**
- [ ] CORS configured for production domain
- [ ] Rate limiting active (test with repeated requests)
- [ ] Password validation enforces strength
- [ ] Security headers in place

---

## 🐛 REMAINING ISSUES (Lower Priority)

| Issue | Root Cause | Fix | Priority |
|-------|-----------|-----|----------|
| Auto check-in on login | Dashboard initialization logic | Debug dashboard provider | MEDIUM |
| Avatar upload returns fake URL | Frontend doesn't use upload endpoint | Implement multipart upload | MEDIUM |
| Location search not working | Geocoding not initialized | Add geocoding plugin init | LOW |
| Empty catch blocks | Scattered throughout | Audit and log errors | LOW |
| Offline queue missing | No background sync | Add Hive local cache + sync logic | LOW |

---

## 📞 Support

If stuck on any action:
1. Check the specific file path mentioned
2. Look for matching code patterns in the file
3. See the validation section for how to test
4. Ask for help debugging specific errors

Good luck! This plan should get your app to production.
