---
name: FieldCheck Product Strategy & Implementation Blueprint
date-created: April 26, 2026
status: ACTIVE DEVELOPMENT PLAN
version: 1.0
---

# FieldCheck - Product Strategy and Implementation Plan

## Executive Summary

Fortify the existing FieldCheck codebase rather than pivoting. Fix attachments persistence, unread counters, and socket hygiene first. Add per-company ticket templates (JSON Schema + workflow + SLA), basic RBAC, and company scoping so each client (e.g., the aircon cleaning service) can define the exact report fields they need. Deliver a short, scripted demo with seeded fallback data.

**Goal:** Turn FieldCheck into a reliable, demo-ready field workforce product for the air-con cleaning client by fixing critical reliability issues and adding per-company configurable ticket templates, durable attachments, RBAC, geofence enforcement, and a small set of enterprise features.

---

## 1. What Changes and Why (Priority Order)

### 1.1 Durable Attachments (CRITICAL)
**What:** Move uploads off ephemeral server disk to Cloudinary or S3; store provider URL and checksum in DB.

**Why:** Prevents lost photos after server restart; fixes a showstopper bug.

**Implementation:**
- Add Cloudinary/S3 integration to backend
- Create signed URL endpoint for direct browser uploads
- Store attachment metadata in MongoDB (url, provider, checksum, uploaded_by, created_at)
- Add retrieval endpoint with authorization checks

---

### 1.2 Socket Hygiene and Unread Counter Centralization
**What:** Centralize socket lifecycle and emit authoritative unread counts from server only.

**Why:** Prevents duplicate notifications and wrong counters; improves reliability.

**Implementation:**
- Create singleton socket manager
- Subscribe once per session
- Server emits unread count in every relevant event
- Client displays server-sent count (no local calculation)

---

### 1.3 Per-Company Ticket Templates
**What:** JSON Schema templates scoped to company_id with workflow and SLA.

**Why:** Lets each client require the fields they need without code changes; enables extensibility.

**Implementation:**
- New collection: ticket_templates
- Store JSON Schema for validation
- Support workflow states and SLA timers
- Add template creation/editing endpoints (admin only)

---

### 1.4 RBAC and Company Scoping
**What:** JWT includes company_id and role; middleware enforces access.

**Why:** Prevents cross-company leaks and accidental admin access; ensures data isolation.

**Implementation:**
- Extend JWT payload with company_id and role
- Create middleware to validate company_id matches user
- Create RBAC middleware (Admin, Manager, FieldWorker)
- Scope all queries by company_id

---

### 1.5 Geofence Enforcement
**What:** Server verifies GPS on check-in and rejects out-of-bounds attempts.

**Why:** Enforces real-world rules and demonstrates trustworthiness.

**Implementation:**
- Verify geofence exists and belongs to company
- Calculate distance from GPS to geofence center
- Reject if distance > radius with clear error
- Log attempt in audit trail

---

### 1.6 Audit Logs and SLA Timers
**What:** Immutable change history and simple overdue escalation.

**Why:** Accountability and managerial features for clients.

**Implementation:**
- New collection: audit_logs (resource_type, resource_id, action, actor_id, details)
- Calculate SLA based on template.sla_seconds
- Emit SLA warnings via socket
- Display in admin dashboard

---

### 1.7 Optional Offline Queue
**What:** Local queue for ticket creation and uploads; retry on reconnect.

**Why:** Field workers often lose signal; improves real usability.

**Implementation:**
- Use Hive/SQLite for local storage
- Queue ticket creation and attachment uploads
- Retry on reconnect with exponential backoff
- Show sync status in UI

---

## 2. Minimal Viable Ticketing Feature Set

1. ✅ **Company ticket templates** - custom fields and required attachments
2. ✅ **Configurable workflows** - statuses and transitions per company
3. ✅ **RBAC** - Admin, Manager, FieldWorker with enforced permissions
4. ✅ **Durable attachments** - Cloudinary/S3 signed uploads and DB refs
5. ✅ **SLA timers and escalation** - visible due dates and alerts
6. ✅ **Audit trail** - who changed what and when

---

## 3. Data Model and API

### 3.1 Database Collections / Tables

