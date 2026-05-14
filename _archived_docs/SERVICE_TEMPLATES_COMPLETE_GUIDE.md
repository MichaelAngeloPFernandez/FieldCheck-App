# Service Templates - Complete Reference Guide

## Overview
FieldCheck now supports 3 complete service templates with customizable forms, workflows, and SLAs. Each template includes 20-35 specialized form fields for specific service types.

---

## 1️⃣ Aircon Cleaning Service

**Template ID:** `69ee24041e2b350202ee2d61`  
**Service Type:** `aircon_cleaning`  
**Form Fields:** 20  
**Workflow States:** 6  
**SLA:** 24 hours

### Form Fields

#### Customer Information (3 fields)
- **customerName** - Text (2-100 chars)
- **customerEmail** - Email format validation
- **customerPhone** - Phone (10+ digits)

#### Service Location (2 fields)
- **serviceAddress** - Text (5-500 chars)
- **buildingType** - Dropdown: residential, commercial, industrial

#### AC Details (2 fields)
- **unitCount** - Number (1-50 units)
- **unitBrand** - Dropdown: Daikin, Fujitsu, LG, Panasonic, Midea, Gree

#### Service Tasks (1 field - array)
- **serviceChecklist** - Multiple tasks:
  - filter_replacement
  - condenser_cleaning
  - evaporator_cleaning
  - drain_cleaning
  - refrigerant_check
  - electrical_inspection
  - performance_test

#### Issues Assessment (2 fields)
- **issuesFound** - Dropdown: none, minor, major
- **issueDescription** - Text (optional)

#### Parts & Labor (4 fields)
- **partsReplaced** - Array of parts with quantity & cost
- **laborHours** - Number (0-24 hours)
- **laborCost** - Number (SGD)
- **photosRequired** - Boolean

#### Follow-up (3 fields)
- **followUpRequired** - Boolean
- **followUpDate** - Date picker
- **techniciansNotes** - Text (0-2000 chars)

### Workflow States
```
draft → assigned → in_progress → completed → closed
            ↓                         ↓
          cancelled              cancelled
```

### Sample Request
```json
{
  "customerName": "John Tan",
  "customerEmail": "john@example.com",
  "customerPhone": "81234567",
  "serviceAddress": "Block 123, Tampines Ave 5, Singapore 529654",
  "buildingType": "residential",
  "unitCount": 3,
  "unitBrand": "daikin",
  "serviceChecklist": [
    {"task": "filter_replacement", "completed": true, "notes": "Replaced with new unit"},
    {"task": "condenser_cleaning", "completed": true}
  ],
  "issuesFound": "minor",
  "issueDescription": "Slight cooling delay noticed",
  "partsReplaced": [
    {"partName": "AC Filter", "quantity": 3, "cost": 45}
  ],
  "laborHours": 2.5,
  "laborCost": 150,
  "photosRequired": true,
  "followUpRequired": false,
  "techniciansNotes": "All units serviced and tested. Performance normal."
}
```

---

## 2️⃣ Plumbing Service

**Template ID:** `69ee2adfba7882854e7f1e36`  
**Service Type:** `plumbing`  
**Form Fields:** 25  
**Workflow States:** 6  
**SLA:** 24 hours

### Form Fields

#### Customer Information (3 fields)
- **customerName** - Text (2-100 chars)
- **customerEmail** - Email format validation
- **customerPhone** - Phone (10+ digits)

#### Service Location (2 fields)
- **serviceAddress** - Text (5-500 chars)
- **propertyType** - Dropdown: residential, commercial, industrial

#### Issue Description (3 fields)
- **issueType** - Dropdown:
  - leak_detection
  - pipe_repair
  - drain_cleaning
  - fixture_replacement
  - water_heater
  - faucet_repair
  - toilet_repair
  - shower_repair
  - emergency_water_shut
  - other
- **issueDescription** - Text (10-1000 chars)
- **affectedAreas** - Multi-select: kitchen, bathroom, laundry, basement, outdoor

#### Severity (1 field)
- **severity** - Dropdown: low, medium, high, emergency

#### Inspection Findings (1 field - array)
- **inspectionFindings** - Multiple findings:
  - corroded_pipes
  - mineral_buildup
  - tree_root_intrusion
  - leaking_joints
  - cracked_pipes
  - low_pressure
  - water_discoloration

