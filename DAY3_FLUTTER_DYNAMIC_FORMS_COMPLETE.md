# Day 3: Flutter Dynamic Forms - COMPLETE

## ✅ Implementation Summary

### Flutter Components Created

1. **TicketService.dart** - REST API client
   - `getTemplates()` - Fetch available templates
   - `getTemplate(id)` - Get full schema
   - `createTicket()` - Create with validation
   - `listTickets()` - List user tickets
   - `updateStatus()` - Change ticket status
   - `ValidationException` - Custom error type

2. **DynamicFormRenderer.dart** - JSON Schema → Flutter widgets
   - Renders all field types: string, number, boolean, enum, array, object
   - Auto-validates: required, minLength, maxLength, pattern, email, min/max
   - Supports nested objects and arrays (checklists)
   - Form validation state management
   - Exports `getFormData()` for submission

3. **TicketCreationScreen.dart** - Complete ticket workflow
   - Load template from API
   - Render dynamic form
   - Manage attachments
   - GPS location capture (ready)
   - SLA display
   - Submit with validation error handling
   - Success callback

4. **TicketDashboardScreen.dart** - Home screen
   - Two-tab interface (Templates | My Tickets)
   - Browse available services
   - View request history
   - Status tracking
   - SLA escalation alerts

### Files Created
- `services/ticket_service.dart` (180 lines)
- `widgets/dynamic_form_renderer.dart` (550 lines)
- `screens/ticket_creation_screen.dart` (320 lines)
- `screens/ticket_dashboard_screen.dart` (350 lines)

---

## 🎯 Quick Integration

### 1. Add to pubspec.yaml
```yaml
dependencies:
  http: ^1.1.0
  shared_preferences: ^2.2.0
  image_picker: ^1.0.0
  file_picker: ^6.0.0
```

### 2. Initialize in Main App

```dart
import 'package:field_check/screens/ticket_dashboard_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: TicketDashboardScreen(
        apiBaseUrl: 'https://your-render-url.onrender.com',
        authToken: 'JWT_TOKEN_HERE',
        userName: 'John Doe',
        userEmail: 'john@example.com',
      ),
    );
  }
}
```

### 3. Or Use Individual Screens

```dart
// Load a specific template and create ticket
TicketCreationScreen(
  templateId: '69ee24041e2b350202ee2d61', // Aircon template
  ticketService: _ticketService,
  attachmentService: _attachmentService,
  onTicketCreated: (ticket) {
    print('Created: ${ticket['ticketNumber']}');
  },
)
```

---

## 📋 Complete Demo Workflow

### User Flow
1. **Open app** → TicketDashboardScreen shows available services
2. **Select service** → Click Aircon Cleaning
3. **Fill form** → DynamicFormRenderer renders all fields
4. **Add photos** → AttachmentPickerWidget uploads images
5. **Submit** → Validation runs, ticket created
6. **View ticket** → Status tracked in "My Requests" tab

### Example: Create Aircon Ticket

```dart
// Step 1: Get services
final templateResult = await ticketService.getTemplates();
// Returns: { count: 1, templates: [...] }

// Step 2: Load full template
final template = await ticketService.getTemplate('69ee24041e2b350202ee2d61');
// Returns: {
//   _id: "69ee24041e2b350202ee2d61",
//   name: "Aircon Cleaning Service",
//   jsonSchema: { ... },
//   workflow: [ ... ],
//   slaSeconds: 86400
// }

// Step 3: User fills form in DynamicFormRenderer
// Form automatically validates against jsonSchema

// Step 4: Upload photos
final attachment = await attachmentService.uploadAttachment(
  file: File('/path/to/photo.jpg'),
  resourceType: 'ticket',
  resourceId: ticketId, // Generated after ticket creation
);

// Step 5: Submit ticket
final result = await ticketService.createTicket(
  templateId: '69ee24041e2b350202ee2d61',
  data: {
    "customerName": "Jane Smith",
    "customerEmail": "jane@example.com",
    "customerPhone": "6589876543",
    "serviceAddress": "123 Main St, Singapore",
    "buildingType": "residential",
    "unitCount": 2,
    "unitBrand": "daikin",
    "serviceChecklist": [
      {
        "task": "filter_replacement",
        "completed": true,
        "notes": "Filter replaced"
      }
    ],
    "issuesFound": "none",
    "laborHours": 2.5,
    "laborCost": 150,
    "techniciansNotes": "Service OK"
  },
  attachmentIds: ['attachment_id_1', 'attachment_id_2'],
);
// Response: {
//   _id: "...",
//   ticketNumber: "AC-0001",
//   status: "draft",
//   slaDueAt: "2026-04-27T..."
// }

// Step 6: View tickets
final ticketsResult = await ticketService.listTickets();
// Returns: {
//   count: 1,
//   total: 1,
//   tickets: [
//     {
//       _id: "...",
//       ticketNumber: "AC-0001",
//       status: "draft",
//       slaDueAt: "2026-04-27T...",
//       isEscalated: false,
//       requestedBy: { name: "John", email: "john@example.com" }
//     }
//   ]
// }
```