```
collections:
  - companies
    fields: id, name, settings, created_at, updated_at
    
  - ticket_templates
    fields: id, company_id, name, json_schema, workflow, sla_seconds, visibility, version, created_by, created_at, updated_at
    indexes: [company_id, created_at]
    
  - tickets
    fields: id (UUID), ticket_no, company_id, template_id, template_version, data (JSON), status, assignee_id, attachments[], gps, created_at, updated_at, created_by
    indexes: [company_id, ticket_no, created_at, status]
    
  - attachments
    fields: id, ticket_id, company_id, url, provider (cloudinary|s3), checksum, uploaded_by, created_at
    indexes: [ticket_id, company_id]
    
  - audit_logs
    fields: id, resource_type, resource_id, action, actor_id, changes, created_at
    indexes: [resource_id, created_at]
    
  - counters (for ticket numbering)
    fields: company_id, ticket_seq
```

---

### 3.2 Key API Endpoints

#### Template Management
```
POST   /api/companies/:companyId/templates
       - Admin only
       - Create template with JSON Schema
       - Response: { id, company_id, name, json_schema, workflow, sla_seconds }

GET    /api/companies/:companyId/templates
       - List templates (filter by visibility)
       - Query: ?visibility=public|private
       - Response: [{ id, name, version, visibility, created_by }]

GET    /api/companies/:companyId/templates/:templateId
       - Retrieve full template with schema
       - Response: { id, json_schema, workflow, sla_seconds }

PATCH  /api/companies/:companyId/templates/:templateId
       - Admin only
       - Update template (increments version)
       - Response: { id, version }
```

#### Ticket Operations
```
POST   /api/tickets
       - Create ticket
       - Body: { template_id, data: {...}, gps: {lat, lng} }
       - Server validates data against template.json_schema
       - Server validates GPS is within geofence
       - Response: { id, ticket_no, status, created_at }

GET    /api/tickets
       - List tickets for user's company
       - Query: ?status=open|in_progress|completed&limit=20&offset=0
       - Response: [{ id, ticket_no, status, assignee, created_at }]

GET    /api/tickets/:ticketId
       - Get full ticket with attachments
       - Response: { id, ticket_no, data, attachments[], audit_trail[], status, sla_due_at }

PATCH  /api/tickets/:ticketId/status
       - Change status
       - Body: { status, comment }
       - Enforce workflow and RBAC
       - Log audit entry
       - Response: { status, updated_at }

GET    /api/tickets/:ticketId/audit
       - Return audit trail for ticket
       - Response: [{ action, actor_id, changes, created_at }]
```

#### Attachments
```
POST   /api/uploads/signed-url
       - Return signed upload URL for Cloudinary/S3
       - Body: { file_type, file_size }
       - Scope to user's company_id
       - Response: { signed_url, upload_id }

POST   /api/tickets/:ticketId/attachments
       - Add attachment reference after upload
       - Body: { url, checksum, provider }
       - Response: { id, url, created_at }

GET    /api/attachments/:attachmentId/download
       - Download attachment (with auth check)
       - Response: Redirect to provider URL or attachment content
```

---

### 3.3 Server Validation Flow (Pseudocode)

