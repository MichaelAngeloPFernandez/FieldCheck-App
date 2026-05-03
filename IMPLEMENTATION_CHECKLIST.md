---
name: FieldCheck Implementation Checklist
date: April 26, 2026
format: Quick reference checklist for tracking progress
---

# FieldCheck Implementation Checklist

## Pre-Implementation Setup

### Before You Start
- [ ] Review [MASTER_IMPLEMENTATION_PLAN.md](MASTER_IMPLEMENTATION_PLAN.md) (choose Option A, B, or C)
- [ ] Read relevant sections of chosen guide:
  - Option A: [AIRCON_TEMPLATE_IMPLEMENTATION_GUIDE.md](AIRCON_TEMPLATE_IMPLEMENTATION_GUIDE.md)
  - Option B: [PRODUCT_STRATEGY_BLUEPRINT.md](PRODUCT_STRATEGY_BLUEPRINT.md)
  - All: Review [IMPLEMENTATION_AUDIT_AND_GAP_ANALYSIS.md](IMPLEMENTATION_AUDIT_AND_GAP_ANALYSIS.md)
- [ ] Install required dependencies locally
- [ ] Set up development environment

### Cloud Storage Setup (Required)
- [ ] Create Cloudinary account (https://cloudinary.com)
- [ ] Get API key and upload URL
- [ ] Set environment variables:
  - [ ] `CLOUDINARY_CLOUD_NAME`
  - [ ] `CLOUDINARY_API_KEY`
  - [ ] `CLOUDINARY_UPLOAD_URL`
- [ ] Test upload endpoint (curl test)

### MongoDB Setup
- [ ] Verify MongoDB Atlas connection
- [ ] Create new collections (or run migrations):
  - [ ] `ticket_templates`
  - [ ] `tickets`
  - [ ] `attachments`
  - [ ] `counters` (for ticket numbering)
  - [ ] `audit_logs` (if doing full platform)

---

## Phase 1: Quick Win - Aircon Template System (Days 1-3)

### Day 1: Durable Attachments

#### Backend - Storage Service
- [ ] Create `backend/services/StorageService.js`
- [ ] Implement Cloudinary integration
- [ ] POST `/api/uploads/signed-url` endpoint
- [ ] POST `/api/attachments` endpoint
- [ ] GET `/api/attachments/:id/download` endpoint
- [ ] Add authorization checks
- [ ] Test locally

#### Backend - Attachment Model
- [ ] Create `backend/models/Attachment.js`
- [ ] Fields: id, ticket_id, company_id, url, provider, checksum, uploaded_by, created_at
- [ ] Indexes: ticket_id, company_id, checksum
- [ ] Test model creation

#### Testing - Day 1
- [ ] Upload photo via signed URL
- [ ] Retrieve photo by URL
- [ ] Server restart persistence test
- [ ] Unauthorized access rejected (403)
- [ ] File checksum validation

#### Acceptance
- [ ] Upload photo → restart server → retrieve photo ✅

---

### Day 2: Template Model & Validation

#### Backend - Template Model
- [ ] Create `backend/models/TicketTemplate.js`
- [ ] Fields: id, company_id, name, json_schema, workflow, sla_seconds, visibility, version, created_by
- [ ] Indexes: company_id, created_at, service_type
- [ ] Test model

#### Backend - Ticket Model Update
- [ ] Modify `backend/models/Ticket.js`
- [ ] Add template_id reference
- [ ] Add template_version snapshot
- [ ] Add data field (Object for form data)
- [ ] Add gps field
- [ ] Add status field
- [ ] Indexes: company_id, ticket_no, status

#### Backend - Validation Service
- [ ] `npm install ajv`
- [ ] Create validation using AJV
- [ ] Test JSON Schema validation

#### Backend - Template Routes
- [ ] Create `backend/routes/templates.js`
- [ ] POST /api/companies/:companyId/templates (admin only)
- [ ] GET /api/companies/:companyId/templates (list)
- [ ] GET /api/templates/:templateId (get full)
- [ ] Test with curl

#### Backend - Ticket Routes
- [ ] Create `backend/routes/tickets.js`
- [ ] POST /api/tickets (create with validation)
- [ ] GET /api/tickets (list)
- [ ] GET /api/tickets/:id (retrieve)
- [ ] Test with curl

#### Backend - Ticket Numbering
- [ ] Create Counter model for atomic increment
- [ ] Implement ticket_no generator (AC-0001, AC-0002, etc.)
- [ ] Test uniqueness

#### Backend - Seed Data
- [ ] Create `backend/seeds/aircon_template.js`
- [ ] Aircon Cleaning template with full JSON Schema
- [ ] Test seeding: `node backend/seeds/aircon_template.js`

#### Testing - Day 2
- [ ] Create template with valid JSON Schema
- [ ] Create template with invalid schema → rejection
- [ ] Create ticket with valid form data
- [ ] Create ticket with invalid data → validation errors returned
- [ ] Ticket numbering: AC-0001, AC-0002, etc.

#### Acceptance
- [ ] Valid ticket data accepted and saved ✅
- [ ] Invalid data rejected with error details ✅
- [ ] Template versioning works ✅

---

### Day 3: Flutter Dynamic Forms

#### Flutter - Models
- [ ] Create/update ticket models
- [ ] Create template model

#### Flutter - Dynamic Form Renderer
- [ ] Create `field_check/lib/widgets/DynamicFormRenderer.dart`
- [ ] Handle types: string, boolean, enum, array (photos), object (nested)
- [ ] Client-side validation (required fields, minLength, etc.)
- [ ] Form submission

#### Flutter - Attachment Picker
- [ ] Create `field_check/lib/widgets/AttachmentPickerWidget.dart`
- [ ] Camera/photo library picker
- [ ] Request signed URL from backend
- [ ] Upload to Cloudinary directly
- [ ] Show upload progress
- [ ] Handle errors
- [ ] Display uploaded photos

#### Flutter - Ticket Creation Screen
- [ ] Create `field_check/lib/screens/TicketCreationScreen.dart` (or update existing)
- [ ] Fetch template
- [ ] Show template description
- [ ] Render DynamicFormRenderer
- [ ] Show attachment picker
- [ ] GPS location capture
- [ ] Submit button

#### Flutter - Ticket List Screen
- [ ] Update to show new tickets
- [ ] Display ticket_no, status, created_at
- [ ] Tap to view details

#### Flutter - Integration
- [ ] Update API service with new endpoints
- [ ] Add template service
- [ ] Add ticket service

#### Testing - Day 3
- [ ] Load Aircon template → form renders correctly
- [ ] Fill form → validation works
- [ ] Upload photo → Cloudinary URL returned
- [ ] Submit form → API called with correct data
- [ ] Form validation errors shown to user
- [ ] Success: ticket created with ticket_no AC-0001

#### Acceptance
- [ ] Template renders dynamically ✅
- [ ] Photo upload works end-to-end ✅
- [ ] Ticket creation with validation ✅
- [ ] Admin can view created ticket ✅

---

## Phase 2: Production Ready (Days 4-5)

### Day 4: RBAC, Multi-Tenant, Security

#### Backend - User Schema Update
- [ ] Add `company_id` field to User model
- [ ] Add `role` enum: admin, manager, employee (currently only admin, employee)
- [ ] Migration script: `backend/migrations/add_company_id_to_users.js`

#### Backend - Company Model
- [ ] Create `backend/models/Company.js`
- [ ] Fields: id, name, settings, created_at
- [ ] Test creation

#### Backend - Middleware
- [ ] Create `backend/middleware/companyScoping.js`
- [ ] Middleware: Check req.user.company_id matches resource
- [ ] Apply to all routes

#### Backend - RBAC Middleware
- [ ] Create `backend/middleware/rbac.js`
- [ ] Implement permission checks (admin, manager, employee)
- [ ] Apply to all admin-only routes

#### Backend - Security Fixes
- [ ] Fix CORS in `backend/server.js`
  - [ ] Change `origin: "*"` to specific domain
  - [ ] Add credentials: true
- [ ] Enable rate limiting
- [ ] Add security headers

#### Backend - Geofence Fixes
- [ ] Fix checkout bypass: require geofence on both checkin and checkout
- [ ] Add GPS accuracy validation (reject < 50m accuracy)
- [ ] Deduplicate Haversine formula to `backend/utils/geoUtils.js`
- [ ] Add 5m tolerance on boundary

#### Backend - Routes Update
- [ ] Add company scoping middleware to all routes
- [ ] Test: User A can't access User B's data (403)
- [ ] Test: Manager can review tickets (if role added)

#### Testing - Day 4
- [ ] User from Company A can't see Company B's tickets (403)
- [ ] Admin sees only their company's data
- [ ] Geofence checkout now requires location
- [ ] GPS accuracy < 50m: rejection
- [ ] CORS no longer allows *

#### Acceptance
- [ ] Multi-tenant isolation working ✅
- [ ] RBAC enforced at API level ✅
- [ ] Geofence fully validated ✅

---

### Day 5: Audit Logs, Polish, Deployment

#### Backend - Audit Logs
- [ ] Create `backend/models/AuditLog.js`
- [ ] Fields: id, resource_type, resource_id, action, actor_id, changes, created_at
- [ ] Create `backend/services/AuditLogService.js`
- [ ] Middleware to auto-log all changes
- [ ] GET `/api/audit-logs/:resourceId` endpoint

#### Backend - SLA & Escalation
- [ ] Calculate SLA due date on ticket creation
- [ ] Implement SLA escalation alerts
- [ ] Send notifications at 50%, 80%, 100% thresholds

#### Backend - Socket Security
- [ ] Add per-event authorization checks
- [ ] Add event deduplication
- [ ] Add rate limiting on events

#### Documentation
- [ ] Update README with new features
- [ ] Write deployment guide
- [ ] Write API documentation (OpenAPI/Swagger)

#### Deployment Prep
- [ ] Create production environment file (.env.production)
- [ ] Test on staging environment
- [ ] Backup existing database
- [ ] Write rollback plan

#### Demo Script Verification
- [ ] Admin creates Aircon template (can configure JSON Schema)
- [ ] Admin creates ticket with geofence
- [ ] Field worker attempts check-in outside geofence → rejected
- [ ] Field worker moves inside geofence → accepted
- [ ] Field worker renders form from template
- [ ] Field worker uploads photo (show URL)
- [ ] Field worker submits ticket
- [ ] Admin views ticket with audit trail
- [ ] Admin changes status to "pending_review"
- [ ] Full script takes 5 minutes ✅

#### Final Testing
- [ ] Unit tests pass
- [ ] Integration tests pass
- [ ] Manual E2E testing complete
- [ ] Load testing (concurrent submissions)
- [ ] Security audit complete
- [ ] Performance acceptable
- [ ] No lint errors

#### Acceptance
- [ ] All acceptance criteria from sections above ✅
- [ ] Demo script works end-to-end ✅
- [ ] Production deployment ready ✅

---

## Bugs to Fix (From Audit)

### Critical
- [ ] Attachments ephemeral (Day 1 - fixes this)
- [ ] Checkout bypasses geofence (Day 4)
- [ ] Multi-tenant scoping missing (Day 4)

### High Priority
- [ ] GPS accuracy not validated (Day 4)
- [ ] CORS wide open (Day 4)
- [ ] Haversine duplicated 4 times (Day 4)

### Medium Priority
- [ ] Offline sync limited to attendance (optional)
- [ ] Socket notifications could duplicate (Day 5)
- [ ] No audit logs (Day 5)

### Low Priority
- [ ] Incomplete RBAC (only 2 roles)
- [ ] No field-level permissions

---

## Code Quality Checks

Before deploying, verify:

### Backend
- [ ] `npm run lint` - 0 errors
- [ ] `npm test` - All tests pass
- [ ] No empty catch blocks
- [ ] All endpoints have validation
- [ ] All endpoints have error handling
- [ ] No hardcoded secrets

### Flutter
- [ ] `flutter analyze` - 0 errors
- [ ] `flutter test` - All tests pass
- [ ] No deprecated APIs
- [ ] Proper null safety
- [ ] Handle all error cases

### Database
- [ ] All migrations run successfully
- [ ] Indexes created for performance
- [ ] Backup verified

---

## Deployment Checklist

Before going live:

### Setup
- [ ] Cloudinary account configured
- [ ] MongoDB Atlas verified
- [ ] Environment variables set
- [ ] SSL certificates ready

### Testing
- [ ] All unit tests pass
- [ ] Integration tests pass
- [ ] Manual testing complete
- [ ] Load testing successful
- [ ] Security audit passed

### Data
- [ ] Database backed up
- [ ] Migrations tested on backup
- [ ] Seeded data verified
- [ ] Audit logs initialized

### Communication
- [ ] Client notified of launch
- [ ] Demo script prepared
- [ ] Support team trained
- [ ] Rollback plan documented

### Monitoring
- [ ] Error logging enabled
- [ ] Performance metrics tracked
- [ ] Alert thresholds set
- [ ] On-call rotation scheduled

---

## Success Milestones

### End of Day 1
- [ ] Attachments persist after server restart ✅
- [ ] Durable storage working

### End of Day 2
- [ ] Template system working
- [ ] Validation working
- [ ] Ticket creation with validation ✅

### End of Day 3
- [ ] **DEMO READY** ✅
- [ ] Field worker can complete full workflow
- [ ] Aircon client can be shown working system

### End of Day 4
- [ ] Multi-tenant isolation working
- [ ] RBAC enforced
- [ ] Security hardened

### End of Day 5
- [ ] **PRODUCTION READY** ✅
- [ ] Audit trail complete
- [ ] Ready to deploy
- [ ] Multiple companies can use

---

## Troubleshooting Quick Reference

| Problem | Solution | See |
|---------|----------|-----|
| Cloudinary upload fails | Check API key and environment | AIRCON_TEMPLATE_IMPLEMENTATION_GUIDE.md |
| Validation not working | Verify AJV installed and schema valid | PRODUCT_STRATEGY_BLUEPRINT.md - Section 3.3 |
| MongoDB connection error | Check connection string and Atlas IP whitelist | backend/server.js |
| Flutter widget errors | Run `flutter clean && flutter pub get` | AIRCON_TEMPLATE_IMPLEMENTATION_GUIDE.md |
| Socket not connecting | Check CORS and token validation | IMPLEMENTATION_AUDIT_AND_GAP_ANALYSIS.md |

---

## Help & Support

**When stuck:**
1. Check relevant guide's troubleshooting section
2. Review file location and line numbers from audit
3. Ask `@fieldcheck-dev` for implementation help
4. Check test cases for expected behavior

**Quick Commands:**
```bash
# Test specific feature
npm test backend/tests/template.test.js

# Run linter
npm run lint

# Check logs
tail -f backend/logs/app.log

# Verify MongoDB
mongo connection-string show collections
```

---

## Tracking Your Progress

Save this checklist and check off items as you complete them.

**Target Timeline:**
- ✅ Day 1: Attachments
- ✅ Day 2: Templates  
- ✅ Day 3: Flutter (DEMO READY)
- ✅ Day 4: RBAC & Security
- ✅ Day 5: Audit & Deploy (PRODUCTION READY)

---

**YOU'VE GOT THIS! 🚀**

Pick your starting point, check off items as you go, and use `@fieldcheck-dev` when you need help.

Good luck!