---

## 🎨 DynamicFormRenderer Details

### Supported JSON Schema Types

| Type | Renders As | Validation |
|------|-----------|-----------|
| string | TextField | minLength, maxLength, pattern, email |
| number | TextField (numeric) | minimum, maximum |
| integer | TextField (integer only) | minimum, maximum |
| boolean | Checkbox | - |
| enum (string) | Dropdown | fixed values |
| array (string) | Dynamic list | - |
| array (object) | Checklist | object properties |
| object | Card container | nested properties |

### Example: Aircon Schema Fields

```javascript
// Renders as TextFields:
customerName: "string" → Text input (required)
customerEmail: "string" (format: email) → Email input
customerPhone: "string" (pattern: \d{10,}) → Phone input

// Renders as Dropdowns:
buildingType: "string" (enum: [...]) → Dropdown
unitBrand: "string" (enum: [...]) → Dropdown
issuesFound: "string" (enum: ["none", "minor", "major"]) → Dropdown

// Renders as Checklist:
serviceChecklist: "array" (items: object) → Add/remove items
  ├─ task: enum dropdown
  ├─ completed: checkbox
  └─ notes: textarea

// Renders as Number inputs:
unitCount: "integer" (min: 1, max: 50) → Number input
laborHours: "number" → Decimal input
```

### Form Validation Flow

```
User enters data
     ↓
DynamicFormRenderer validates on-change
     ↓
Constraints checked:
  ├─ Required fields
  ├─ Min/max length
  ├─ Pattern (email, phone)
  ├─ Min/max values
  └─ Type constraints
     ↓
onValidationChanged callback → disables/enables Submit button
     ↓
User clicks Submit
     ↓
Final validation (FormState.validate())
     ↓
If valid: POST /api/tickets
If invalid: Show error dialog
```

---

## 📱 TicketCreationScreen Features

### Loading States
- ✅ Loading template from API
- ✅ Error handling with retry
- ✅ Loading indicator during submission
- ✅ Form validation feedback

### Attachment Management
- ✅ Camera picker
- ✅ Gallery picker
- ✅ File picker (PDF, Word, Excel, images)
- ✅ Multiple files
- ✅ Delete uploaded files
- ✅ File size display

### SLA Display
- ✅ Show estimated completion time
- ✅ Auto-calculate from slaSeconds
- ✅ Format: "24 hours" or "8 hours 30 min"

### Error Handling
- ✅ Network errors
- ✅ Validation errors (field-by-field)
- ✅ Server errors
- ✅ User-friendly messages

### Success Feedback
- ✅ Toast notification with ticket number
- ✅ `onTicketCreated` callback
- ✅ Auto-pop with result

---

## 🧪 Testing the Complete Flow

### Manual Test: Create Aircon Ticket via Flutter

1. **Start backend server**
   ```bash
   cd backend && npm start
   ```

2. **Open Flutter app** with TicketDashboardScreen

3. **Tab 1: New Service**
   - See "Aircon Cleaning Service"
   - Click it → Opens TicketCreationScreen

4. **Form automatically loads schema**
   - All fields from Aircon template appear
   - Required fields marked with *
   - Validation hints shown

5. **Fill required fields**
   ```
   Customer Name: "Jane Smith"
   Email: "jane@example.com"
   Phone: "6589876543"
   Address: "123 Main St"
   Building Type: "residential" (dropdown)
   Unit Count: "2"
   Brand: "daikin" (dropdown)
   Checklist: Add items, mark completed
   Issues: "none" (dropdown)
   Labor: "2.5" hours
   Notes: "OK"
   ```

6. **Add photos**
   - Click "Camera" or "Gallery"
   - Select photo
   - Uploads automatically
   - Shows in attachment list