```javascript
// POST /api/tickets - Create Ticket
async function createTicket(req, res) {
  const tokenCompany = req.user.company_id;
  const tokenRole = req.user.role;
  
  // 1. Validate user is FieldWorker or Admin
  if (!['FieldWorker', 'Admin'].includes(tokenRole)) {
    return res.status(403).json({ error: 'Insufficient permissions' });
  }
  
  // 2. Get template and verify company access
  const template = await db.ticket_templates.findById(req.body.template_id);
  if (!template) return res.status(404).json({ error: 'Template not found' });
  
  if (template.company_id !== tokenCompany && template.visibility !== 'public') {
    return res.status(403).json({ error: 'Cannot access this template' });
  }
  
  // 3. Validate data against schema
  const ajv = new Ajv();
  const valid = ajv.validate(template.json_schema, req.body.data);
  if (!valid) {
    return res.status(400).json({ 
      error: 'Validation failed',
      details: ajv.errors 
    });
  }
  
  // 4. Validate GPS is within geofence (if template requires it)
  if (template.json_schema.required.includes('gps')) {
    const gps = req.body.gps;
    const geofence = await db.geofences.findOne({
      company_id: tokenCompany,
      _id: req.body.geofence_id
    });
    
    if (!geofence) {
      return res.status(400).json({ error: 'Geofence not found' });
    }
    
    const distance = calculateDistance(gps, geofence.center);
    if (distance > geofence.radius_meters) {
      return res.status(400).json({ 
        error: 'GPS location outside geofence',
        distance,
        allowed_radius: geofence.radius_meters
      });
    }
  }
  
  // 5. Generate ticket number
  const seq = await db.counters.findOneAndUpdate(
    { company_id: tokenCompany },
    { $inc: { ticket_seq: 1 } },
    { upsert: true, returnDocument: 'after' }
  );
  const ticket_no = `AC-${String(seq.ticket_seq).padStart(4, '0')}`;
  
  // 6. Create ticket
  const ticket = await db.tickets.insertOne({
    id: uuid(),
    ticket_no,
    company_id: tokenCompany,
    template_id: template.id,
    template_version: template.version,
    data: req.body.data,
    gps: req.body.gps,
    status: 'open',
    created_by: req.user.id,
    created_at: new Date()
  });
  
  // 7. Create audit log
  await db.audit_logs.insertOne({
    resource_type: 'ticket',
    resource_id: ticket.id,
    action: 'created',
    actor_id: req.user.id,
    details: { ticket_no },
    created_at: new Date()
  });
  
  // 8. Emit socket event
  io.to(`company:${tokenCompany}`).emit('ticket:created', { 
    ticket_no, 
    status: 'open' 
  });
  
  return res.status(201).json({ 
    id: ticket.id, 
    ticket_no, 
    status: 'open' 
  });
}
```

---

## 4. Ticket Template for Aircon Cleaning Service

### 4.1 Core Template (Extensible Base)

```json
{
  "$id": "aircon-cleaning-v1",
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "title": "Aircon Cleaning Service Ticket",
  "required": [
    "customer_name",
    "service_type",
    "photos",
    "checklist",
    "gps"
  ],
  "properties": {
    "customer_name": {
      "type": "string",
      "title": "Customer Name",
      "minLength": 1
    },
    "service_type": {
      "type": "string",
      "title": "Service Type",
      "enum": [
        "inspection",
        "deep_clean",
        "repair",
        "maintenance",
        "emergency"
      ],
      "default": "inspection"
    },
    "unit_serial": {
      "type": "string",
      "title": "Unit Serial Number",
      "minLength": 3
    },
    "location_address": {
      "type": "string",
      "title": "Service Location",
      "minLength": 5
    },
    "checklist": {
      "type": "object",
      "title": "Service Checklist",
      "properties": {
        "filter_cleaned": {
          "type": "boolean",
          "title": "Filter Cleaned"
        },
        "coil_cleaned": {
          "type": "boolean",
          "title": "Coil Cleaned"
        },
        "drain_cleared": {
          "type": "boolean",
          "title": "Drain Cleared"
        },
        "refrigerant_checked": {
          "type": "boolean",
          "title": "Refrigerant Level Checked"
        },
        "electrical_tested": {
          "type": "boolean",
          "title": "Electrical Connections Tested"
        }
      },
      "required": [
        "filter_cleaned",
        "coil_cleaned",
        "drain_cleared"
      ]
    },
    "photos": {
      "type": "array",
      "title": "Service Photos (Before/After)",
      "items": {
        "type": "string",
        "format": "uri"
      },
      "minItems": 1,
      "maxItems": 10
    },
    "gps": {
      "type": "object",
      "title": "GPS Location",
      "required": [
        "lat",
        "lng"
      ],
      "properties": {
        "lat": {
          "type": "number",
          "minimum": -90,
          "maximum": 90
        },
        "lng": {
          "type": "number",
          "minimum": -180,
          "maximum": 180
        },
        "accuracy": {
          "type": "number",
          "title": "GPS Accuracy (meters)"
        }
      }
    },
    "notes": {
      "type": "string",
      "title": "Additional Notes",
      "maxLength": 500
    },
    "parts_replaced": {
      "type": "array",
      "title": "Parts Replaced",
      "items": {
        "type": "object",
        "properties": {
          "part_name": {
            "type": "string"
          },
          "quantity": {
            "type": "integer",
            "minimum": 1
          }
        }
      }
    },
    "customer_signature": {
      "type": "string",
      "title": "Customer Signature",
      "format": "uri"
    }
  },
  "additionalProperties": false
}
```

### 4.2 Template Metadata (Store in DB)