#### Work Performed (1 field - array)
- **workPerformed** - Multiple tasks:
  - pipe_repair
  - pipe_replacement
  - drain_clearing
  - fixture_replacement
  - joint_resealing
  - pressure_relief
  - water_shut_valve
  - flushing

#### Materials (1 field - array)
- **materialsUsed** - Multiple materials with quantity & cost

#### Labor & Cost (2 fields)
- **laborHours** - Number (0-48 hours)
- **laborCost** - Number (SGD)

#### Testing (3 fields)
- **pressureTest** - Boolean
- **pressureTestResult** - Dropdown: passed, failed, not_applicable
- **leakTest** - Boolean (followed by result)
- **leakTestResult** - Dropdown: no_leaks, leaks_found, not_applicable

#### Recommendations (2 fields)
- **recommendations** - Text (0-1000 chars)
- **warrantyOffered** - Boolean
- **warrantyDuration** - Dropdown: 3_months, 6_months, 1_year

#### Follow-up (3 fields)
- **followUpRequired** - Boolean
- **followUpDate** - Date picker
- **plumberNotes** - Text (0-2000 chars)

### Workflow States
```
draft → assigned → in_progress → completed → closed
            ↓                         ↓
          cancelled              cancelled
```

### Sample Request
```json
{
  "customerName": "Maria Wong",
  "customerEmail": "maria@example.com",
  "customerPhone": "91234567",
  "serviceAddress": "42 Clementi Drive, Singapore 129855",
  "propertyType": "residential",
  "issueType": "leak_detection",
  "issueDescription": "Water leaking from kitchen sink pipe under counter",
  "affectedAreas": ["kitchen"],
  "severity": "high",
  "inspectionFindings": [
    {"finding": "leaking_joints", "location": "kitchen sink p-trap", "notes": "Joint compromised"}
  ],
  "workPerformed": [
    {"task": "joint_resealing", "completed": true, "notes": "Resealed with new tape"},
    {"task": "pressure_relief", "completed": true}
  ],
  "materialsUsed": [
    {"material": "PTFE Plumber's Tape", "quantity": "1 roll", "cost": 8}
  ],
  "laborHours": 1.5,
  "laborCost": 90,
  "pressureTest": true,
  "pressureTestResult": "passed",
  "leakTest": true,
  "leakTestResult": "no_leaks",
  "recommendations": "Consider replacing sink assembly within 6 months",
  "warrantyOffered": true,
  "warrantyDuration": "6_months",
  "followUpRequired": false,
  "plumberNotes": "Leak source identified and sealed. Customer satisfied."
}
```

---

## 3️⃣ Electrical Service

**Template ID:** `69ee2b1358571c0cf0e76033`  
**Service Type:** `electrical`  
**Form Fields:** 32  
**Workflow States:** 6  
**SLA:** 24 hours

### Form Fields

#### Customer Information (3 fields)
- **customerName** - Text (2-100 chars)
- **customerEmail** - Email format validation
- **customerPhone** - Phone (10+ digits)

#### Service Location (2 fields)
- **serviceAddress** - Text (5-500 chars)
- **propertyType** - Dropdown: residential, commercial, industrial

#### Electrical System (3 fields)
- **voltage** - Dropdown: 110V, 220V, 380V, three_phase, other
- **panelType** - Dropdown: fuse_box, breaker_box, smart_panel, other
- **panelAmps** - Dropdown: 60, 100, 150, 200, 300, 400, other

#### Issue Type (2 fields)
- **issueType** - Dropdown:
  - power_outage
  - flickering_lights
  - dead_outlet
  - tripped_breaker
  - burning_smell
  - wire_installation
  - rewiring
  - panel_upgrade
  - circuit_installation
  - light_fixture
  - switch_replacement
  - safety_inspection
  - other
- **issueDescription** - Text (10-1000 chars)

#### Affected Areas (1 field)
- **affectedCircuits** - Multi-select: kitchen, bathroom, bedroom, living_room, garage, outdoor, entire_house