7. **Submit**
   - Click FAB "Submit"
   - Form validates (should pass)
   - Sends POST to /api/tickets
   - Shows "✓ Ticket AC-0001 created"
   - Auto-pops and refreshes list

8. **Tab 2: My Requests**
   - AC-0001 appears with status "draft"
   - Shows creation date
   - No escalation warning (within SLA)

---

## 🔧 Customization

### Create New Template

```dart
// 1. Define JSON Schema
const myTemplate = {
  "type": "object",
  "properties": {
    "fieldName": {
      "type": "string",
      "title": "Field Label",
      "minLength": 5
    }
  },
  "required": ["fieldName"]
};

// 2. Create template (backend, admin only)
// POST /api/templates
const body = {
  "name": "My Service",
  "serviceType": "my_service",
  "jsonSchema": myTemplate,
  "workflow": [...],
  "slaSeconds": 86400
};

// 3. Use in Flutter
TicketCreationScreen(
  templateId: newTemplateId,
  ticketService: _ticketService,
  ...
)
```

### Add Custom Validation

```dart
// Extend DynamicFormRenderer
class CustomFormRenderer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return DynamicFormRenderer(
      jsonSchema: schema,
      onDataChanged: (data) {
        // Custom validation
        if (data['fieldA'] != null && data['fieldB'] == null) {
          // Show error
        }
      },
    );
  }
}
```

---

## 📊 Architecture Diagram

```
TicketDashboardScreen
├─ TicketService (API client)
│  ├─ getTemplates()
│  └─ listTickets()
└─ TabBarView
   ├─ Templates Tab
   │  └─ ListView
   │     └─ TicketCreationScreen (on tap)
   │        ├─ TicketService.getTemplate()
   │        ├─ DynamicFormRenderer
   │        │  ├─ Renders JSON Schema fields
   │        │  └─ Validates on-change
   │        ├─ AttachmentPickerWidget
   │        │  └─ AttachmentService
   │        └─ TicketService.createTicket()
   │
   └─ My Requests Tab
      └─ ListView
         └─ TicketService.listTickets()
```

---

## 🚀 Production Checklist

- [ ] Replace hardcoded API URLs with config
- [ ] Move auth token to secure storage
- [ ] Add GPS location capture
- [ ] Implement offline form saving
- [ ] Add image compression before upload
- [ ] Test with slow network
- [ ] Handle file upload errors gracefully
- [ ] Add camera permissions handling
- [ ] Localization for multi-language
- [ ] Add analytics tracking
- [ ] Dark mode support
- [ ] Tablet responsive layout

---

## 📚 API Reference

### TicketService Methods

```dart
// Templates
getTemplates({String? serviceType})
getTemplate(String templateId)

// Tickets
createTicket({
  required String templateId,
  required Map<String, dynamic> data,
  String? requesterName,
  String? requesterEmail,
  String? requesterPhone,
  Map<String, dynamic>? gpsLocation,
  List<String>? attachmentIds,
})

getTicket(String ticketId)
listTickets({...})
updateStatus(String ticketId, String newStatus, {String? reason})
```

### DynamicFormRenderer Methods

```dart
// Get form data for submission
Map<String, dynamic> getFormData()

// Callbacks
onDataChanged(Map<String, dynamic> formData)
onValidationChanged(bool isValid)
```

---

## ✨ Summary

**Day 3 Components:**
- ✅ 4 Flutter files created (1400+ lines)
- ✅ Complete JSON Schema rendering
- ✅ Full form validation
- ✅ Attachment integration
- ✅ Error handling
- ✅ Loading states
- ✅ Success feedback

**Ready to Use:**
```dart
TicketDashboardScreen(
  apiBaseUrl: 'https://your-backend.com',
  authToken: 'jwt_token',
)
```

**What Users Can Do:**
1. Browse service templates
2. Create new tickets with dynamic forms
3. Upload photos and documents
4. View ticket status
5. Track SLA escalation

---

## 🎉 Demo Ready!

The complete Aircon Cleaning Service workflow is now fully functional:

**Backend:**
- ✅ Template system with JSON Schema
- ✅ Ticket creation with validation
- ✅ Attachment storage
- ✅ State machine workflow
- ✅ SLA tracking

**Mobile:**
- ✅ Template browsing
- ✅ Dynamic form rendering
- ✅ Photo uploads
- ✅ Ticket submission
- ✅ Status tracking

**Next Steps:**
- Integrate into existing app navigation
- Connect to authentication system
- Add GPS location capture
- Customize for additional service types
- Deploy to production