```javascript
{
  id: "tpl_aircon_cleaning_v1",
  company_id: "comp_123",
  name: "Aircon Cleaning Service",
  description: "Standard aircon unit cleaning and maintenance service",
  json_schema: { /* above schema */ },
  workflow: {
    states: ["open", "in_progress", "completed", "cancelled", "pending_review"],
    transitions: {
      "open": ["in_progress", "cancelled"],
      "in_progress": ["completed", "pending_review", "open"],
      "pending_review": ["completed", "open"],
      "completed": [],
      "cancelled": []
    },
    permissions: {
      "open": ["FieldWorker", "Admin"],
      "in_progress": ["FieldWorker"],
      "pending_review": ["Manager", "Admin"],
      "completed": ["Admin"],
      "cancelled": ["Admin"]
    }
  },
  sla_seconds: 86400, // 24 hours to complete
  required_attachments: ["photos"],
  visibility: "private",
  version: 1,
  created_by: "user_admin_001",
  created_at: "2026-04-26T10:00:00Z",
  updated_at: "2026-04-26T10:00:00Z",
  
  // Extensibility: Template inheritance and variants
  tags: ["aircon", "service", "cleaning"],
  variants: [
    {
      name: "Residential",
      description: "For residential customers",
      json_schema_overrides: {
        "properties.service_type.enum": ["inspection", "deep_clean", "maintenance"]
      }
    },
    {
      name: "Commercial",
      description: "For commercial customers - includes escalation procedures",
      json_schema_overrides: {
        "required": ["customer_name", "service_type", "photos", "checklist", "gps", "work_order_number"],
        "properties.work_order_number": {
          "type": "string",
          "title": "Work Order Number"
        }
      }
    }
  ]
}
```

### 4.3 Extensibility for Other Services

Add a template metadata table to allow flexible configuration:

```javascript
// Template Extension Framework
{
  id: "tpl_service_base",
  company_id: "comp_123",
  service_type: "generic_field_service", // enumeration for future services
  
  // Base fields all templates inherit
  base_fields: {
    customer_name: { type: "string", required: true },
    service_location: { type: "string", required: true },
    gps: { type: "object", required: true },
    photos: { type: "array", required: true },
    notes: { type: "string", required: false }
  },
  
  // Service-specific fields
  service_specific_fields: {
    // Aircon: unit_serial, checklist, refrigerant, etc.
    // Pest Control: infestation_type, treatment_used, follow_up_date, etc.
    // Landscaping: before/after photos, materials_used, etc.
  },
  
  // Workflow configuration
  workflow_config: {
    initial_state: "open",
    final_states: ["completed", "cancelled"],
    transitions: { /* state machine */ }
  },
  
  // SLA configuration
  sla_config: {
    default_duration_seconds: 86400,
    escalation_rules: [
      { threshold_percent: 50, notify: "manager" },
      { threshold_percent: 80, notify: "admin", escalate: true }
    ]
  }
}
```

---

## 5. Flutter Changes (High Level)

### 5.1 Architecture Changes

```
field_check/lib/
├── admin/
│   ├── screens/
│   │   ├── TemplateEditorScreen.dart         # Create/edit templates
│   │   ├── TemplateListScreen.dart
│   │   └── TicketReviewScreen.dart
│   └── widgets/
│       ├── JsonSchemaEditor.dart             # Visual schema builder
│       └── WorkflowEditor.dart
│
├── field/
│   ├── screens/
│   │   ├── TicketListScreen.dart
│   │   ├── DynamicFormScreen.dart            # Render template form
│   │   └── TicketDetailScreen.dart
│   └── widgets/
│       └── DynamicFormRenderer.dart          # Form builder from schema
│
├── services/
│   ├── socket_manager.dart                   # Centralized socket lifecycle
│   ├── offline_queue.dart                    # Local DB queue
│   ├── template_service.dart                 # Template API calls
│   ├── ticket_service.dart                   # Ticket API calls
│   └── storage_service.dart                  # Durable attachment uploads
│
└── models/
    ├── template.dart
    ├── ticket.dart
    └── attachment.dart
```

### 5.2 Dynamic Form Renderer

