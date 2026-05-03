# Day 2: Template System - Complete

## ✅ What Was Implemented

### Models Created
1. **TicketTemplate.js** - Service template schemas with JSON Schema validation
2. **Ticket.js** - Individual service requests with state machine
3. **Counter.js** - Atomic ticket number generation

### Services Created
1. **ValidationService.js** - JSON Schema validation using AJV
2. **TicketService.js** - Business logic for ticket lifecycle

### Routes Created
- **ticketRoutes.js** - REST endpoints for templates and tickets

### Database
- ✅ Aircon Cleaning template seeded (ID: 69ee24041e2b350202ee2d61)
- ✅ JSON Schema with all fields for service
- ✅ Workflow state machine configured
- ✅ 24-hour SLA set

---

## 🧪 Testing the System

### Test 1: Get Aircon Template

```bash
# Get template list
curl -X GET http://localhost:5000/api/templates \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -H "Content-Type: application/json"

# Response:
# {
#   "count": 1,
#   "templates": [{
#     "_id": "69ee24041e2b350202ee2d61",
#     "name": "Aircon Cleaning Service",
#     "serviceType": "aircon_cleaning",
#     "version": 1,
#     "slaSeconds": 86400
#   }]
# }

# Get full template schema
curl -X GET http://localhost:5000/api/templates/69ee24041e2b350202ee2d61 \
  -H "Authorization: Bearer YOUR_JWT_TOKEN"
```

### Test 2: Create Ticket with VALID Data

```bash
# This should PASS validation
curl -X POST http://localhost:5000/api/tickets \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "templateId": "69ee24041e2b350202ee2d61",
    "requesterName": "John Doe",
    "requesterEmail": "john@example.com",
    "requesterPhone": "6581234567",
    "data": {
      "customerName": "Jane Smith",
      "customerEmail": "jane@example.com",
      "customerPhone": "6589876543",
      "serviceAddress": "123 Main Street, Singapore 123456",
      "buildingType": "residential",
      "unitCount": 2,
      "unitBrand": "daikin",
      "serviceChecklist": [
        {
          "task": "filter_replacement",
          "completed": true,
          "notes": "Filter replaced successfully"
        },
        {
          "task": "condenser_cleaning",
          "completed": true,
          "notes": "Deep cleaned"
        }
      ],
      "issuesFound": "none",
      "laborHours": 2.5,
      "laborCost": 150,
      "photosRequired": true,
      "followUpRequired": false,
      "techniciansNotes": "Service completed without issues"
    }
  }'

# Response:
# {
#   "_id": "...",
#   "ticketNumber": "AC-0001",
#   "status": "draft",
#   "slaDueAt": "2026-04-27T...",
#   "message": "Ticket created successfully"
# }
```

### Test 3: Create Ticket with INVALID Data (Missing Required Field)

```bash
# This should FAIL validation - missing customerName
curl -X POST http://localhost:5000/api/tickets \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "templateId": "69ee24041e2b350202ee2d61",
    "requesterName": "John Doe",
    "requesterEmail": "john@example.com",
    "requesterPhone": "6581234567",
    "data": {
      "customerEmail": "jane@example.com",
      "customerPhone": "6589876543",
      "serviceAddress": "123 Main Street, Singapore 123456",
      "buildingType": "residential",
      "unitCount": 2,
      "unitBrand": "daikin",
      "serviceChecklist": []
    }
  }'

# Response (400 error):
# {
#   "error": "Validation failed",
#   "details": [
#     {
#       "field": "$root",
#       "message": "Missing required field: customerName",
#       "keyword": "required"
#     }
#   ]
# }
```

### Test 4: List Tickets

```bash
curl -X GET "http://localhost:5000/api/tickets?status=draft" \
  -H "Authorization: Bearer YOUR_JWT_TOKEN"
```

### Test 5: Get Ticket Details

```bash
# Replace with actual ticket ID from Test 2
curl -X GET http://localhost:5000/api/tickets/AC-0001 \
  -H "Authorization: Bearer YOUR_JWT_TOKEN"
```

### Test 6: Update Ticket Status

```bash
curl -X PATCH http://localhost:5000/api/tickets/AC-0001/status \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "status": "assigned",
    "reason": "Assigned to technician John"
  }'
```

---

## 📋 Aircon Template Schema Details

### Required Fields
1. **customerName** - String (2-100 chars)
2. **customerEmail** - Email format
3. **customerPhone** - Phone (10+ digits)
4. **serviceAddress** - String (5-500 chars)
5. **buildingType** - Enum: residential | commercial | industrial
6. **unitCount** - Integer (1-50)
7. **unitBrand** - Enum: daikin | fujitsu | lg | panasonic | midea | gree | other
8. **serviceChecklist** - Array of tasks (at least one required)
9. **issuesFound** - Enum: none | minor | major

