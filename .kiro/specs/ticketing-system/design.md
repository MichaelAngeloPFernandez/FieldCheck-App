# Design Document: Ticketing System

## Overview

The FieldCheck App already has a `Ticket` model, `TicketTemplate` model, `ticketService.js`, `validationService.js`, and route stubs in place. However, the admin-facing ticketing workflow is incomplete: there is no guided ticket creation UI, no enforced employee assignment validation, and the existing `ticketService.js` references stale field names that diverge from the live Mongoose models.

This design delivers a **complete, production-ready ticketing system** by:

1. Aligning the backend service layer with the actual Mongoose schemas (`Ticket`, `TicketTemplate`, `Counter`).
2. Hardening the existing route handlers (`ticketRoutes.js`, `templateRoutes.js`) with the missing business rules from the requirements.
3. Providing a Flutter frontend that renders a template-driven ticket creation form, an admin ticket list with filters, and an employee ticket view.
4. Wiring real-time Socket.IO events and audit logging throughout.

The existing `Task`/`UserTask` system is **not modified**. Tickets are a parallel, template-driven workflow.

---

## Architecture

The system follows the existing layered architecture of the FieldCheck backend:

```
Flutter Client
      │
      │  HTTPS + JWT Bearer
      ▼
Express Router  (routes/ticketRoutes.js, routes/templateRoutes.js)
      │
      │  business logic
      ▼
Service Layer   (ticketService.js, validationService.js, auditService.js, storageService.js)
      │
      │  Mongoose ODM
      ▼
MongoDB Atlas   (Ticket, TicketTemplate, Counter, AuditLog, User, Company, Geofence)
      │
      │  Socket.IO events
      ▼
Connected Clients (admin dashboard, employee app)
```

### Key Architectural Decisions

- **No new models**: All required data fits the existing `Ticket`, `TicketTemplate`, `Counter`, and `AuditLog` schemas. Minor field additions to `Ticket` (see Data Models) are backward-compatible.
- **Route-level controllers**: The existing pattern of inline route handlers (no separate controller files for tickets/templates) is preserved to match the codebase style.
- **AJV validation stays in routes**: `validationService.js` is used for the service layer; the routes also compile AJV validators directly (matching the existing pattern in `ticketRoutes.js`).
- **Counter is company-scoped**: `Counter.getNextSequence(companyId)` already provides atomic, per-company ticket numbering. The ticket number format is `<COMPANY_CODE>-<NNNN>` (e.g., `ACME-0001`).
- **SLA cron job already exists**: `jobs/sla_check_job.js` runs every 5 minutes and marks overdue tickets. It needs a small addition to handle the `on_time`/`overdue` finalization on close/verify.

---

## Components and Interfaces

### Backend Components

#### 1. `routes/ticketRoutes.js` (enhanced)

The existing file already implements the core routes. The following gaps must be filled:

| Gap | Required Change |
|-----|----------------|
| No employee-role validation on `assignee_id` | Add user lookup + role check before saving |
| `PATCH /:id` allows updates on `closed`/`verified` tickets | Add status guard |
| `PATCH /:id/status` does not finalize `sla_status` on close/verify | Add SLA finalization logic |
| `PATCH /:id` does not emit a Socket.IO event for assignee changes | Emit `ticketAssigneeChanged` |
| No endpoint for listing assignable employees | Add `GET /api/tickets/employees` |

**Route Table (complete):**

```
GET    /api/tickets                    List tickets (admin: company-scoped; employee: assigned only)
GET    /api/tickets/employees          List assignable employees for the admin's company
GET    /api/tickets/:id                Get single ticket (populated)
GET    /api/tickets/:id/audit          Get audit trail for a ticket
POST   /api/tickets                    Create ticket
PATCH  /api/tickets/:id                Update ticket data / notes / assignee
PATCH  /api/tickets/:id/status         Transition ticket status
POST   /api/tickets/:id/attachments    Upload attachment (multipart/form-data, field: "file")
GET    /api/tickets/attachments/:fileId  Download attachment
PATCH  /api/tickets/:id/archive        Archive ticket (admin only)
PATCH  /api/tickets/:id/restore        Restore ticket (admin only)
```

#### 2. `routes/templateRoutes.js` (already complete)

The existing implementation satisfies all requirements. No changes needed beyond confirming the `requireRole('admin')` guard is in place on mutating routes (it is).