```dart
// Example: Render JSON Schema to Flutter widgets
class DynamicFormRenderer extends StatefulWidget {
  final Map<String, dynamic> jsonSchema;
  final Map<String, dynamic>? initialData;
  
  @override
  State<DynamicFormRenderer> createState() => _DynamicFormRendererState();
}

// Maps JSON Schema types to Flutter widgets:
// "string" → TextField
// "boolean" → CheckboxListTile
// "enum" → Dropdown or RadioGroup
// "array" with "format": "uri" → AttachmentPicker
// "object" → GroupedFields / Card
// "integer" or "number" → NumberField with validation
```

### 5.3 Upload Flow (Durable Attachments)

```dart
// 1. Request signed URL from backend
final signedUrl = await uploadService.getSignedUrl(
  fileName: 'ticket_photo_001.jpg',
  fileSize: file.lengthSync(),
);

// 2. Upload directly to Cloudinary/S3
await uploadService.uploadToProvider(
  file: file,
  signedUrl: signedUrl,
);

// 3. Include returned URL in ticket creation
await ticketService.createTicket(
  templateId: template.id,
  data: formData,
  attachments: [
    { url: 'https://res.cloudinary.com/...', checksum: 'abc123' }
  ],
);
```

### 5.4 Socket Manager (Singleton)

```dart
class SocketManager {
  static final SocketManager _instance = SocketManager._internal();
  
  late IO.Socket _socket;
  int _unreadCount = 0;
  
  factory SocketManager() {
    return _instance;
  }
  
  SocketManager._internal();
  
  void init(String baseUrl, String token) {
    // Subscribe once per session
    _socket = IO.io(baseUrl, <String, dynamic>{
      'auth': { 'token': token },
      'reconnection': true,
      'reconnectionDelay': 1000,
      'reconnectionDelayMax': 5000,
    });
    
    // Listen only for server-sent unread count
    _socket.on('unread:update', (data) {
      setState(() => _unreadCount = data['count']);
    });
  }
}
```

### 5.5 Offline Queue (Optional)

```dart
class OfflineQueueService {
  final hiveBox = Hive.box('offline_queue');
  
  // Queue ticket creation
  Future<void> queueTicket(Map<String, dynamic> ticket) async {
    await hiveBox.add({
      'type': 'ticket_create',
      'payload': ticket,
      'timestamp': DateTime.now(),
      'status': 'pending'
    });
  }
  
  // Retry on reconnect
  Future<void> syncQueue() async {
    final queue = hiveBox.values.toList();
    for (final item in queue) {
      if (item['status'] == 'pending') {
        try {
          await _sync(item);
          item['status'] = 'synced';
          await item.save();
        } catch (e) {
          // Retry with exponential backoff
          print('Sync failed: $e');
        }
      }
    }
  }
}
```

---

## 6. Ready-to-Use JSON Schema Templates

All templates are extensible and can be adapted for other companies.

### Aircon Cleaning (Primary)
[See section 4.1 above]

### Future Template: Pest Control Service

```json
{
  "$id": "pest-control-v1",
  "type": "object",
  "required": [
    "property_owner",
    "infestation_type",
    "treatment_used",
    "photos"
  ],
  "properties": {
    "property_owner": {
      "type": "string",
      "title": "Property Owner Name"
    },
    "infestation_type": {
      "type": "string",
      "enum": ["rodent", "insect", "termite", "other"]
    },
    "treatment_used": {
      "type": "string",
      "title": "Treatment/Pesticide Used"
    },
    "photos": {
      "type": "array",
      "minItems": 1,
      "items": { "type": "string", "format": "uri" }
    },
    "follow_up_date": {
      "type": "string",
      "format": "date"
    }
  }
}
```

### Future Template: Landscaping Service

```json
{
  "$id": "landscaping-v1",
  "type": "object",
  "required": ["client_name", "service_type"],
  "properties": {
    "client_name": { "type": "string" },
    "service_type": {
      "enum": ["maintenance", "renovation", "installation"]
    },
    "before_photos": {
      "type": "array",
      "items": { "type": "string", "format": "uri" }
    },
    "after_photos": {
      "type": "array",
      "items": { "type": "string", "format": "uri" }
    },
    "materials_used": {
      "type": "array",
      "items": { "type": "string" }
    }
  },
  "if": {
    "properties": { "service_type": { "const": "renovation" } }
  },
  "then": {
    "required": ["before_photos", "after_photos"]
  }
}
```

### Future Template: Proof of Delivery