### Optional Fields
- issueDescription
- partsReplaced (array with partName, quantity, cost)
- laborHours (0-24)
- laborCost (SGD)
- photosRequired (boolean)
- followUpRequired (boolean)
- followUpDate (date format)
- techniciansNotes (max 2000 chars)

### Checklist Tasks
- filter_replacement
- condenser_cleaning
- evaporator_cleaning
- drain_cleaning
- refrigerant_check
- electrical_inspection
- performance_test

---

## 🔄 Workflow States

```
draft → assigned → in_progress → completed → closed
                ↘              ↘
                  cancelled       cancelled
```

### State Descriptions
1. **draft** - Initial creation, not yet assigned
2. **assigned** - Assigned to technician, pending work
3. **in_progress** - Technician actively working
4. **completed** - Work finished, awaiting approval
5. **closed** - Final state, no more transitions
6. **cancelled** - Service cancelled

---

## 💾 Database Schema References

### TicketTemplate Collection
```javascript
{
  _id: ObjectId,
  name: "Aircon Cleaning Service",
  serviceType: "aircon_cleaning",
  jsonSchema: { /* JSON Schema v7 */ },
  workflow: [ /* state transitions */ ],
  slaSeconds: 86400,
  version: 1,
  createdBy: ObjectId,
  isActive: true,
  createdAt: ISODate,
  updatedAt: ISODate
}
```

### Ticket Collection
```javascript
{
  _id: ObjectId,
  ticketNumber: "AC-0001",
  templateId: ObjectId,
  templateVersion: 1,
  data: { /* form submission data */ },
  requestedBy: ObjectId,
  assignedTo: ObjectId,
  status: "draft",
  slaDueAt: ISODate,
  isEscalated: false,
  statusHistory: [ /* audit trail */ ],
  attachmentIds: [ ObjectId, ... ],
  createdAt: ISODate,
  updatedAt: ISODate
}
```

### Counter Collection
```javascript
{
  _id: "ac",           // Counter ID
  seq: 1,              // Current sequence
  prefix: "AC",        // Display prefix
  digits: 4            // Padding (AC-0001)
}
```

---

## 🔧 Integration Points

### Connect Attachments to Tickets
When uploading photos with a ticket:
```bash
# 1. Create ticket (returns _id)
curl -X POST http://localhost:5000/api/tickets ...

# 2. Upload attachments
curl -X POST http://localhost:5000/api/attachments/upload \
  -F "resourceType=ticket" \
  -F "resourceId=TICKET_ID_FROM_STEP_1" \
  -F "file=@photo.jpg"

# 3. Add attachment IDs to ticket data or update separately
```

### Create Another Template
```bash
curl -X POST http://localhost:5000/api/templates \
  -H "Authorization: Bearer ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Plumbing Repair",
    "serviceType": "plumbing",
    "jsonSchema": { /* your schema */ },
    "workflow": [ /* states */ ],
    "slaSeconds": 43200
  }'
```

---

## 📊 Statistics

- **Models**: 3 (TicketTemplate, Ticket, Counter)
- **Services**: 2 (ValidationService, TicketService)
- **Routes**: 7 endpoints
- **Dependencies**: ajv, ajv-formats
- **Template Fields**: 14 core + 4 optional
- **Workflow States**: 6 states
- **SLA**: 24 hours escalation

---

## ✅ Day 2 Checklist

- [x] TicketTemplate model created
- [x] Ticket model created
- [x] Counter model created
- [x] ValidationService implemented
- [x] TicketService implemented
- [x] Ticket routes created
- [x] AJV dependencies installed
- [x] Aircon template seeded (ID: 69ee24041e2b350202ee2d61)
- [x] Validation testing verified
- [x] Routes registered in server.js

---

## 🚀 Next: Day 3

Tomorrow: **Flutter Dynamic Forms**
- Create DynamicFormRenderer widget
- Render JSON Schema as Flutter UI
- Implement form validation
- Connect to ticket API
- **Deliverable:** Full Aircon workflow end-to-end

---

## 📚 Quick Reference

**Create template:** POST /api/templates (admin)
**List templates:** GET /api/templates
**Get template:** GET /api/templates/:id
**Create ticket:** POST /api/tickets
**List tickets:** GET /api/tickets
**Get ticket:** GET /api/tickets/:id
**Update status:** PATCH /api/tickets/:id/status

Template ID (Aircon): **69ee24041e2b350202ee2d61**