#### 3. `services/ticketService.js` (refactored)

The existing `ticketService.js` references stale field names (`jsonSchema`, `slaSeconds`, `serviceType`, `statusHistory`, etc.) that do not match the live Mongoose models. It must be refactored to use the correct field names:

| Old (stale) | Correct (live model) |
|-------------|---------------------|
| `template.jsonSchema` | `template.json_schema` |
| `template.slaSeconds` | `template.sla_seconds` |
| `template.serviceType` | `template.name` (used for prefix derivation) |
| `ticket.statusHistory` | Not in model — remove |
| `ticket.slaDueAt` | `ticket.sla_deadline` |
| `ticket.sla_status` | `ticket.sla_status` (correct) |

The refactored service exposes:
- `TicketService.generateTicketNumber(companyId, companyCode)` — uses `Counter.getNextSequence`
- `TicketService.validateAndCreate(params)` — wraps route creation logic for reuse
- `TicketService.finalizeSlsStatus(ticket)` — called on close/verify transitions

#### 4. `jobs/sla_check_job.js` (enhanced)

Add SLA finalization: when a ticket transitions to `closed` or `verified`, compute `sla_status` based on `completedAt` vs `sla_deadline`. This logic is added to the status transition route handler and the SLA job.

#### 5. Flutter Frontend Components

```
lib/
  features/
    tickets/
      screens/
        ticket_list_screen.dart        Admin ticket list with filters
        ticket_detail_screen.dart      Full ticket detail view
        ticket_create_screen.dart      Template-driven creation form
        employee_ticket_list_screen.dart  Employee's assigned tickets
      widgets/
        template_dropdown.dart         Dropdown populated from GET /api/templates
        dynamic_form.dart              Renders fields from json_schema
        ticket_status_chip.dart        Colored status badge
        sla_indicator.dart             SLA deadline + status display
        attachment_picker.dart         File picker + upload
      models/
        ticket_model.dart              Dart model for Ticket
        ticket_template_model.dart     Dart model for TicketTemplate
      services/
        ticket_api_service.dart        HTTP calls to /api/tickets
        template_api_service.dart      HTTP calls to /api/templates
```

**Dynamic Form Rendering (`dynamic_form.dart`):**

The `json_schema` `properties` object is iterated to render form fields. Supported field types:

| JSON Schema type | Flutter widget |
|-----------------|----------------|
| `string` | `TextFormField` |
| `string` + `enum` | `DropdownButtonFormField` |
| `number` / `integer` | `TextFormField` (numeric keyboard) |
| `boolean` | `SwitchListTile` |
| `string` + `format: date` | `TextFormField` + date picker |

Required fields (from `json_schema.required` array) are marked with `*` and validated on submit.

---

## Data Models

### `Ticket` (existing, minor additions)

The existing schema is sufficient. The following fields are confirmed in use:

```javascript
{
  ticket_no:        String,   // "ACME-0001" — unique, required
  company:          ObjectId, // ref: Company — required, indexed
  template:         ObjectId, // ref: TicketTemplate — required
  template_version: Number,   // snapshot of template.version at creation
  data:             Mixed,    // validated form payload
  status:           String,   // default: 'open'
  assignee:         ObjectId, // ref: User — nullable
  created_by:       ObjectId, // ref: User — nullable
  attachments:      [String], // GridFS URL paths
  sla_deadline:     Date,     // createdAt + template.sla_seconds
  sla_status:       String,   // enum: ['on_time', 'at_risk', 'overdue', null]
  gps:              { lat, lng },
  geofence:         ObjectId, // ref: Geofence — nullable
  notes:            String,
  isArchived:       Boolean,
  completedAt:      Date,     // set on first terminal status transition
  createdAt:        Date,     // auto (timestamps: true)
  updatedAt:        Date,     // auto (timestamps: true)
}
```

**Indexes (existing + recommended):**
```javascript
{ company: 1, status: 1 }          // existing
{ assignee: 1, status: 1 }         // existing
{ company: 1, isArchived: 1, createdAt: -1 }  // add for list query performance
{ sla_deadline: 1, status: 1 }     // add for SLA job performance
```

### `TicketTemplate` (existing, no changes)