#### Safety Issues (1 field)
- **safetyIssues** - Multi-select:
  - overloaded_circuits
  - exposed_wiring
  - improper_grounding
  - outdated_wiring
  - fire_hazard
  - damaged_outlet
  - damaged_switch
  - none

#### Inspection Findings (1 field - array)
- **inspectionFindings** - Multiple findings:
  - faulty_breaker
  - burned_outlet
  - loose_connection
  - bad_wire
  - blown_fuse
  - short_circuit
  - ground_fault
  - voltage_imbalance
  - no_issues_found

#### Work Performed (1 field - array)
- **workPerformed** - Multiple tasks:
  - outlet_replacement
  - switch_replacement
  - breaker_replacement
  - wire_repair
  - wire_replacement
  - circuit_installation
  - grounding_repair
  - light_fixture_installation
  - panel_upgrade
  - load_testing

#### Parts & Materials (1 field - array)
- **partsReplaced** - Multiple items with quantity & cost

#### Testing (6 fields)
- **voltageTest** - Boolean
- **continuityTest** - Boolean
- **groundTest** - Boolean
- **loadTest** - Boolean
- **allTestsPassed** - Boolean

#### Certification (2 fields)
- **certificationRequired** - Boolean
- **certificationNumber** - Text (optional)

#### Labor & Cost (2 fields)
- **laborHours** - Number (0-48 hours)
- **laborCost** - Number (SGD)

#### Recommendations (2 fields)
- **recommendations** - Text (0-1000 chars)
- **urgentRepairsNeeded** - Boolean

#### Warranty (2 fields)
- **warrantyOffered** - Boolean
- **warrantyDuration** - Dropdown: 3_months, 6_months, 1_year

#### Follow-up (3 fields)
- **followUpRequired** - Boolean
- **followUpDate** - Date picker
- **electricianNotes** - Text (0-2000 chars)

### Workflow States
```
draft → assigned → in_progress → completed → closed
            ↓                         ↓
          cancelled              cancelled
```

### Sample Request
```json
{
  "customerName": "David Lim",
  "customerEmail": "david@example.com",
  "customerPhone": "81234567",
  "serviceAddress": "88 Kim Tian Place, Singapore 160088",
  "propertyType": "residential",
  "voltage": "220V",
  "panelType": "breaker_box",
  "panelAmps": "200",
  "issueType": "flickering_lights",
  "issueDescription": "Lights in master bedroom flickering intermittently",
  "affectedCircuits": ["bedroom"],
  "safetyIssues": ["loose_connection"],
  "inspectionFindings": [
    {"finding": "loose_connection", "location": "Master bedroom circuit", "severity": "medium", "notes": "Loose terminal at breaker"}
  ],
  "workPerformed": [
    {"task": "breaker_replacement", "completed": true, "notes": "Replaced faulty breaker"},
    {"task": "load_testing", "completed": true}
  ],
  "partsReplaced": [
    {"part": "20A Breaker", "quantity": "1 unit", "cost": 35}
  ],
  "voltageTest": true,
  "continuityTest": true,
  "groundTest": true,
  "loadTest": true,
  "allTestsPassed": true,
  "certificationRequired": false,
  "laborHours": 1.0,
  "laborCost": 100,
  "recommendations": "Schedule annual electrical inspection",
  "urgentRepairsNeeded": false,
  "warrantyOffered": true,
  "warrantyDuration": "1_year",
  "followUpRequired": false,
  "electricianNotes": "Breaker faulty and replaced. All tests passed. System safe."
}
```

---

## 📊 Templates Comparison

| Aspect | Aircon | Plumbing | Electrical |
|--------|--------|----------|-----------|
| **Fields** | 20 | 25 | 32 |
| **Arrays** | 2 | 3 | 4 |
| **Testing** | ✗ | 2 tests | 4 tests |
| **Certification** | ✗ | ✗ | Certification # |
| **Warranty** | ✗ | ✓ | ✓ |
| **Complexity** | Medium | High | Very High |

---

## 🚀 Using Templates via API

### List All Templates
```bash
curl -X GET https://fieldcheck-backend.onrender.com/api/templates \
  -H "Authorization: Bearer YOUR_TOKEN"
```

