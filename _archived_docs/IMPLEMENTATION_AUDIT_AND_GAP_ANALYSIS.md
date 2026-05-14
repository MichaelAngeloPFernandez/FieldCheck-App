---
name: FieldCheck Implementation Audit & Gap Analysis
date: April 26, 2026
purpose: Identify what's built, what's broken, and implementation priority
---

# FieldCheck-App: Implementation Audit & Gap Analysis

## Executive Summary

✅ **Good News:** Geofence validation and socket.io infrastructure are already built.

🔴 **Bad News:** Critical showstoppers exist:
- **Attachments are ephemeral** (lost on server restart) - MUST FIX FIRST
- **Templates system missing** (hardcoded schemas only) - Required for clients
- **No RBAC beyond admin/employee** (no manager role, no multi-tenant)
- **Audit logs missing** (no accountability trail)
- **Offline sync incomplete** (only attendance, no retry)

**Recommendation:** Start with attachment persistence (Day 1), then templates (Days 2-3).

---

## 1. Feature Status Matrix

### Geofence Implementation

**Status:** ✅ **FUNCTIONAL** 

**What Works:**
- ✅ GPS distance validation using Haversine formula (tested)
- ✅ Server rejects check-in outside radius (403 error)
- ✅ Distance calculated correctly: `R * atan2(√a, √(1-a))`