```javascript
{
  company:     ObjectId,  // ref: Company — required
  name:        String,    // required, trim
  description: String,
  json_schema: Mixed,     // JSON Schema draft-07
  workflow: {
    statuses:    [String],  // default: ['open','in_progress','completed','verified','closed']
    transitions: Mixed,     // map: fromStatus -> [toStatus]
  },
  sla_seconds: Number,    // null = no SLA
  visibility:  String,    // 'company' | 'public'
  version:     Number,    // monotonic, incremented on json_schema change
  isActive:    Boolean,
  created_by:  ObjectId,
}
```

### `Counter` (existing, no changes)

```javascript
{
  company: ObjectId,  // unique per company
  seq:     Number,    // atomically incremented
}
```

`Counter.getNextSequence(companyId)` is the canonical way to generate ticket numbers.

### `AuditLog` (existing, no changes)

Actions used by the ticketing system:

| `action` | `resource_type` | When |
|----------|----------------|------|
| `created` | `ticket` | Ticket created |
| `status_changed` | `ticket` | Status transition |
| `data_updated` | `ticket` | Data/notes/assignee updated |
| `attachment_added` | `ticket` | File uploaded |
| `assignee_updated` | `ticket` | Assignee changed via PATCH |
| `sla_breached` | `ticket` | SLA job marks overdue |
| `geofence_rejected` | `ticket` | Creation rejected by geofence |
| `created` | `template` | Template created |
| `updated` | `template` | Template updated |
| `deactivated` | `template` | Template soft-deleted |

---

## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a system — essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*

### Property 1: Template list scoping