Response:
```json
{
  "templates": [
    {
      "_id": "69ee24041e2b350202ee2d61",
      "name": "Aircon Cleaning Service",
      "serviceType": "aircon_cleaning",
      "description": "Comprehensive air conditioning...",
      "fields": 20,
      "sla": "24 hours"
    },
    {
      "_id": "69ee2adfba7882854e7f1e36",
      "name": "Plumbing Service",
      "serviceType": "plumbing",
      "description": "Professional plumbing repair...",
      "fields": 25,
      "sla": "24 hours"
    },
    {
      "_id": "69ee2b1358571c0cf0e76033",
      "name": "Electrical Service",
      "serviceType": "electrical",
      "description": "Professional electrical repair...",
      "fields": 32,
      "sla": "24 hours"
    }
  ]
}
```

### Get Template by ID
```bash
curl -X GET https://fieldcheck-backend.onrender.com/api/templates/69ee24041e2b350202ee2d61 \
  -H "Authorization: Bearer YOUR_TOKEN"
```

### Create Ticket from Template
```bash
curl -X POST https://fieldcheck-backend.onrender.com/api/tickets \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "templateId": "69ee24041e2b350202ee2d61",
    "data": {
      "customerName": "John Tan",
      "customerEmail": "john@example.com",
      "customerPhone": "81234567",
      ...
    }
  }'
```

---

## 🎨 Flutter Integration

### Load Available Templates
```dart
final templates = await ticketService.getTemplates();

// Filter by service type
final airconTemplate = templates.firstWhere(
  (t) => t['serviceType'] == 'aircon_cleaning',
  orElse: () => null,
);
```

### Create Ticket from Template
```dart
final response = await ticketService.createTicket(
  templateId: template['_id'],
  data: {
    'customerName': 'John Tan',
    'customerEmail': 'john@example.com',
    'customerPhone': '81234567',
    // ... rest of form data matching JSON Schema
  },
);

print('Ticket created: ${response['ticketNumber']}'); // AC-0001
```

---

## ✅ Validation Rules

All templates use **JSON Schema v7** validation with AJV:

### Required Fields
- Customer info (name, email, phone)
- Service location (address, property type)
- Issue type & description
- Service-specific fields

### Format Validation
- **Email:** RFC 5321 format
- **Phone:** 10+ digits only
- **Text:** Min/max length enforcement
- **Numbers:** Min/max value enforcement
- **Enum:** Only allowed values accepted

### Example Error Response
```json
{
  "error": "Validation failed",
  "details": [
    {
      "field": "customerEmail",
      "message": "Invalid email format"
    },
    {
      "field": "unitCount",
      "message": "Must be between 1 and 50"
    }
  ]
}
```

---

## 📋 Creating New Templates

To create a new service template (e.g., HVAC, Cleaning, Landscaping):

1. **Create seed file:** `backend/seeds/seedYourServiceTemplate.js`
2. **Define JSON Schema** with required/optional fields
3. **Define workflow states** (draft → assigned → in_progress → completed → closed)
4. **Run seed:** `node backend/seeds/seedYourServiceTemplate.js`
5. **Update Flutter** to show new template option

---

## 🔄 Template Versioning

Each template maintains version history:

```json
{
  "_id": "69ee24041e2b350202ee2d61",
  "version": 1,
  "updatedAt": "2026-04-26T10:30:00Z",
  "history": [
    {"version": 1, "changes": "Initial creation"}
  ]
}
```

Update a template:
```bash
# Edit seed file and run again
node backend/seeds/seedAirconTemplate.js
# Version auto-increments, existing tickets unaffected
```

---

## 🎯 Next Steps

- ✅ 3 templates created (Aircon, Plumbing, Electrical)
- ⏳ Deploy backend to Render
- ⏳ Update Flutter API URLs
- ⏳ Build Flutter APK
- ⏳ Add more templates as needed

---

## 📚 Template IDs Reference

| Service | Type | ID | Fields |
|---------|------|----|----|
| Aircon | aircon_cleaning | 69ee24041e2b350202ee2d61 | 20 |
| Plumbing | plumbing | 69ee2adfba7882854e7f1e36 | 25 |
| Electrical | electrical | 69ee2b1358571c0cf0e76033 | 32 |

---

**FieldCheck is now ready with complete service templates! 🚀**