```json
{
  "$id": "proof-of-delivery-v1",
  "type": "object",
  "required": ["recipient_name", "package_id", "photo_proof", "gps"],
  "properties": {
    "recipient_name": { "type": "string" },
    "package_id": { "type": "string" },
    "photo_proof": {
      "type": "array",
      "minItems": 1,
      "items": { "type": "string", "format": "uri" }
    },
    "signature": {
      "type": "string",
      "format": "uri"
    },
    "gps": {
      "type": "object",
      "properties": {
        "lat": { "type": "number" },
        "lng": { "type": "number" }
      }
    }
  }
}
```

---

## 7. Ticket Numbering and Identity

### 7.1 Dual Identity System

**Primary Key:** UUID for internal uniqueness and distributed generation.

**Human Readable:** Generated ticket_no like `AC-0001` or `AC-2026-0001` scoped per company and service type.

### 7.2 Generator Implementation

```javascript
// Atomic increment per company (MongoDB example)
async function generateTicketNumber(companyId, companyCode = 'AC') {
  const seq = await db.counters.findOneAndUpdate(
    { company_id: companyId },
    { $inc: { ticket_seq: 1 } },
    { upsert: true, returnDocument: 'after' }
  );
  
  return `${companyCode}-${String(seq.ticket_seq).padStart(4, '0')}`;
  // Returns: AC-0001, AC-0002, AC-0003, etc.
}
```

### 7.3 Ticket Record Structure

```javascript
{
  _id: ObjectId(),                    // MongoDB primary key
  id: "550e8400-e29b-41d4-a716-...", // UUID for external references
  ticket_no: "AC-0001",               // Human readable
  company_id: "comp_123",
  template_id: "tpl_aircon_v1",
  template_version: 1,
  data: {
    customer_name: "John Doe",
    service_type: "deep_clean",
    // ... form data
  },
  gps: { lat: 1.3521, lng: 103.8198 },
  status: "open",
  assignee_id: "user_fw_001",
  attachments: [
    {
      id: "att_001",
      url: "https://res.cloudinary.com/.../photo.jpg",
      provider: "cloudinary",
      checksum: "sha256abc123",
      uploaded_by: "user_fw_001",
      created_at: "2026-04-26T11:30:00Z"
    }
  ],
  sla_due_at: "2026-04-27T11:30:00Z",
  created_by: "user_fw_001",
  created_at: "2026-04-26T10:30:00Z",
  updated_at: "2026-04-26T10:30:00Z"
}
```

---

## 8. Demo Script and Fallback (5 minutes)

### 8.1 Demo Flow

**Setup:** Pre-seeded company "AirconCo" with admin user and one field worker assigned.

**Script Steps:**

1. **Template Creation** (Admin)
   - Admin logs in
   - Navigate to "Templates" → "Create New"
   - Show aircon cleaning template with required fields
   - Highlight JSON Schema editor
   - Workflow states: open → in_progress → completed

2. **Ticket Assignment** (Admin)
   - Admin creates ticket for today's service
   - Assigns to field worker "Ahmed"
   - Shows ticket number `AC-0001` and SLA due time

3. **Geofence Validation Failure** (Field Worker)
   - Field worker logs in
   - Attempts to check-in from outside geofence (mock location)
   - Server rejects with: "GPS location outside service area (100m away)"
   - Shows audit log entry: "Check-in rejected - out of bounds"

4. **Successful Check-in and Service** (Field Worker)
   - Field worker moves to geofence center
   - Checks in successfully
   - Opens ticket form (dynamically rendered from template)
   - Fills checklist items
   - Uploads photo (Cloudinary URL visible)
   - Marks complete

5. **Admin Review** (Admin)
   - Admin views ticket
   - Shows durable attachment URL
   - Displays audit trail: created → checked in → photo added → completed
   - Changes status to "QA Review"
   - Shows SLA status: "Completed on time (2 hours remaining)"

### 8.2 Fallback Data (If Live Upload Fails)

Pre-seed the database with:

```javascript
// Database seeding for fallback
{
  companies: [
    {
      id: "comp_demo_001",
      name: "AirconCo Demo",
      settings: { timezone: "Asia/Singapore" }
    }
  ],
  
  ticket_templates: [
    {
      id: "tpl_ac_demo_v1",
      company_id: "comp_demo_001",
      name: "Aircon Cleaning Service",
      json_schema: { /* full schema */ },
      workflow: { /* states and transitions */ },
      sla_seconds: 86400
    }
  ],
  
  tickets: [
    {
      id: "tkt_demo_001",
      ticket_no: "AC-0001",
      company_id: "comp_demo_001",
      template_id: "tpl_ac_demo_v1",
      status: "completed",
      data: {
        customer_name: "Demo Customer",
        service_type: "deep_clean",
        checklist: { filter_cleaned: true, coil_cleaned: true, drain_cleared: true },
        notes: "Service completed successfully"
      },
      attachments: [
        {
          url: "https://res.cloudinary.com/demo/image/upload/v1661234567/ticket_abc.jpg",
          provider: "cloudinary",
          checksum: "sha256abc123"
        }
      ]
    }
  ],
  
  audit_logs: [
    { resource_type: "ticket", action: "created", actor: "admin", created_at: "..." },
    { resource_type: "ticket", action: "check_in", actor: "fieldworker", created_at: "..." },
    { resource_type: "attachment", action: "uploaded", actor: "fieldworker", created_at: "..." },
    { resource_type: "ticket", action: "status_changed", actor: "fieldworker", created_at: "..." }
  ]
}
```

---

## 9. Sprint Plan (One Developer, AI-Assisted)

### Day 1: Durable Attachments (6-8 hours)
- [ ] Set up Cloudinary/S3 account and SDK
- [ ] Implement signed URL endpoint
- [ ] Create attachment model in DB
- [ ] Add attachment retrieval with auth checks
- [ ] Test server restart persistence

### Day 2: Template Model & Validation (6-8 hours)
- [ ] Create ticket_templates collection
- [ ] Implement AJV JSON Schema validation
- [ ] POST /api/templates endpoint (admin)
- [ ] POST /api/tickets with validation
- [ ] Unit tests for schema validation

### Day 3: Flutter Dynamic Form & Admin UI (6-8 hours)
- [ ] Build DynamicFormRenderer widget
- [ ] Create AttachmentPicker widget
- [ ] Build TemplateEditorScreen (admin)
- [ ] Connect upload flow (signed URL → Cloudinary)
- [ ] Integration tests

### Day 4: RBAC, Geofence, Socket Fixes (6-8 hours)
- [ ] Extend JWT with company_id and role
- [ ] Implement company-scoping middleware
- [ ] Add geofence distance validation
- [ ] Refactor socket manager (singleton pattern)
- [ ] Unit tests for RBAC and geofence

### Day 5: Audit Logs, Polish, Demo (6-8 hours)
- [ ] Implement audit log collection and endpoints
- [ ] Add optional offline queue (Hive/SQLite)
- [ ] Seed demo data (AirconCo company)
- [ ] Write docs/demo.md
- [ ] QA and final testing

**Total:** ~32-40 hours for one developer.

**If two developers:** Parallelize days 1+2 and days 3+4 to cut time roughly in half (~16-20 hours).

---

## 10. Acceptance Criteria (What to Verify)

- [ ] ✅ Attachments persist after server restart and are retrievable by authorized users.
- [ ] ✅ Creating a ticket with invalid data returns 400 with AJV validation errors.
- [ ] ✅ Users cannot access templates, tickets, or attachments from other companies (403).
- [ ] ✅ Geofence check rejects out-of-bounds check-ins with clear error message.
- [ ] ✅ Geofence check success logs audit entry and allows check-in.
- [ ] ✅ Socket notifications include authoritative unread count; client displays that count.
- [ ] ✅ Admin can create a template in the UI.
- [ ] ✅ Field worker can render and submit a ticket from that template.
- [ ] ✅ Admin can view ticket audit trail with all actions.
- [ ] ✅ SLA timer visible on ticket; escalation warnings sent at thresholds.
- [ ] ✅ Demo script runs end-to-end (5 minutes).
- [ ] ✅ Fallback seeded data loads if live upload fails.

---

## 11. Files to Add or Modify

### Backend

