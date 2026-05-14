---
name: FieldCheck Implementation Plan - Master Summary
date: April 26, 2026
status: READY FOR IMPLEMENTATION
---

# FieldCheck Implementation Plan - Master Summary & Action Plan

## Documents Created (Your Blueprint)

You now have 4 comprehensive guides:

1. **[PRODUCT_STRATEGY_BLUEPRINT.md](PRODUCT_STRATEGY_BLUEPRINT.md)** (60 pages)
   - Complete product vision
   - All features (attachments, templates, RBAC, audit logs, etc.)
   - Full data models
   - API endpoint specifications
   - 5 ready-to-use JSON schemas (Aircon, Pest Control, Landscaping, POD, Telecom)
   - Sprint plan for all features

2. **[IMPLEMENTATION_AUDIT_AND_GAP_ANALYSIS.md](IMPLEMENTATION_AUDIT_AND_GAP_ANALYSIS.md)** (40 pages)
   - Feature-by-feature audit of current codebase
   - What's working ✅ vs what's broken ❌
   - Root causes and specific file locations
   - Code duplication issues
   - Security vulnerabilities
   - Testing checklist

3. **[AIRCON_TEMPLATE_IMPLEMENTATION_GUIDE.md](AIRCON_TEMPLATE_IMPLEMENTATION_GUIDE.md)** (20 pages)
   - **Focused implementation for your primary client**
   - Aircon Cleaning Service template only (extensible to others)
   - Ready-to-copy code snippets (backend, Flutter)
   - Complete data models
   - API implementation details
   - Seeding instructions
   - 3-day timeline with AI assistance

4. **This Document** - Your action plan

---

## Current State Summary

### What's WORKING ✅

| Feature | Status | Notes |
|---------|--------|-------|
| Geofence validation | ✅ | GPS distance calculated correctly, rejects out-of-bounds check-ins |
| Socket.io infrastructure | ✅ | Singleton pattern, user/role-based rooms, unread counts |
| Basic RBAC | ✅ | Admin vs Employee roles (but incomplete) |
| Offline sync (partial) | ✅ | Attendance data queued, syncs on reconnect |

### What's BROKEN 🔴 (Critical)

| Feature | Status | Impact | Blocker? |
|---------|--------|--------|----------|
| Durable attachments | ❌ MISSING | Photos lost on server restart | YES |
| Templates system | ❌ MISSING | Can't customize forms per client | YES |
| Multi-tenant RBAC | ❌ MISSING | All admins see all companies' data | YES |
| Audit logs | ❌ MISSING | No accountability trail | NO |

### What Needs Fixes 🟡 (Important)

| Issue | File | Priority |
|-------|------|----------|
| Geofence accuracy validation | attendanceController.js | HIGH |
| Geofence checkout bypass | attendanceController.js | HIGH |
| Haversine code duplication | 4 files | MEDIUM |
| CORS wide open | server.js | HIGH (security) |
| Offline sync limited to attendance | sync_service.dart | MEDIUM |

---

## Your Options

### Option A: Quick Win (Focus on Aircon Client Only)

**Scope:** Just implement the Aircon Cleaning template system, skip everything else for now.

**Timeline:** 3 days (one developer)

**What You'll Get:**
- ✅ Durable attachments (Cloudinary/S3)
- ✅ Aircon template + dynamic forms
- ✅ Demo-ready for your client
- ✅ Easily extensible to other services

**What You Won't Get:**
- ❌ Multi-tenant (still single company)
- ❌ Audit logs
- ❌ Complete RBAC
- ❌ Offline improvements

**Best For:** If you need to demo to the Aircon cleaning client ASAP

**Use:** [AIRCON_TEMPLATE_IMPLEMENTATION_GUIDE.md](AIRCON_TEMPLATE_IMPLEMENTATION_GUIDE.md)

---

### Option B: Complete Platform (All Features from Product Strategy)

**Scope:** Everything in the product strategy blueprint.

**Timeline:** 8 days (one developer) / 4-5 days (two developers in parallel)

**What You'll Get:**
- ✅ Durable attachments
- ✅ Template system (Aircon + templates for other services)
- ✅ Full multi-tenant RBAC
- ✅ Audit logs
- ✅ Enhanced offline sync
- ✅ Production-ready security

**Best For:** If you're building a long-term product platform

