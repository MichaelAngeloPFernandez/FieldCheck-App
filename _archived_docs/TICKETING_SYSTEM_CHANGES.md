# Ticketing System — Implementation Changelog

This document tracks every change required to deliver the complete ticketing system for the FieldCheck App. It is organized by file, with a clear **current state → required change** breakdown for each.

---

## Summary

The FieldCheck App already has a solid foundation: `Ticket` and `TicketTemplate` models, `ticketRoutes.js`, `templateRoutes.js`, `ticketService.js`, `validationService.js`, `sla_check_job.js`, and seed data for three service types. However, several gaps remain before the system is production-ready.

| Area | Status |
|------|--------|
| `Ticket` model | ✅ Complete — no changes needed |
| `TicketTemplate` model | ✅ Complete — no changes needed |
| `Counter` model | ✅ Complete — no changes needed |
| `AuditLog` model | ✅ Complete — no changes needed |
| `templateRoutes.js` | ✅ Complete — no changes needed |
| `validationService.js` | ✅ Complete — no changes needed |
| `ticketRoutes.js` | ⚠️ Gaps — 4 missing behaviours |
| `ticketService.js` | ❌ Stale — field names diverge from live models |
| `sla_check_job.js` | ⚠️ Partial — missing SLA finalization on close/verify |
| Flutter frontend | ❌ Not yet built |
| Backend indexes | ⚠️ 2 recommended indexes missing |
| Tests | ❌ Not yet written |

---

## Backend Changes

### 1. `backend/routes/ticketRoutes.js`

**Current state:** Core routes exist (`GET /`, `GET /:id`, `POST /`, `PATCH /:id`, `PATCH /:id/status`, `POST /:id/attachments`, `GET /attachments/:fileId`, `PATCH /:id/archive`, `PATCH /:id/restore`). Several business rules are missing.

#### 1.1 Add `GET /api/tickets/employees` endpoint

**Gap:** No endpoint exists to list assignable employees for the admin's company.  
**Required:** New route that returns all users with `role: 'employee'` and `isActive: true` scoped to the admin's company, including `_id`, `name`, `employeeId`, and `status` fields.

```
GET /api/tickets/employees
Auth: admin only
Response: [{ _id, name, employeeId, status }]
```

#### 1.2 Add employee-role validation on `assignee_id` at creation

**Gap:** `POST /api/tickets` accepts any `assignee_id` without verifying the user exists or has `role: 'employee'`.  
**Required:** Before saving, look up the user by `assignee_id`. Return HTTP 400 if the user is not found or does not have `role: 'employee'`.

#### 1.3 Add status guard on `PATCH /api/tickets/:id`

**Gap:** `PATCH /:id` allows data/notes/assignee updates on tickets with `status: 'closed'` or `status: 'verified'`.  
**Required:** Return HTTP 400 if the ticket's current status is `'closed'` or `'verified'` before applying any updates.

#### 1.4 Add SLA finalization on `PATCH /api/tickets/:id/status`

**Gap:** When a ticket transitions to `'closed'` or `'verified'`, `sla_status` is not finalized.  
**Required:** After setting `completedAt`, compute final `sla_status`:
- If `sla_deadline` is null → leave `sla_status` as null
- If `completedAt <= sla_deadline` → set `sla_status = 'on_time'`
- If `completedAt > sla_deadline` → set `sla_status = 'overdue'`

#### 1.5 Add `closed` status guard on `PATCH /api/tickets/:id/status`

**Gap:** A ticket with `status: 'closed'` can still receive status transition requests (the workflow transitions map has `closed: []`, which returns an unhelpful "Allowed: " message).  
**Required:** Explicitly check `if (ticket.status === 'closed')` before the workflow validation and return HTTP 400 with a clear message.

#### 1.6 Emit `ticketAssigneeChanged` Socket.IO event

**Gap:** `PATCH /:id` does not emit a real-time event when `assignee_id` changes.  
**Required:** When `assignee_id` is present in the request body and differs from the current value, emit `ticketAssigneeChanged` with `{ ticketId, ticket_no, assignee }`.

---

### 2. `backend/services/ticketService.js`

**Current state:** The service was written against an older schema and uses field names that no longer match the live Mongoose models. It is currently unused by the routes (routes implement logic inline), but it needs to be corrected so it can be used for reusable business logic.

#### Field name corrections required