```
backend/
├── models/
│   ├── TicketTemplate.js
│   ├── Ticket.js
│   ├── Attachment.js
│   └── AuditLog.js
│
├── routes/
│   ├── templates.js              (NEW)
│   ├── tickets.js                (NEW)
│   ├── uploads.js                (NEW)
│   └── auth.js                   (MODIFY - add company_id to JWT)
│
├── middleware/
│   ├── companyScoping.js         (NEW)
│   ├── rbac.js                   (NEW)
│   └── auth.js                   (MODIFY)
│
├── services/
│   ├── StorageService.js         (NEW - Cloudinary/S3)
│   ├── TicketValidationService.js (NEW - AJV + geofence)
│   ├── AuditLogService.js        (NEW)
│   └── SlaService.js             (NEW)
│
├── controllers/
│   ├── templateController.js     (NEW)
│   ├── ticketController.js       (NEW)
│   ├── uploadController.js       (NEW)
│   └── auditLogController.js     (NEW)
│
├── migrations/
│   └── add_tickets_schema.js     (NEW - DB migrations)
│
└── tests/
    ├── ticket.test.js
    ├── template.test.js
    └── rbac.test.js
```

### Frontend (Flutter)

```
field_check/lib/
├── admin/
│   ├── screens/
│   │   ├── TemplateEditorScreen.dart    (NEW)
│   │   ├── TemplateListScreen.dart      (NEW)
│   │   └── TicketReviewScreen.dart      (NEW)
│   └── widgets/
│       ├── JsonSchemaEditor.dart        (NEW)
│       └── WorkflowEditor.dart          (NEW)
│
├── field/
│   ├── screens/
│   │   ├── DynamicFormScreen.dart       (NEW)
│   │   └── TicketListScreen.dart        (NEW)
│   └── widgets/
│       ├── DynamicFormRenderer.dart     (NEW)
│       └── AttachmentPicker.dart        (NEW)
│
├── services/
│   ├── socket_manager.dart              (NEW/REFACTOR)
│   ├── offline_queue.dart               (NEW - optional)
│   ├── template_service.dart            (NEW)
│   ├── ticket_service.dart              (NEW)
│   └── storage_service.dart             (NEW)
│
└── tests/
    ├── dynamic_form_renderer_test.dart
    └── socket_manager_test.dart
```

### Documentation

```
docs/
├── demo.md                      (NEW)
├── templates.md                 (NEW)
├── api.md                       (UPDATE - new endpoints)
├── schema.md                    (NEW - template schema reference)
└── deployment.md                (NEW - Cloudinary setup, etc.)
```

---

## 12. Next Artifacts to Produce

Choose based on what you need first:

- [ ] OpenAPI/Swagger spec for all new endpoints
- [ ] Exact DB migration script (MongoDB or SQL)
- [ ] Middleware code snippet (JWT company scoping + RBAC)
- [ ] Flutter dynamic form renderer skeleton (production-ready Dart)
- [ ] Seed data JSON (AirconCo company with templates and sample tickets)
- [ ] Cloudinary/S3 integration guide with code examples
- [ ] Unit test file skeletons (Jest for backend, Flutter test for frontend)

---

## Additional Implementation Notes

### A. Geofence Validation
**Check:** Verify if geofence functionality already works correctly in the current codebase before adding new validation layer.

**Action:** Run acceptance tests on existing geofence check-in logic.

### B. Audit Existing Code
**Check:** Scan codebase for existing implementations of:
- Template/dynamic form rendering
- Attachment handling
- Socket lifecycle management
- RBAC patterns

**Goal:** Reuse existing patterns and avoid duplicate implementations.

### C. Template System Extensibility
**Design:** Make the ticket template system extensible so future service types (pest control, landscaping, etc.) can be added without code changes—just new JSON schemas and metadata.

**Base Template Structure:**
- Core required fields (customer, location, GPS, photos, notes)
- Service-specific overrides
- Workflow configuration
- SLA settings

**Implementation:** Use template inheritance/composition pattern.

---

## Status Tracking

| Component | Status | Verified | Notes |
|-----------|--------|----------|-------|
| Durable attachments | 🔴 TODO | ❌ | Critical blocker |
| Geofence validation | 🟡 CHECK | ❌ | May be partially done |
| Socket hygiene | 🔴 TODO | ❌ | Need singleton pattern |
| Ticket templates | 🔴 TODO | ❌ | Core feature |
| RBAC middleware | 🔴 TODO | ❌ | Security critical |
| Flutter form renderer | 🔴 TODO | ❌ | Enable template rendering |
| Audit logs | 🔴 TODO | ❌ | Accountability |
| Demo script | 🔴 TODO | ❌ | For panelists |

---

**Document Created:** April 26, 2026
**Blueprint Version:** 1.0
**Status:** READY FOR IMPLEMENTATION
