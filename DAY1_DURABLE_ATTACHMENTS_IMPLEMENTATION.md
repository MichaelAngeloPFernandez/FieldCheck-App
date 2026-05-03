# Day 1: Durable Attachments - Integration Guide

## Overview
Converted ephemeral attachment system to persistent storage using MongoDB + Render storage.

**What was created:**
- ✅ `Attachment.js` - MongoDB model for attachment metadata
- ✅ `StorageService.js` - Service for file CRUD operations
- ✅ `attachmentRoutes.js` - REST endpoints (upload, retrieve, delete)
- ✅ `attachment_service.dart` - Flutter client service
- ✅ `attachment_picker_widget.dart` - Flutter UI widget
- ✅ Updated `Report.js` to reference attachments via IDs

**Key improvement:** Files now persist across server restart.

---

## Backend Integration

### 1. Initialize Storage Service
In `backend/server.js`, add to the initialization section (after connectDB):

```javascript
// Around line 100 (after connectDB)
const StorageService = require('./services/StorageService');

// ... later in the code, before starting server ...

// Initialize storage
await StorageService.init();
console.log('✓ Storage service initialized');
```

### 2. Using Attachments in Reports
When creating/updating a report, send attachment IDs in the body:

```javascript
// Example POST /api/reports
{
  "type": "task",
  "taskId": "507f1f77bcf86cd799439011",
  "content": "Task completed with photos",
  "attachmentIds": [
    "507f1f77bcf86cd799439012",
    "507f1f77bcf86cd799439013"
  ]
}
```

### 3. Modify reportController.js
Update the POST endpoint to handle attachments:

```javascript
// In reportController.js, createReport function
exports.createReport = async (req, res) => {
  try {
    const { type, taskId, content, attendanceId, attachmentIds } = req.body;

    const report = new Report({
      type,
      task: taskId,
      attendance: attendanceId,
      employee: req.user._id,
      content,
      attachmentIds: attachmentIds || [], // NEW: Reference attachment IDs
      status: 'submitted',
    });

    await report.save();
    await report.populate('attachmentIds'); // NEW: Populate attachment details

    res.status(201).json(report);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};
```

### 4. Test with cURL

**Upload a file:**
```bash
curl -X POST http://localhost:5000/api/attachments/upload \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -F "file=@/path/to/photo.jpg" \
  -F "resourceType=report" \
  -F "resourceId=507f1f77bcf86cd799439011"
```

Response:
```json
{
  "_id": "507f1f77bcf86cd799439020",
  "fileName": "photo.jpg",
  "fileSize": 1024000,
  "url": "/api/attachments/1699123456789-abc123-photo.jpg",
  "uploadedAt": "2024-11-05T10:00:00Z"
}
```

**Retrieve file:**
```bash
curl -X GET http://localhost:5000/api/attachments/1699123456789-abc123-photo.jpg/file \
  -H "Authorization: Bearer YOUR_JWT_TOKEN"
```

**Get all attachments for a report:**
```bash
curl -X GET "http://localhost:5000/api/resources/report/507f1f77bcf86cd799439011/attachments" \
  -H "Authorization: Bearer YOUR_JWT_TOKEN"
```

---

## Flutter Integration

### 1. Add Dependencies
Update `field_check/pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter
  http: ^1.1.0
  image_picker: ^1.0.0
  file_picker: ^6.0.0
  shared_preferences: ^2.2.0
```

Run: `flutter pub get`

### 2. Initialize Attachment Service
In your main App or auth module:

```dart
import 'package:field_check/services/attachment_service.dart';

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: MyHomePage(),
    );
  }
}

// In your auth/home screen after login:
final attachmentService = AttachmentService(
  apiBaseUrl: 'http://your-render-url.com',
);
await attachmentService.init();

// Pass to widgets:
AttachmentPickerWidget(
  resourceType: 'report',
  resourceId: reportId,
  attachmentService: attachmentService,
  onAttachmentUploaded: (attachment) {
    print('Uploaded: ${attachment['fileName']}');
  },
)
```

### 3. Use in Report Creation Screen

Example:

```dart
import 'package:flutter/material.dart';
import '../widgets/attachment_picker_widget.dart';
import '../services/attachment_service.dart';

class ReportCreationScreen extends StatefulWidget {
  final String reportId;
  final AttachmentService attachmentService;

  const ReportCreationScreen({
    required this.reportId,
    required this.attachmentService,
  });

  @override
  State<ReportCreationScreen> createState() => _ReportCreationScreenState();
}

class _ReportCreationScreenState extends State<ReportCreationScreen> {
  List<Map<String, dynamic>> _attachments = [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Report')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ... other form fields ...

          const SizedBox(height: 24),
          AttachmentPickerWidget(
            resourceType: 'report',
            resourceId: widget.reportId,
            attachmentService: widget.attachmentService,
            onAttachmentUploaded: (attachment) {
              setState(() {
                _attachments.add(attachment);
              });
            },
          ),

          const SizedBox(height: 24),
          Text('Attached Files: ${_attachments.length}'),
          ..._attachments.map((att) => ListTile(
            title: Text(att['fileName']),
            subtitle: Text('${att['fileSize']} bytes'),
            trailing: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () async {
                try {
                  await widget.attachmentService.deleteAttachment(att['_id']);
                  setState(() => _attachments.removeWhere((a) => a['_id'] == att['_id']));
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Delete failed: $e')),
                  );
                }
              },
            ),
          )),

          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _submitReport,
            child: const Text('Submit Report'),
          ),
        ],
      ),
    );
  }

  void _submitReport() {
    // Send report with attachmentIds
    final attachmentIds = _attachments.map((a) => a['_id']).toList();
    // TODO: Call API with attachmentIds
  }
}
```

### 4. Update API Service
Add to your http client service:

```dart
// In your existing API service file
import '../services/attachment_service.dart';

class ApiService {
  final AttachmentService attachmentService;

  ApiService({required this.attachmentService});

  Future<Map<String, dynamic>> createReport({
    required String reportId,
    required String content,
    required List<String> attachmentIds,
  }) async {
    final response = await http.post(
      Uri.parse('$apiBaseUrl/api/reports'),
      headers: {'Authorization': 'Bearer $token'},
      body: jsonEncode({
        'content': content,
        'attachmentIds': attachmentIds,
      }),
    );

    if (response.statusCode == 201) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to create report');
    }
  }
}
```

---

## Testing Persistence

### Test 1: Upload → Restart → Retrieve
1. Upload a file via AttachmentPickerWidget
2. Note the attachment ID and filename
3. **Restart backend server** (`npm start`)
4. Call GET `/api/attachments/:attachmentId` → ✅ Should still return metadata
5. Call GET `/api/attachments/:storageName/file` → ✅ Should still download file

### Test 2: Soft Delete
1. Call DELETE `/api/attachments/:attachmentId`
2. Call GET `/api/attachments/:attachmentId` → ✅ Should return 404 (soft deleted)
3. Check MongoDB: `db.attachments.findById(_id)` → Should have `isDeleted: true`

### Test 3: Report with Attachments
1. Create report with attachment IDs in body
2. Verify report.attachmentIds has array of IDs
3. Query report with populate:
```javascript
Report.findById(reportId).populate('attachmentIds')
  .then(r => console.log(r.attachmentIds))
```

---

## Database Schema (Verify)

```javascript
// Check with MongoDB compass or Mongo shell:
db.attachments.findOne()

// Should look like:
{
  "_id": ObjectId("674abc..."),
  "resourceType": "report",
  "resourceId": ObjectId("674def..."),
  "fileName": "photo.jpg",
  "fileSize": 1024000,
  "fileType": "image/jpeg",
  "url": "/api/attachments/1699123456789-abc123-photo.jpg",
  "provider": "render",
  "checksum": "sha256hash...",
  "uploadedBy": ObjectId("674xyz..."),
  "uploadedAt": ISODate("2024-11-05T10:00:00Z"),
  "isDeleted": false,
  "createdAt": ISODate("2024-11-05T10:00:00Z"),
  "updatedAt": ISODate("2024-11-05T10:00:00Z")
}
```

---

## Common Issues & Solutions

### Issue: "Multer not found" on upload
**Solution:** Install multer
```bash
cd backend && npm install multer
```

### Issue: Files disappear after restart (ephemeral storage)
**Note:** This is EXPECTED on Render's free tier. Files in `/uploads` are ephemeral.
**Future upgrade:** Move to Cloudinary or AWS S3:
- Install: `npm install cloudinary multer-storage-cloudinary`
- Update StorageService.js upload logic
- Change provider enum to include 'cloudinary'
- No database changes needed (metadata stays same)

### Issue: "Not authenticated" error
**Solution:** Ensure JWT token is passed:
```dart
attachmentService.updateAuthToken(jwtToken); // After login
```

### Issue: CORS error on upload
**Solution:** Ensure `/api/attachments/upload` is before CORS middleware in server.js

---

## What's Next (Day 2)

Tomorrow we implement:
- Template system with JSON Schema validation
- Dynamic form creation from templates
- Ticket model with state machine workflow

Today's work is **DONE** ✅ - All files persist across restarts!