| Stale field name | Correct field name (live model) |
|------------------|---------------------------------|
| `template.jsonSchema` | `template.json_schema` |
| `template.slaSeconds` | `template.sla_seconds` |
| `template.serviceType` | `template.name` |
| `ticket.statusHistory` | *(remove — not in model)* |
| `ticket.slaDueAt` | `ticket.sla_deadline` |
| `ticket.ticketNumber` | `ticket.ticket_no` |
| `ticket.templateId` | `ticket.template` |
| `ticket.requestedBy` | `ticket.created_by` |
| `Counter.findByIdAndUpdate(counterId, ...)` | `Counter.getNextSequence(companyId)` |
| `status: 'draft'` (initial) | `status: 'open'` |

#### Methods to refactor

- **`generateTicketNumber(templateId)`** → change to `generateTicketNumber(companyId, companyCode)` using `Counter.getNextSequence(companyId)` and format `${companyCode}-${seq.toString().padStart(4, '0')}`.
- **`createTicket(params)`** → align all field names, remove `statusHistory`, use `sla_deadline` instead of `slaDueAt`, set initial `status: 'open'`.
- **`updateStatus(ticketId, newStatus, changedBy, reason)`** → fix `template.workflow.transitions[currentStatus]` lookup (currently uses `template.workflow.find(w => w.state === ...)` which is wrong — `workflow.transitions` is a plain object map, not an array).
- **`escalateOverdueTickets()`** → rename to `finalizeSlsStatus(ticket)` — a helper called on close/verify transitions to compute final `sla_status`.

---

### 3. `backend/jobs/sla_check_job.js`

**Current state:** Runs every 5 minutes. Correctly marks tickets as `at_risk` (30 min before deadline) and `overdue` (past deadline). Does **not** finalize `sla_status` when a ticket closes.

#### 3.1 Add SLA finalization helper

**Gap:** When a ticket transitions to `'closed'` or `'verified'`, `sla_status` should be set to `'on_time'` or remain `'overdue'` based on `completedAt` vs `sla_deadline`. This logic currently does not exist anywhere.  
**Required:** Export a `finalizeSlaStatus(ticket)` function from this module (or from `ticketService.js`) that is called by the status transition route handler.

```javascript
// Logic to add:
function finalizeSlaStatus(ticket) {
  if (!ticket.sla_deadline) return; // no SLA — leave null
  if (ticket.completedAt <= ticket.sla_deadline) {
    ticket.sla_status = 'on_time';
  }
  // else: leave as 'overdue' (already set by cron job or stays from creation)
}
```

---

### 4. `backend/models/Ticket.js` — Recommended Index Additions

**Current state:** Two indexes exist: `{ company: 1, status: 1 }` and `{ assignee: 1, status: 1 }`.

**Recommended additions** (performance, not correctness):

```javascript
ticketSchema.index({ company: 1, isArchived: 1, createdAt: -1 }); // list query
ticketSchema.index({ sla_deadline: 1, status: 1 });                // SLA job query
```

---

## Flutter Frontend — New Files

All files are new. None exist yet.

### Directory structure

```
lib/features/tickets/
  screens/
    ticket_list_screen.dart           Admin ticket list with status/template filters
    ticket_detail_screen.dart         Full ticket detail view (populated fields)
    ticket_create_screen.dart         Template-driven creation form
    employee_ticket_list_screen.dart  Employee's assigned tickets only
  widgets/
    template_dropdown.dart            Dropdown from GET /api/templates
    dynamic_form.dart                 Renders fields from json_schema properties
    ticket_status_chip.dart           Colored status badge
    sla_indicator.dart                SLA deadline + on_time/at_risk/overdue display
    attachment_picker.dart            File picker + upload to POST /:id/attachments
  models/
    ticket_model.dart                 Dart model for Ticket
    ticket_template_model.dart        Dart model for TicketTemplate
  services/
    ticket_api_service.dart           HTTP calls to /api/tickets
    template_api_service.dart         HTTP calls to /api/templates
```

### Screen descriptions

#### `ticket_list_screen.dart`
- Calls `GET /api/tickets` on load
- Filter bar: status dropdown, template dropdown, archived toggle
- Each row shows: `ticket_no`, template name, status chip, assignee name, SLA indicator
- Taps navigate to `ticket_detail_screen.dart`
- FAB opens `ticket_create_screen.dart`

#### `ticket_create_screen.dart`
- Step 1: `TemplateDropdown` — calls `GET /api/templates`, shows active templates
- Step 2: `DynamicForm` — renders fields from selected template's `json_schema`
- Step 3: Employee assignment — calls `GET /api/tickets/employees`, optional dropdown
- Submit calls `POST /api/tickets`
- Shows empty state message if no templates are available

#### `ticket_detail_screen.dart`
- Calls `GET /api/tickets/:id`
- Shows all populated fields: template name, status, assignee, SLA, form data, attachments
- Status transition button (allowed transitions from `template.workflow.transitions`)
- Attachment list with download links