*For any* company and any set of templates (with mixed `isActive`, `company`, and `visibility` values), `GET /api/templates` SHALL return only templates where `isActive: true` AND (`company` matches the requesting user's company OR `visibility: 'public'`). No inactive template and no template from a different company with `visibility: 'company'` shall appear in the result.

**Validates: Requirements 1.1, 1.4**

---

### Property 2: Ticket data validation round-trip

*For any* `TicketTemplate` with a valid `json_schema` and any `data` payload that satisfies that schema, `POST /api/tickets` SHALL return HTTP 201 and the created ticket's `data` field SHALL equal the submitted payload. Conversely, for any `data` payload that violates the schema, the endpoint SHALL return HTTP 400 with at least one field-level error entry.

**Validates: Requirements 2.2, 8.1, 8.2, 11.2**

---

### Property 3: Ticket creation invariants

*For any* valid ticket creation request, the created `Ticket` document SHALL satisfy all of the following simultaneously:
- `status` equals `'open'`
- `ticket_no` matches the pattern `^[A-Z0-9]+-\d{4}$`
- `ticket_no` is unique across all tickets in the company
- `sla_deadline` equals `createdAt + template.sla_seconds` (within 1 second tolerance) when `sla_seconds > 0`, or `null` when `sla_seconds` is `null` or `0`
- `sla_status` equals `'on_time'` when `sla_deadline` is set, or `null` when `sla_deadline` is `null`

**Validates: Requirements 2.3, 10.1, 10.2**

---

### Property 4: Assignee validation

*For any* ticket creation or update request that includes an `assignee_id`, the system SHALL reject the request with HTTP 400 if the referenced user does not exist or does not have `role: 'employee'`. Only when the referenced user exists and has `role: 'employee'` SHALL the `Ticket.assignee` field be set to that user's `_id`.

**Validates: Requirements 2.4, 2.5**

---

### Property 5: Audit log completeness

*For any* state-changing operation on a ticket (create, status change, data update, attachment upload, assignee change), an `AuditLog` entry SHALL be written with the correct `action`, `actor_id`, `resource_id`, and `company`. The audit log entry SHALL be written atomically with the operation — if the operation succeeds, the log entry must exist.

**Validates: Requirements 2.7, 3.4, 6.4, 8.4, 12.4**

---

### Property 6: Employee list filtering

*For any* admin's company, `GET /api/tickets/employees` SHALL return only users where `role: 'employee'` AND `isActive: true` AND `company` matches the admin's company. Each returned user SHALL include at minimum `_id`, `name`, `employeeId`, and `status` fields. No admin user, inactive user, or user from a different company shall appear.

**Validates: Requirements 3.1, 3.2, 3.3**

---

### Property 7: Ticket list scoping and filtering

*For any* admin, `GET /api/tickets` SHALL return only non-archived tickets belonging to the admin's company, sorted by `createdAt` descending. When a `status` query parameter is provided, all returned tickets SHALL have that status. When a `template` query parameter is provided, all returned tickets SHALL reference that template. When `archived=true` is provided, only archived tickets SHALL be returned.

**Validates: Requirements 4.1, 4.3, 4.4, 4.5, 4.6**

---

### Property 8: Cross-company access denial

*For any* user requesting a ticket that belongs to a different company, `GET /api/tickets/:id` SHALL return HTTP 403. Similarly, an employee requesting a ticket not assigned to them SHALL receive HTTP 403.

**Validates: Requirements 5.2, 7.4**

---

### Property 9: SLA overdue status

*For any* ticket where `sla_deadline` is in the past and `status` is not `'completed'`, `'verified'`, or `'closed'`, the ticket's `sla_status` SHALL be `'overdue'` — both in the API response and in the database after the SLA cron job runs.

**Validates: Requirements 5.3, 7.3, 10.3**

---

### Property 10: Workflow transition enforcement

*For any* ticket and any requested status transition, the system SHALL permit the transition if and only if the target status appears in `template.workflow.transitions[currentStatus]`. Any transition not in the allowed list SHALL return HTTP 400. A ticket with `status: 'closed'` SHALL reject all transition attempts regardless of the transitions map.

**Validates: Requirements 6.1, 6.5**

---

### Property 11: Terminal status completedAt

*For any* ticket transitioning to `'completed'`, `'verified'`, or `'closed'`, `Ticket.completedAt` SHALL be set to a non-null timestamp if it was previously `null`. Once set, `completedAt` SHALL NOT be overwritten by subsequent transitions.

**Validates: Requirements 6.2**

---

### Property 12: SLA finalization on close/verify

*For any* ticket transitioning to `'closed'` or `'verified'`, `sla_status` SHALL be set to `'on_time'` if `completedAt ≤ sla_deadline`, or SHALL remain `'overdue'` if `completedAt > sla_deadline`. If `sla_deadline` is `null`, `sla_status` SHALL remain `null`.

**Validates: Requirements 10.4**

---

### Property 13: Template version increment

*For any* template with version `N`, updating the `json_schema` field via `PUT /api/templates/:id` SHALL result in `version` becoming exactly `N + 1`. Updates to other fields (name, description, sla_seconds, etc.) without changing `json_schema` SHALL NOT increment the version.

**Validates: Requirements 9.3**

---

### Property 14: Template soft delete preserves data

*For any* template, `DELETE /api/templates/:id` SHALL set `isActive: false` and the template document SHALL still exist in the database. All tickets that reference the template SHALL remain intact and queryable.

**Validates: Requirements 9.4**

---

### Property 15: Template access control

*For any* non-admin user, `POST /api/templates`, `PUT /api/templates/:id`, and `DELETE /api/templates/:id` SHALL return HTTP 403.

**Validates: Requirements 9.6**

---

### Property 16: Attachment round-trip

*For any* file uploaded via `POST /api/tickets/:id/attachments` (up to 10 MB), the returned `fileId` SHALL be usable to retrieve the file via `GET /api/tickets/attachments/:fileId` with the correct `Content-Type` and `Content-Disposition` headers. The file's URL SHALL appear in `Ticket.attachments` after upload.

**Validates: Requirements 12.1, 12.2, 12.5**

---

### Property 17: Public template visibility

*For any* `TicketTemplate` with `visibility: 'public'`, users from any company SHALL be able to retrieve it via `GET /api/templates` and `GET /api/templates/:id`.

**Validates: Requirements 11.4**

---

## Error Handling

### HTTP Status Code Conventions

| Scenario | Status |
|----------|--------|
| Missing required field | 400 |
| AJV schema validation failure | 400 with `errors` array |
| Invalid workflow transition | 400 with allowed transitions listed |
| Data update on closed/verified ticket | 400 |
| Status transition on closed ticket | 400 |
| Unauthenticated request | 401 |
| Non-admin accessing admin-only endpoint | 403 |
| Cross-company ticket access | 403 |
| Employee accessing another employee's ticket | 403 |
| Geofence enforcement rejection | 403 with distance details |
| Resource not found | 404 |
| File upload exceeds 10 MB | 413 (multer default) |
| Internal server error | 500 |

### Validation Error Response Shape

All AJV validation failures return:
```json
{
  "message": "Ticket data validation failed",
  "errors": [
    { "path": "/fieldName", "message": "must be string", "params": {} }
  ]
}
```

### Audit Logging Failures

`auditService.log()` is fire-and-forget — it catches and logs errors internally but never throws. This ensures audit failures never break the primary request path.

### Socket.IO Emission Failures

All `global.io.emit()` calls are wrapped in `if (global.io)` guards. Emission failures are non-fatal.

### SLA Job Error Handling

The SLA cron job catches all errors and logs them without crashing the process. Individual ticket update failures are isolated — one failure does not prevent other tickets from being processed.

---

## Testing Strategy

### Unit Tests (Jest)

Unit tests cover specific examples, edge cases, and pure logic:

- `validationService.validate()` with valid and invalid data against sample schemas
- `Counter.getNextSequence()` atomicity (mock MongoDB)
- SLA deadline computation: `createdAt + sla_seconds`
- SLA finalization logic: `completedAt` vs `sla_deadline` comparison
- Workflow transition validation: allowed and disallowed transitions
- `storageService.uploadBuffer()` and `getFileStream()` with mock GridFS

### Property-Based Tests (fast-check)

Property-based testing is appropriate for this feature because:
- The validation service is a pure function over arbitrary JSON Schemas and data
- Ticket creation invariants must hold for any valid template/data combination
- Filtering and scoping rules must hold for any combination of companies, users, and tickets
- Workflow enforcement must hold for any transition map and any status pair

**Library**: [`fast-check`](https://github.com/dubzzz/fast-check) (already compatible with Jest)

**Configuration**: Minimum 100 iterations per property test.

**Tag format**: `// Feature: ticketing-system, Property N: <property_text>`

#### Property Test Implementations

**Property 1 — Template list scoping**
```javascript
// Feature: ticketing-system, Property 1: Template list scoping
fc.assert(fc.asyncProperty(
  fc.record({ companyId: fc.uuid(), templates: fc.array(templateArb) }),
  async ({ companyId, templates }) => {
    // seed DB, call GET /api/templates as admin of companyId
    // assert: all returned templates are active AND (same company OR public)
  }
), { numRuns: 100 });
```

**Property 2 — Ticket data validation round-trip**
```javascript
// Feature: ticketing-system, Property 2: Ticket data validation round-trip
fc.assert(fc.asyncProperty(
  fc.tuple(jsonSchemaArb, fc.record({})),
  async ([schema, data]) => {
    const result = validationService.validate(schema, data);
    const isValid = ajv.validate(schema, data);
    return result.valid === isValid;
  }
), { numRuns: 200 });
```

**Property 3 — Ticket creation invariants**
```javascript
// Feature: ticketing-system, Property 3: Ticket creation invariants
fc.assert(fc.asyncProperty(
  fc.record({ slaSeconds: fc.oneof(fc.constant(null), fc.nat()) }),
  async ({ slaSeconds }) => {
    // create ticket, assert status='open', ticket_no format, sla_deadline math
  }
), { numRuns: 100 });
```

**Property 10 — Workflow transition enforcement**
```javascript
// Feature: ticketing-system, Property 10: Workflow transition enforcement
fc.assert(fc.asyncProperty(
  fc.record({ from: statusArb, to: statusArb, transitions: transitionMapArb }),
  async ({ from, to, transitions }) => {
    const allowed = transitions[from] || [];
    const response = await patchStatus(ticketId, to);
    if (allowed.includes(to)) {
      return response.status === 200;
    } else {
      return response.status === 400;
    }
  }
), { numRuns: 100 });
```

### Integration Tests

Integration tests verify end-to-end behavior with a real (test) MongoDB instance:

- Full ticket lifecycle: create → in_progress → completed → verified → closed
- SLA cron job: seed overdue tickets, run job, verify `sla_status: 'overdue'`
- Socket.IO event emission: `ticketCreated`, `ticketStatusChanged`
- Attachment upload and download via GridFS
- Cross-company access denial (403)
- Template deactivation and exclusion from dropdown

### Flutter Widget Tests

- `TemplateDropdown` renders template names from mock API response
- `DynamicForm` renders correct field types for each JSON Schema property type
- `DynamicForm` marks required fields and validates on submit
- `TicketListScreen` shows empty state when no templates exist
- `SlaIndicator` shows correct color/label for `on_time`, `at_risk`, `overdue`, `null`