**Critical Issues:**
1. ❌ **Code duplication** - Haversine defined 4+ times:
   - [backend/controllers/attendanceController.js](backend/controllers/attendanceController.js#L41-L53)
   - [backend/controllers/locationController.js](backend/controllers/locationController.js#L693-L703)
   - [backend/server.js](backend/server.js#L111-L118)
   - [backend/controllers/availabilityController.js](backend/controllers/availabilityController.js#L13-L23)
   
   **Fix:** Extract to `utils/geoUtils.js` and reuse

2. ❌ **No GPS accuracy validation** - Accepts low-accuracy GPS (±100m)
   
   **Current:** Takes GPS at face value
   
   **Should be:** `if (gps.accuracy > 50) reject` (don't trust low-accuracy readings)

3. ❌ **Checkout bypasses geofence** 
   
   **Current:** [attendanceController.js line 319](backend/controllers/attendanceController.js#L319) comment: `// skip geofence checks on checkout`
   
   **Issue:** Workers can checkout from anywhere (defeats purpose)
   
   **Fix:** Require geofence on both check-in AND checkout

4. ⚠️ **Floating-point precision** - Boundary check might fail
   
   **Current:** `if (distanceMeters > geofence.radius)`
   
   **Should be:** `if (distanceMeters > geofence.radius + 5) // 5m tolerance`

**Testing Recommendation:**
```bash
# Test scenarios:
1. Check-in 10m inside geofence → ✅ should succeed
2. Check-in 10m outside geofence → ❌ should reject  
3. Check-in on boundary (±1m) → Should succeed (add tolerance)
4. Low accuracy GPS (±100m) → Should reject with "GPS accuracy too low"
5. Checkout outside geofence → Should reject (currently bypassed)
```

**In Product Strategy Blueprint:** ✅ Geofence already exists; needs accuracy validation + checkout fix

---

### Attachment/Upload System

**Status:** 🔴 **BROKEN - CRITICAL BLOCKER**

**Current State:**
- Attachments stored as **URL strings only** in MongoDB
- **NO file upload endpoint** - only proxy fetch endpoint
- **NO Cloudinary/S3** - zero cloud integration
- **Ephemeral storage** - files lost on server restart
- Files expected to be on remote server (hardcoded whitelist)

**Where Stored:**
- Report model: [backend/models/Report.js](backend/models/Report.js#L15) → `attachments: [String]`
- Task model: [backend/models/Task.js](backend/models/Task.js#L47-L51) → `{ images, documents, others: [String] }`

**Current Endpoints:**
```
GET /api/uploads/proxy?url=...
- Takes external URL
- Fetches from whitelist (fieldcheck-*.onrender.com)
- Returns to client
- Sets Cache-Control: no-store
- NO persistent storage
```

**What Happens on Server Restart:**
- 🔴 All attachment URLs become invalid
- 🔴 Cached files evicted
- 🔴 No way to retrieve past attachments

**What's Missing:**
1. ❌ Multipart file upload endpoint
2. ❌ Cloudinary or S3 integration
3. ❌ Signed URL generation
4. ❌ File checksum validation (dedup)
5. ❌ File size/type validation
6. ❌ Attachment metadata table
7. ❌ Authorization checks on retrieval

**In Product Strategy Blueprint:** 🔴 **CRITICAL** - Must implement Day 1

**Implementation Checklist:**
- [ ] Create Cloudinary or S3 account
- [ ] Create `Attachment` model with: `{ url, provider, checksum, uploaded_by, ticket_id, created_at }`
- [ ] POST `/api/uploads/signed-url` endpoint
- [ ] POST `/api/tickets/:id/attachments` endpoint
- [ ] GET `/api/attachments/:id/download` endpoint
- [ ] Update Report & Task models to reference Attachment IDs
- [ ] Test: Upload → restart server → retrieve file ✅

---

### Socket.io Implementation

**Status:** ✅ **DONE** with ⚠️ security concerns

**What Works:**
- ✅ Singleton pattern verified (single instance across app)
- ✅ JWT-based authentication on socket connect
- ✅ User/role-based room joins
- ✅ Unread counts calculated per scope (5 scopes)
- ✅ Events: `unreadCounts`, `newReport`, `employeeLocationsUpdate`, etc.
- ✅ Multiple sockets per user supported
- ✅ 3-second grace period for reconnect

**Code Location:** [backend/server.js](backend/server.js#L54-L270)

**Security Issues:**
1. ❌ **CORS wide open:** `origin: "*"` allows ANY domain
   
   **Current:** 
   ```javascript
   cors: { origin: "*" }
   ```
   
   **Should be:**
   ```javascript
   cors: { 
     origin: process.env.FRONTEND_URL,
     credentials: true 
   }
   ```

2. ❌ **No per-event authorization** - Only checks token on initial connect
   
   **Risk:** Can't revoke permissions without disconnect

3. ⚠️ **Potential duplicate notifications** - No deduplication in emit logic
   
   **Risk:** User sees same notification twice

4. ⚠️ **Complex throttle logic** - Presence notifications throttled but logic is convoluted

**In Product Strategy Blueprint:** ✅ Already done; just needs security hardening

**Security Improvements:**
- [ ] Change CORS from `*` to specific domain
- [ ] Add per-event permission checks
- [ ] Add event deduplication
- [ ] Add rate limiting on events
- [ ] Test: Malicious domain trying to connect → should reject

---

### RBAC (Role-Based Access Control)

**Status:** 🟡 **PARTIAL** - Only basic roles, no multi-tenant

**Current Implementation:**
- Roles: `employee`, `admin` (only 2!)
- Model: [backend/models/User.js](backend/models/User.js#L72) → `role: { enum: ['employee', 'admin'] }`
- Middleware: [backend/middleware/authMiddleware.js](backend/middleware/authMiddleware.js)
- Routes protected: `router.get('/', protect, admin, handler)`

**What Works:**
- ✅ JWT validation
- ✅ Role-based route protection
- ✅ Simple "admin vs everyone else" model
- ✅ Stored in database

**What's Missing:**
1. ❌ **No manager role** (requested in strategy but NOT implemented)
2. ❌ **No granular permissions** (can't grant "view-only" or "edit reports only")
3. ❌ **No multi-tenant scoping** 
   - No `company_id` field in User schema
   - No `department_id` field
   - All admins are GLOBAL (see all data)
4. ❌ **No row-level security** (can't check if user owns specific resource)
5. ❌ **No permission inheritance** (no role hierarchy)
6. ❌ **No service account auth** (no API keys for automation)
7. ❌ **No permission audit** (no logging of permission changes)

**Current Access Control:**
```javascript
// Admin: can see ALL users, geofences, tasks, reports
// Employee: can only see own data (checked via req.user._id)

router.get('/', protect, admin, getAttendanceRecords)
// Only admins allowed; employees get 401
```

**For Product Strategy (Multi-Tenant):**
Need to add:
```javascript
// User schema update
company_id: { type: ObjectId, ref: 'Company', required: true },
role: { enum: ['admin', 'manager', 'field_worker'], default: 'field_worker' },
permissions: [String]  // Granular permissions

// Middleware update
const companyScoped = (req, res, next) => {
  if (req.user.company_id !== req.params.companyId) {
    return res.status(403).json({ error: 'Access denied' })
  }
  next()
}
```

**In Product Strategy Blueprint:** 🟡 Need major updates for multi-tenant

**Implementation Checklist:**
- [ ] Add `company_id` to User schema
- [ ] Add `manager` role to enum (in addition to admin, employee)
- [ ] Create `Permission` model with granular permissions
- [ ] Add company-scoping middleware
- [ ] Add RBAC middleware for permission checks
- [ ] Migrate existing users to companies (batch script)
- [ ] Test: User A can't access User B's data from different company

---

### Templates/Dynamic Forms System

**Status:** 🔴 **COMPLETELY MISSING**

**Current State:**
- Report schema: [backend/models/Report.js](backend/models/Report.js#L1-L30) - HARDCODED fields
- NO template model
- NO form builder UI
- NO dynamic field system

**Hardcoded Report Fields:**
```javascript
{
  type: { enum: ['task', 'attendance'] },
  task: ObjectId,
  attendance: ObjectId,
  employee: ObjectId,
  geofence: ObjectId,
  content: String,
  attachments: [String],
  status: { enum: ['submitted', 'reviewed'] },
  grade: { enum: ['poor', 'good', 'excellent'] },
  gradeComment: String
}
```

**To Add Custom Fields Today:**
1. Schema migration
2. Code changes
3. Backend rebuild
4. Frontend rebuild
5. Deploy

**What's Needed (From Strategy):**
1. ✅ JSON Schema validation library (AJV) - not added yet
2. ❌ TicketTemplate model
3. ❌ Template CRUD endpoints
4. ❌ Dynamic form renderer (Flutter)
5. ❌ Admin template editor UI
6. ❌ Template versioning

**In Product Strategy Blueprint:** 🔴 **CORE FEATURE** - Must implement Days 2-3

**Implementation Checklist:**
- [ ] `npm install ajv` (backend)
- [ ] Create TicketTemplate model with JSON Schema
- [ ] POST/GET/PATCH template endpoints
- [ ] Validation service using AJV
- [ ] Flutter DynamicFormRenderer widget
- [ ] Admin template editor screen
- [ ] Seeded aircon template data
- [ ] Test: Create template → Field worker renders form → Submit validates against schema

---

### Audit Logs / Change Tracking

**Status:** 🔴 **NOT IMPLEMENTED**

**Current State:**
- All models have: `timestamps: true` (auto `createdAt`, `updatedAt`)
- Only 2 models have `createdBy` field: Conversation, Geofence
- NO audit collection
- NO change history
- NO action logging

**Questions You CAN'T Answer Today:**
- ❌ "Who deleted this report?"
- ❌ "When was geofence radius changed from 100m to 50m?"
- ❌ "What changes did the admin make?"
- ❌ "Full history of this attendance record?"

**What's Needed (From Strategy):**
- AuditLog model: `{ resource_type, resource_id, action, actor_id, changes, created_at }`
- Middleware to log all changes
- GET `/api/audit-logs` endpoint
- Optional: immutable DB log (append-only)

**In Product Strategy Blueprint:** 🟡 Medium priority (Days 4-5)

---

### Offline Queue / Sync System

**Status:** 🟡 **PARTIALLY IMPLEMENTED** - Limited scope

**What Works:**
- ✅ Offline data persisted to SharedPreferences
- ✅ Connectivity detection (Connectivity plugin)
- ✅ Sync triggered on reconnect
- ✅ Endpoint: `POST /api/sync`

**Where Implemented:**
- Frontend: [field_check/lib/services/sync_service.dart](field_check/lib/services/sync_service.dart)
- Model: [field_check/lib/models/offline_data_model.dart](field_check/lib/models/offline_data_model.dart)
- Trigger: [field_check/lib/main.dart](field_check/lib/main.dart#L132)

**What's Broken:**
1. ❌ **ONLY attendance syncs** - Tasks, reports, locations NOT queued
2. ❌ **NO retry logic** - Fails once = permanent loss
3. ❌ **NO exponential backoff** - Doesn't retry with delays
4. ❌ **NO conflict resolution** - What if server version conflicts with offline?
5. ❌ **NO queue size limits** - Could grow unbounded
6. ❌ **Silent failure** - Just prints error, no UI feedback
7. ❌ **NO progress UI** - User doesn't know sync is happening
8. ❌ **Backend endpoint not fully implemented** - `/api/sync` handler is minimal

**Current Flow:**
```dart
// Collects attendance only
final attendanceItems = []
for (var data in offlineRecords) {
  if (data.dataType == 'attendance') {
    attendanceItems.add(...)
  }
}

// Sends to backend
await http.post('/api/sync', body: { attendance: attendanceItems })
```

**Data Loss Risk:**
- 🔴 App crash before sync = data lost (only persisted on disk during sync)
- 🔴 Network timeout = silent failure
- 🔴 Server error = silent failure

**In Product Strategy Blueprint:** 🟡 Optional (Day 5)

**Enhancement Checklist:**
- [ ] Queue all data types (not just attendance)
- [ ] Add exponential backoff retry
- [ ] Add conflict resolution (server-wins vs last-write-wins)
- [ ] Add queue size limits
- [ ] Add sync progress UI
- [ ] Add error notifications
- [ ] Test: Create offline data → kill network → reconnect → should sync

---

## 2. Implementation Priority Roadmap

### CRITICAL PATH (Must Do)

**Day 1: Durable Attachments** ⚠️ BLOCKER
```
Estimated: 8 hours
Files to create: storage_service.js, signed-url endpoint, attachment model
Files to modify: Report.js, Task.js, attendanceController.js
Deliverable: Upload photo → server restart → retrieve photo ✅
```

**Day 2: Template System** ⚠️ BLOCKER  
```
Estimated: 8 hours
Files to create: TicketTemplate.js, template routes, AJV validator
Files to modify: ticketController.js
Deliverable: Create aircon template → field worker renders form ✅
```

**Day 3: Flutter Dynamic Forms**
```
Estimated: 8 hours
Files to create: DynamicFormRenderer.dart, AttachmentPicker.dart
Files to modify: TicketListScreen.dart, report upload flow
Deliverable: Template schema → Flutter form with validation ✅
```

### HIGH PRIORITY (Should Do)

**Day 4: RBAC & Company Scoping**
```
Estimated: 8 hours
Files to create: companyScoping.js middleware, permission model
Files to modify: User.js, all controllers
Deliverable: User A can't access User B's tickets from different company ✅
```

**Day 4-5: Socket Security & Audit Logs**
```
Estimated: 6 hours each
Deliverable: Secure CORS + Full change history ✅
```

### MEDIUM PRIORITY (Nice to Have)

**Day 5: Geofence Improvements**
```
Estimated: 4 hours
Tasks: Deduplicate haversine, add accuracy validation, fix checkout
Deliverable: Robust geofence with all validation ✅
```

**Day 5: Offline Queue Enhancements**
```
Estimated: 4 hours
Tasks: Add retry logic, all data types, progress UI
Deliverable: Reliable offline sync ✅
```

---

## 3. Code Duplication to Eliminate

### Haversine Formula (Calculate GPS Distance)

**Currently defined in 4 places:**
1. [backend/controllers/attendanceController.js](backend/controllers/attendanceController.js#L41-L53)
2. [backend/controllers/locationController.js](backend/controllers/locationController.js#L693-L703)
3. [backend/server.js](backend/server.js#L111-L118)
4. [backend/controllers/availabilityController.js](backend/controllers/availabilityController.js#L13-L23)

**Fix:** Create `backend/utils/geoUtils.js`
```javascript
// utils/geoUtils.js
const EARTH_RADIUS_METERS = 6371000;

function calculateDistance(lat1, lng1, lat2, lng2) {
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
            Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) *
            Math.sin(dLng / 2) * Math.sin(dLng / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return EARTH_RADIUS_METERS * c;
}

module.exports = { calculateDistance };
```

**Then import in all 4 files:**
```javascript
const { calculateDistance } = require('../utils/geoUtils');
```

**Benefit:** Single source of truth, easier to fix bugs, consistency

---

## 4. Geofence Checkout Issue

**Current Behavior:** [backend/controllers/attendanceController.js](backend/controllers/attendanceController.js#L319)
```javascript
// Line 319 comment: "skip geofence checks on checkout"
// Workers can checkout from anywhere
```

**Why This is Bad:**
- Defeats purpose of geofence (proving work location)
- Can clock out at home instead of site

**Fix:**
```javascript
// BEFORE (current - NO geofence check)
async checkOut(req, res) {
  // skip geofence checks on checkout
  await Attendance.updateOne(...);
}

// AFTER (proposed - REQUIRE geofence on checkout too)
async checkOut(req, res) {
  const { gps, geofence_id } = req.body;
  
  // Validate GPS within geofence
  const geofence = await Geofence.findById(geofence_id);
  const distance = calculateDistance(gps, geofence.center);
  
  if (distance > geofence.radius) {
    return res.status(400).json({ 
      error: 'Must checkout within geofence',
      distance,
      allowed_radius: geofence.radius
    });
  }
  
  // Now checkout
  await Attendance.updateOne(...);
}
```

---

## 5. GPS Accuracy Validation (Missing)

**Current:** Accepts any GPS coordinate
```javascript
// Takes GPS at face value
const { lat, lng } = req.body.gps;
const distance = calculateDistance(lat, lng, ...);
```

**Problem:** Low-accuracy GPS readings (±100m) could bypass geofence
- Mobile GPS in urban canyon: accuracy could be ±50-150m
- Building: GPS error larger than geofence radius

**Solution:** Check accuracy field
```javascript
// BEFORE (current - no accuracy check)
const distance = calculateDistance(lat, lng, ...);

// AFTER (proposed)
const { lat, lng, accuracy } = req.body.gps;

// Reject low accuracy readings
if (accuracy > 50) {  // 50 meter threshold
  return res.status(400).json({
    error: 'GPS signal too weak',
    accuracy,
    required: '< 50m'
  });
}

const distance = calculateDistance(lat, lng, ...);
```

---

## 6. Testing Checklist Before Deploy

### Geofence Tests
```
✅ Check-in 10m inside geofence → Success
❌ Check-in 100m outside geofence → Rejected
✅ Check-in on boundary (±1m) → Success (with tolerance)
❌ Check-in with low accuracy GPS → Rejected
❌ Checkout outside geofence → Rejected (after fix)
```

### Attachment Tests
```
✅ Upload photo → store in Cloudinary
✅ Server restart → photo still retrievable
❌ Unauthorized user → 403 forbidden
✅ Download attachment → correct file
✅ Delete ticket → attachment still exists (not cascading delete)
```

### Template Tests
```
✅ Create aircon template
✅ Validate ticket data against schema → accept valid, reject invalid
✅ Field worker renders form from template
✅ Submit form → server validates and saves
```

### RBAC Tests
```
✅ User A can't access User B's data (different companies)
✅ Field worker can't create templates (admin only)
✅ Manager can review tickets (after manager role added)
```

### Socket Tests
```
✅ Unread count updates on new notification
✅ Multiple sockets per user → count correct
✅ Socket reconnects automatically
✅ Old CORS exploit (origin: *) → reject from malicious domain
```

---

## 7. Quick Migration Script Needs

### 1. Add company_id to Existing Users
```javascript
// Run once: batch assign all users to "default company"
db.users.updateMany({}, { $set: { company_id: ObjectId(...) } })
```

### 2. Create Template for Aircon Service
```javascript
db.ticket_templates.insertOne({
  company_id: ObjectId(...),
  name: "Aircon Cleaning Service",
  json_schema: { /* full schema */ },
  workflow: { ... },
  sla_seconds: 86400,
  visibility: "private",
  version: 1,
  created_by: admin_id,
  created_at: new Date()
})
```

### 3. Deduplicate Haversine Functions
```bash
# Automated refactor
grep -n "Math.sin(dLat" backend/**/*.js | head -20
# Identify all occurrences, extract to utils/geoUtils.js
```

---

## Conclusion

**Summary of Work:**

| Task | Status | Days | Priority |
|------|--------|------|----------|
| Fix attachments persistence | 🔴 CRITICAL | 1 | P0 |
| Build template system | 🔴 CRITICAL | 2 | P0 |
| Flutter form renderer | 🔴 CRITICAL | 1 | P0 |
| Add RBAC + multi-tenant | 🟡 HIGH | 1 | P1 |
| Fix geofence issues | 🟡 HIGH | 0.5 | P2 |
| Add audit logs | 🟡 HIGH | 0.5 | P1 |
| Harden socket security | 🟡 MEDIUM | 0.5 | P2 |
| Improve offline sync | 🟡 MEDIUM | 0.5 | P3 |

**Total:** ~8 days for one developer (can parallelize to ~4-5 days with two)

**Go-Live Checklist:**
- [ ] All critical path work complete (attachments, templates, RBAC)
- [ ] Geofence validated and checkout fixed
- [ ] Demo script works end-to-end
- [ ] Fallback data seeded
- [ ] Security audit complete (CORS, RBAC, multi-tenant)
- [ ] Load testing (handle concurrent submissions)

---

**Next Step:** Choose implementation approach:
1. **SequentialApproach:** Do attachment fixes first, then templates (safer, clearer)
2. **ParallelApproach:** Two devs: one on attachments + socket, one on templates + RBAC (faster)

Recommend: **Sequential with AI assistance** - Use agent to parallelize search and analysis while you build.