#### `employee_ticket_list_screen.dart`
- Same as `ticket_list_screen.dart` but filtered to assigned tickets only
- No FAB (employees cannot create tickets)
- Shows SLA overdue warning prominently

### Widget descriptions

#### `dynamic_form.dart`
Iterates `json_schema.properties` and renders the appropriate Flutter widget per field type:

| JSON Schema type | Widget |
|-----------------|--------|
| `string` | `TextFormField` |
| `string` + `enum` | `DropdownButtonFormField` |
| `number` / `integer` | `TextFormField` (numeric keyboard) |
| `boolean` | `SwitchListTile` |
| `string` + `format: date` | `TextFormField` + date picker |

Fields listed in `json_schema.required` are marked with `*` and validated on submit.

#### `sla_indicator.dart`
Displays a colored label based on `sla_status`:

| `sla_status` | Color | Label |
|-------------|-------|-------|
| `on_time` | Green | On Time |
| `at_risk` | Amber | At Risk |
| `overdue` | Red | Overdue |
| `null` | Grey | No SLA |

---

## Tests — New Files

### Backend unit tests (`backend/__tests__/unit/`)

| File | What it tests |
|------|--------------|
| `validationService.test.js` | `validate()` with valid/invalid data against sample schemas |
| `ticketService.test.js` | `generateTicketNumber()`, `finalizeSlaStatus()`, SLA deadline math |
| `workflowTransitions.test.js` | Allowed and disallowed transitions for various status pairs |

### Backend property-based tests (`backend/__tests__/property/`)

Uses [`fast-check`](https://github.com/dubzzz/fast-check), minimum 100 iterations per property.

| File | Property tested |
|------|----------------|
| `templateScoping.property.test.js` | Property 1: Only active, company-scoped or public templates returned |
| `ticketValidation.property.test.js` | Property 2: Validation round-trip — valid data → 201, invalid → 400 |
| `ticketCreationInvariants.property.test.js` | Property 3: `status='open'`, `ticket_no` format, SLA math |
| `assigneeValidation.property.test.js` | Property 4: Non-employee `assignee_id` → 400 |
| `employeeListFiltering.property.test.js` | Property 6: Only active employees from same company returned |
| `ticketListScoping.property.test.js` | Property 7: Archived/status/template filters all correct |
| `workflowEnforcement.property.test.js` | Property 10: Transition allowed ↔ in transitions map |

### Backend integration tests (`backend/__tests__/integration/`)

| File | What it tests |
|------|--------------|
| `ticketLifecycle.test.js` | Full lifecycle: create → in_progress → completed → verified → closed |
| `slaJob.test.js` | Seed overdue tickets, run job, verify `sla_status: 'overdue'` |
| `socketEvents.test.js` | `ticketCreated`, `ticketStatusChanged` events emitted correctly |
| `attachments.test.js` | Upload and download via GridFS |
| `crossCompanyAccess.test.js` | 403 on cross-company ticket access |
| `templateDeactivation.test.js` | Deactivated template excluded from dropdown |

### Flutter widget tests (`test/features/tickets/`)

| File | What it tests |
|------|--------------|
| `template_dropdown_test.dart` | Renders template names from mock API |
| `dynamic_form_test.dart` | Correct widget per JSON Schema field type; required field validation |
| `ticket_list_screen_test.dart` | Empty state when no templates exist |
| `sla_indicator_test.dart` | Correct color/label for each `sla_status` value |

---

## Files Not Changed

The following files are confirmed complete and require no modifications:

- `backend/models/Ticket.js`
- `backend/models/TicketTemplate.js`
- `backend/models/Counter.js`
- `backend/models/AuditLog.js`
- `backend/routes/templateRoutes.js`
- `backend/services/validationService.js`
- `backend/services/auditService.js`
- `backend/services/storageService.js`
- `backend/seeds/seedAirconTemplate.js`
- `backend/seeds/seedElectricalTemplate.js`
- `backend/seeds/seedPlumbingTemplate.js`
- `backend/middleware/authMiddleware.js`
- `backend/server.js`
- All existing `Task`/`UserTask` files

---

## Change Count Summary

| Category | Files Changed | Files Added |
|----------|--------------|-------------|
| Backend routes | 1 | 0 |
| Backend services | 1 | 0 |
| Backend jobs | 1 | 0 |
| Backend models (indexes only) | 1 | 0 |
| Flutter screens | 0 | 4 |
| Flutter widgets | 0 | 5 |
| Flutter models | 0 | 2 |
| Flutter services | 0 | 2 |
| Backend unit tests | 0 | 3 |
| Backend property tests | 0 | 7 |
| Backend integration tests | 0 | 6 |
| Flutter widget tests | 0 | 4 |
| **Total** | **4** | **33** |