**Use:** [PRODUCT_STRATEGY_BLUEPRINT.md](PRODUCT_STRATEGY_BLUEPRINT.md) + [IMPLEMENTATION_AUDIT_AND_GAP_ANALYSIS.md](IMPLEMENTATION_AUDIT_AND_GAP_ANALYSIS.md)

---

### Option C: Hybrid (Quick Win + Foundation for Full Platform)

**Scope:** Do Aircon template (Option A), then incrementally add full features.

**Timeline:** 3 days (quick win) + ongoing

**Best For:** If you want working demo soon, but plan for scale

**Use:** Start with [AIRCON_TEMPLATE_IMPLEMENTATION_GUIDE.md](AIRCON_TEMPLATE_IMPLEMENTATION_GUIDE.md), then expand using [PRODUCT_STRATEGY_BLUEPRINT.md](PRODUCT_STRATEGY_BLUEPRINT.md)

---

## My Recommendation: Option C (Hybrid)

**Why:**
1. **Unblocks your Aircon client demo in 3 days** ✅
2. **Builds the right foundation** for future growth
3. **Lets you learn the system incrementally** 
4. **You can parallelize with AI** (one person builds, agent analyzes)

**Week 1:** Aircon template system (ready to show client)
**Week 2-3:** Add full RBAC, templates for other services, audit logs (production ready)

---

## The Critical Issues You MUST Fix

Based on the audit, here are the showstoppers:

### 1. Durable Attachments (BLOCKER #1)
**Current:** Photos lost on server restart
**Fix:** Use Cloudinary/S3 instead of ephemeral disk
**Effort:** 1 day
**Risk:** HIGH (data loss in production)
**See:** [AIRCON_TEMPLATE_IMPLEMENTATION_GUIDE.md - Part 2](AIRCON_TEMPLATE_IMPLEMENTATION_GUIDE.md#part-2-backend-api)

### 2. Template System (BLOCKER #2)
**Current:** Can't customize forms; everything hardcoded
**Fix:** Implement JSON Schema + dynamic form renderer
**Effort:** 2 days
**Risk:** HIGH (can't meet client requirements)
**See:** [AIRCON_TEMPLATE_IMPLEMENTATION_GUIDE.md - All Parts](AIRCON_TEMPLATE_IMPLEMENTATION_GUIDE.md)

### 3. Multi-Tenant Scoping (SECURITY ISSUE)
**Current:** Admins can see all companies' data
**Fix:** Add company_id to all queries, scoping middleware
**Effort:** 1 day
**Risk:** CRITICAL (data breach)
**See:** [IMPLEMENTATION_AUDIT_AND_GAP_ANALYSIS.md - Section 4](IMPLEMENTATION_AUDIT_AND_GAP_ANALYSIS.md#4-rbac-role-based-access-control)

---

## Implementation Roadmap (Recommended)

### Phase 1: Quick Win (Days 1-3) - Demo Ready

```
Day 1: Durable Attachments
  - Add Cloudinary SDK
  - Implement signed URL endpoint
  - Create Attachment model
  - Test: Upload photo → server restart → retrieve ✅

Day 2: Template Model + Validation
  - Create TicketTemplate model
  - Implement AJV JSON Schema validation
  - Add POST /api/templates endpoint
  - Add POST /api/tickets with validation
  - Seed Aircon template

Day 3: Flutter Dynamic Forms
  - Build DynamicFormRenderer widget
  - Create AttachmentPicker widget
  - Connect upload flow
  - Test end-to-end

DEMO READY ✅
```

### Phase 2: Production Ready (Days 4-5) - Full Platform

```
Day 4: RBAC + Multi-Tenant + Security
  - Add company_id to User schema
  - Implement company-scoping middleware
  - Add manager role
  - Secure CORS (no more *)
  - Fix geofence issues

Day 5: Audit Logs + Polish
  - Implement AuditLog model
  - Add middleware to log all changes
  - Seed production-like data
  - Final testing and hardening
  - Write deployment guide

PRODUCTION READY ✅
```

---

## Files You Need to Create/Modify

### Phase 1 (Quick Win)

**New Files:**
- `backend/models/TicketTemplate.js`
- `backend/models/Attachment.js`
- `backend/services/StorageService.js`
- `backend/routes/templates.js`
- `backend/routes/tickets.js`
- `backend/routes/uploads.js`
- `field_check/lib/widgets/DynamicFormRenderer.dart`
- `field_check/lib/widgets/AttachmentPickerWidget.dart`
- `backend/seeds/aircon_template.js`

**Modified Files:**
- `backend/models/Ticket.js` (add template_id reference)
- `backend/models/Report.js` (update attachment handling)
- `field_check/lib/services/api_service.dart` (add new endpoints)

### Phase 2 (Production Ready)

**New Files:**
- `backend/models/AuditLog.js`
- `backend/models/Company.js`
- `backend/middleware/companyScoping.js`
- `backend/services/AuditLogService.js`
- `backend/utils/geoUtils.js` (deduplicate Haversine)

**Modified Files:**
- `backend/models/User.js` (add company_id, manager role)
- `backend/middleware/authMiddleware.js` (RBAC middleware)
- `backend/server.js` (CORS fix)
- Multiple controllers (add company scoping)

---

## Success Criteria

### After Day 3 (Quick Win - Demo Ready):
- [ ] Upload photo → persists after server restart ✅
- [ ] Create Aircon template in admin UI
- [ ] Field worker renders form from template
- [ ] Field worker submits ticket with photos
- [ ] Ticket shows in admin dashboard
- [ ] Demo script works end-to-end (5 min)
- [ ] Client sees it works! 🎉

### After Day 5 (Full Platform):
- [ ] All above + 
- [ ] Users can't access other companies' data
- [ ] Audit log shows who did what when
- [ ] Manager role works correctly
- [ ] Socket security hardened
- [ ] Geofence accuracy validated
- [ ] Production deployment ready ✅

---

## How to Use the AI Agent

**Before you start:** Use `@fieldcheck-dev` agent for help.

### For Quick Win Phase:

```
@fieldcheck-dev
I'm implementing the Aircon Cleaning template system.
Help me:
1. Create the TicketTemplate model
2. Implement the signed URL endpoint for photo uploads
3. Build the DynamicFormRenderer widget

Use this guide: [link to AIRCON_TEMPLATE_IMPLEMENTATION_GUIDE.md]
```

### For RBAC + Multi-Tenant:

```
@fieldcheck-dev
I need to add multi-tenant scoping to FieldCheck.
Currently all admins see all companies' data (security issue).

Help me:
1. Add company_id to User schema
2. Create company-scoping middleware
3. Add manager role
4. Fix geofence issues (checkout bypass, accuracy validation)

Reference: [link to IMPLEMENTATION_AUDIT_AND_GAP_ANALYSIS.md]
```

### For Specific Bugs:

```
@fieldcheck-dev
Geofence check-in is bypassed on checkout (security issue).
File: backend/controllers/attendanceController.js line 319
How do I fix this and ensure checkout also requires geofence?
```

---

## Key Decisions to Make NOW

### Decision 1: Cloud Storage Provider
**Options:**
- **Cloudinary** (recommended) - Simpler setup, better for photos
- **S3** (AWS) - More control, but more complex
- **Local cloud** - Not recommended (ephemeral)

**Recommendation:** Use **Cloudinary** for quick setup

```bash
# Sign up at https://cloudinary.com
# Get API key and upload URL
# npm install cloudinary
```

### Decision 2: Parallel vs Sequential Implementation
**Options:**
- **Sequential** (one person builds) - Clear flow, easier to debug
- **Parallel** (two people) - Faster, but coordination needed

**Recommendation:** **Sequential with AI** - You implement, agent researches/analyzes in parallel

### Decision 3: Demo Timing
**Question:** When do you need to demo to the Aircon client?
- This week? → Do Phase 1 only (Quick Win)
- Next month? → Do full Phase 1 + 2 (Complete Platform)

**Recommended:** Demo Phase 1 results in 3 days, then enhance

---

## Potential Issues & Mitigations

| Issue | Mitigation |
|-------|-----------|
| Cloudinary account setup delays | Sign up TODAY, use free tier for testing |
| MongoDB connection issues | Verify MongoDB Atlas connection first |
| Flutter dependency conflicts | Clean build: `flutter clean && flutter pub get` |
| Backend compilation errors | Run `npm install` and check Node version |
| Time overruns | AI assistance can parallelize research |

---

## Testing Before Production

```bash
# Unit tests (backend)
npm test backend/tests/template.test.js
npm test backend/tests/ticket.test.js

# Integration tests (backend → Flutter)
flutter test test/ticket_creation_test.dart

# Manual testing
1. Create Aircon template (admin)
2. Create ticket (field worker)
3. Upload photo (should persist)
4. Submit form (should validate)
5. View ticket (admin should see audit trail)
```

---

## Next Steps: Your Action Plan

### TODAY:
- [ ] Read [AIRCON_TEMPLATE_IMPLEMENTATION_GUIDE.md](AIRCON_TEMPLATE_IMPLEMENTATION_GUIDE.md) (30 min)
- [ ] Decide: Option A, B, or C? (5 min)
- [ ] If Cloudinary: Sign up and get API keys (15 min)
- [ ] Review [IMPLEMENTATION_AUDIT_AND_GAP_ANALYSIS.md](IMPLEMENTATION_AUDIT_AND_GAP_ANALYSIS.md) (30 min)

### TOMORROW:
- [ ] Start Day 1 (Durable Attachments)
- [ ] Use `@fieldcheck-dev` agent for implementation help
- [ ] Test: Upload photo → restart → retrieve

### END OF WEEK:
- [ ] Demo Phase 1 to Aircon client (or internally)
- [ ] Decide: Continue to Phase 2?

---

## Quick Reference: Key Commands

```bash
# Start development server
cd backend && npm start

# Run Flutter app
cd field_check && flutter run

# Test backend
npm test

# Check errors
npm run lint

# Build APK (when ready)
cd field_check && flutter build apk --release

# Seed data
node backend/seeds/aircon_template.js
```

---

## Resources You Have

1. **Custom Agent:** `@fieldcheck-dev` - Use for implementation help
2. **Code Examples:** All in [AIRCON_TEMPLATE_IMPLEMENTATION_GUIDE.md](AIRCON_TEMPLATE_IMPLEMENTATION_GUIDE.md) ready to copy/paste
3. **Architecture Docs:** [PRODUCT_STRATEGY_BLUEPRINT.md](PRODUCT_STRATEGY_BLUEPRINT.md) explains every design decision
4. **Audit Results:** [IMPLEMENTATION_AUDIT_AND_GAP_ANALYSIS.md](IMPLEMENTATION_AUDIT_AND_GAP_ANALYSIS.md) tells you exactly what exists
5. **Codebase:** 97% complete, just needs these features

---

## Success Looks Like This

**End of Week 1:**
- ✅ Aircon template system implemented
- ✅ Photos persist on server restart
- ✅ Field worker can render and submit forms
- ✅ Admin can view tickets with audit trail
- ✅ Demo works end-to-end
- 🎉 **Aircon client impressed, ready to pilot**

**End of Week 2:**
- ✅ Multi-tenant RBAC implemented
- ✅ Audit logs for all changes
- ✅ Security hardened
- ✅ Ready for multiple companies
- 🎉 **Production-ready platform**

---

## Questions to Ask Yourself

**Before you start, clarify:**

1. **When do you need to demo?** (Impacts scope)
2. **How many companies will use this initially?** (Impacts RBAC priority)
3. **Do you have a Cloudinary account?** (If not, set up now)
4. **Can you allocate 1 full person for 3 days?** (Recommended for Phase 1)
5. **What if you get stuck?** (Use `@fieldcheck-dev` agent)

---

## TL;DR - START HERE

**Choose your path:**

🟢 **Quick Win (3 days):** Use [AIRCON_TEMPLATE_IMPLEMENTATION_GUIDE.md](AIRCON_TEMPLATE_IMPLEMENTATION_GUIDE.md)
- Implement Aircon template
- Demo to client
- Extensible foundation

🔵 **Complete Platform (8 days):** Use [PRODUCT_STRATEGY_BLUEPRINT.md](PRODUCT_STRATEGY_BLUEPRINT.md)
- All features
- Multi-tenant ready
- Production hardened

🟡 **Hybrid (3+5 days):** Do both in phases
- Quick win first
- Expand second
- **RECOMMENDED**

---

## You're Ready!

You have:
- ✅ Complete product strategy
- ✅ Audit of current state
- ✅ Step-by-step implementation guides
- ✅ Ready-to-copy code examples
- ✅ Custom AI agent (`@fieldcheck-dev`)
- ✅ Clear roadmap

**Pick your path and start building.**

The next step is yours. Choose Option A, B, or C above and let's go! 🚀

---

**Questions?** Use `@fieldcheck-dev` - It's trained on your entire codebase and these blueprints.

**Ready to start Day 1?** Ask: `@fieldcheck-dev Help me implement durable attachments with Cloudinary`
