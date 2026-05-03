---
name: Aircon Cleaning Template - Implementation Guide
date: April 26, 2026
scope: Ticket template system focused on Aircon Cleaning Service, extensible for future companies
target: Primary implementation for demonstration to aircon cleaning client
---

# Aircon Cleaning Template - Implementation & Deployment Guide

## Quick Overview

This guide walks you through implementing a **single ticket template** for your aircon cleaning client, while building it in a way that's **easily extensible** for other service types in the future.

**Timeline:** ~3 days for one developer (with AI assistance)
- Day 1: Backend template model + API
- Day 2: Validation + sample data
- Day 3: Flutter UI + testing

---

## Part 1: Data Model

### 1.1 TicketTemplate Collection

Create new MongoDB collection with this schema:

```javascript
// backend/models/TicketTemplate.js
const mongoose = require('mongoose');

const templateSchema = new mongoose.Schema({
  // Identity
  id: mongoose.Schema.Types.ObjectId,  // Primary key
  company_id: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Company',
    required: true,
    index: true
  },
  
  // Metadata
  name: {
    type: String,
    required: true,
    example: 'Aircon Cleaning Service'
  },
  
  description: {
    type: String,
    example: 'Standard aircon unit cleaning and maintenance service'
  },
  
  service_type: {
    type: String,
    enum: ['aircon_cleaning', 'pest_control', 'landscaping', 'delivery', 'telecom_maintenance', 'other'],
    required: true,
    example: 'aircon_cleaning'
  },
  
  // JSON Schema for validation (v7)
  json_schema: {
    type: Object,
    required: true,
    example: { /* full schema below */ }
  },
  
  // Workflow configuration
  workflow: {
    states: [String],  // ['open', 'in_progress', 'completed', 'cancelled', ...]
    transitions: Object,  // { 'open': ['in_progress', 'cancelled'], ... }
    permissions: Object   // { 'open': ['FieldWorker', 'Admin'], ... }
  },
  
  // SLA & Escalation
  sla_seconds: {
    type: Number,
    default: 86400,  // 24 hours
    example: 86400
  },
  
  sla_escalation: [{
    threshold_percent: Number,  // 50, 80, 100
    notify: String,             // 'manager', 'admin'
    escalate: Boolean           // true/false
  }],
  
  // Required fields & attachments
  required_attachments: [String],  // ['photos']
  
  // Access control
  visibility: {
    type: String,
    enum: ['private', 'public'],
    default: 'private',
    description: 'private=company only, public=shared across all companies'
  },
  
  // Versioning
  version: {
    type: Number,
    default: 1
  },
  
  # Extensibility for future
  variants: [{
    name: String,                  // 'Residential', 'Commercial'
    description: String,
    json_schema_overrides: Object  // Override specific fields
  }],
  
  tags: [String],  // ['aircon', 'service', 'cleaning', 'residential']
  
  // Audit
  created_by: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User',
    required: true
  },
  
  created_at: {
    type: Date,
    default: Date.now,
    immutable: true
  },
  
  updated_at: {
    type: Date,
    default: Date.now
  },
  
  updated_by: mongoose.Schema.Types.ObjectId,
  
}, { timestamps: true });

// Indexes for performance
templateSchema.index({ company_id: 1, created_at: -1 });
templateSchema.index({ service_type: 1, visibility: 1 });

module.exports = mongoose.model('TicketTemplate', templateSchema);
```

### 1.2 Ticket Collection (Update Existing)

Update the existing Ticket model to reference templates:

```javascript
// backend/models/Ticket.js
const ticketSchema = new mongoose.Schema({
  // UUID for external references
  id: {
    type: String,
    default: () => require('uuid').v4(),
    unique: true
  },
  
  // Human-readable number (AC-0001, AC-0002, etc.)
  ticket_no: {
    type: String,
    required: true,
    index: true,
    unique: true  // Globally unique
  },
  
  // Company scope
  company_id: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Company',
    required: true,
    index: true
  },
  
  // Template reference
  template_id: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'TicketTemplate',
    required: true
  },
  
  template_version: {
    type: Number,
    required: true,
    description: 'Snapshot of template version when ticket was created'
  },
  
  // Form data (arbitrary JSON per template)
  data: {
    type: Object,
    required: true,
    example: {
      customer_name: 'John Doe',
      service_type: 'deep_clean',
      checklist: { filter_cleaned: true, ... },
      photos: ['https://res.cloudinary.com/.../photo.jpg']
    }
  },
  
  // GPS location
  gps: {
    type: {
      lat: Number,
      lng: Number,
      accuracy: Number
    },
    required: false
  },
  
  // Geofence check result
  geofence_check: {
    geofence_id: mongoose.Schema.Types.ObjectId,
    distance_meters: Number,
    status: { enum: ['passed', 'failed'] },
    checked_at: Date
  },
  
  // Attachments (reference to Attachment collection)
  attachments: [{
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Attachment'
  }],
  
  // Workflow
  status: {
    type: String,
    enum: ['open', 'in_progress', 'completed', 'cancelled', 'pending_review'],
    default: 'open',
    index: true
  },
  
  // Assignment
  assignee_id: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User'
  },
  
  # SLA
  sla_due_at: Date,
  sla_escalated_at: Date,
  sla_escalated_to: String,  // 'manager' or 'admin'
  
  # Audit
  created_by: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User',
    required: true
  },
  
  created_at: {
    type: Date,
    default: Date.now,
    immutable: true
  },
  
  updated_at: {
    type: Date,
    default: Date.now
  },
  
}, { timestamps: true });

// Indexes
ticketSchema.index({ company_id: 1, created_at: -1 });
ticketSchema.index({ ticket_no: 1 });
ticketSchema.index({ status: 1, sla_due_at: 1 });

module.exports = mongoose.model('Ticket', ticketSchema);
```

### 1.3 Attachment Collection (New)

For durable attachment storage:

```javascript
// backend/models/Attachment.js
const attachmentSchema = new mongoose.Schema({
  id: mongoose.Schema.Types.ObjectId,
  
  // Reference to ticket
  ticket_id: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Ticket',
    required: true,
    index: true
  },
  
  // Company scope (denormalized for access control)
  company_id: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Company',
    required: true
  },
  
  # Cloud storage reference
  url: {
    type: String,
    required: true,
    example: 'https://res.cloudinary.com/fieldcheck/image/upload/v1234567890/ticket_photo.jpg'
  },
  
  provider: {
    type: String,
    enum: ['cloudinary', 's3', 'local'],
    required: true
  },
  
  # Data integrity
  checksum: {
    type: String,  // SHA256 hash
    required: true,
    index: true
  },
  
  file_size_bytes: Number,
  
  file_type: {
    type: String,
    example: 'image/jpeg'
  },
  
  # Metadata
  filename: String,
  
  uploaded_by: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User',
    required: true
  },
  
  created_at: {
    type: Date,
    default: Date.now,
    immutable: true
  },
  
}, { timestamps: false });

// Indexes
attachmentSchema.index({ ticket_id: 1 });
attachmentSchema.index({ company_id: 1, created_at: -1 });
attachmentSchema.index({ checksum: 1 });  // For deduplication

module.exports = mongoose.model('Attachment', attachmentSchema);
```

---

## Part 2: Backend API

### 2.1 Create Template Endpoint

```javascript
// backend/routes/templates.js
const express = require('express');
const router = express.Router();
const TicketTemplate = require('../models/TicketTemplate');
const { protect, admin } = require('../middleware/authMiddleware');
const Ajv = require('ajv');

const ajv = new Ajv();

// POST /api/companies/:companyId/templates
// Create a new ticket template (Admin only)
router.post('/:companyId/templates', protect, admin, async (req, res) => {
  try {
    const { companyId } = req.params;
    const { name, description, service_type, json_schema, workflow, sla_seconds, required_attachments } = req.body;
    
    // Validate JSON Schema is valid
    try {
      ajv.compile(json_schema);  // Throws if invalid
    } catch (err) {
      return res.status(400).json({ 
        error: 'Invalid JSON Schema',
        details: err.message 
      });
    }
    
    // Create template
    const template = new TicketTemplate({
      company_id: companyId,
      name,
      description,
      service_type,
      json_schema,
      workflow,
      sla_seconds: sla_seconds || 86400,
      required_attachments: required_attachments || [],
      visibility: 'private',
      version: 1,
      created_by: req.user._id
    });
    
    await template.save();
    
    res.status(201).json({
      id: template._id,
      name: template.name,
      version: template.version,
      service_type: template.service_type
    });
    
  } catch (err) {
    console.error('Template creation error:', err);
    res.status(500).json({ error: 'Failed to create template' });
  }
});

// GET /api/companies/:companyId/templates
// List all templates for company
router.get('/:companyId/templates', protect, async (req, res) => {
  try {
    const { companyId } = req.params;
    
    const templates = await TicketTemplate.find({
      company_id: companyId,
      visibility: 'private'
    }).select('name description service_type version created_by created_at');
    
    res.json(templates);
    
  } catch (err) {
    res.status(500).json({ error: 'Failed to list templates' });
  }
});

// GET /api/templates/:templateId
// Get full template with schema
router.get('/templates/:templateId', protect, async (req, res) => {
  try {
    const { templateId } = req.params;
    
    const template = await TicketTemplate.findById(templateId);
    
    if (!template) {
      return res.status(404).json({ error: 'Template not found' });
    }
    
    // Check company access
    if (template.company_id.toString() !== req.user.company_id) {
      return res.status(403).json({ error: 'Access denied' });
    }
    
    res.json({
      id: template._id,
      name: template.name,
      service_type: template.service_type,
      json_schema: template.json_schema,
      workflow: template.workflow,
      sla_seconds: template.sla_seconds,
      required_attachments: template.required_attachments,
      version: template.version
    });
    
  } catch (err) {
    res.status(500).json({ error: 'Failed to fetch template' });
  }
});

module.exports = router;
```

### 2.2 Create Ticket Endpoint

```javascript
// backend/routes/tickets.js
const express = require('express');
const router = express.Router();
const Ticket = require('../models/Ticket');
const TicketTemplate = require('../models/TicketTemplate');
const Geofence = require('../models/Geofence');
const AuditLog = require('../models/AuditLog');
const { protect } = require('../middleware/authMiddleware');
const { v4: uuidv4 } = require('uuid');
const Ajv = require('ajv');

const ajv = new Ajv();

// Helper: Calculate distance between two GPS points
function calculateDistance(lat1, lng1, lat2, lng2) {
  const R = 6371000; // Earth radius in meters
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLng = (lng2 - lng1) * Math.PI / 180;
  const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
            Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
            Math.sin(dLng / 2) * Math.sin(dLng / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

// Helper: Generate human-readable ticket number
async function generateTicketNumber(companyId) {
  const counter = await require('../models/Counter').findOneAndUpdate(
    { company_id: companyId },
    { $inc: { ticket_seq: 1 } },
    { upsert: true, returnDocument: 'after' }
  );
  
  return `AC-${String(counter.ticket_seq).padStart(4, '0')}`;
}

// POST /api/tickets
// Create new ticket
router.post('/', protect, async (req, res) => {
  try {
    const { template_id, data, gps, geofence_id } = req.body;
    const userId = req.user._id;
    const companyId = req.user.company_id;
    
    // 1. Fetch and validate template
    const template = await TicketTemplate.findById(template_id);
    if (!template) {
      return res.status(404).json({ error: 'Template not found' });
    }
    
    // Check company access
    if (template.company_id.toString() !== companyId) {
      return res.status(403).json({ error: 'Cannot access this template' });
    }
    
    // 2. Validate form data against schema
    const valid = ajv.validate(template.json_schema, data);
    if (!valid) {
      return res.status(400).json({
        error: 'Form validation failed',
        validation_errors: ajv.errors
      });
    }
    
    // 3. Validate GPS within geofence (if template requires GPS)
    if (template.json_schema.required.includes('gps') && gps) {
      // Check GPS accuracy
      if (gps.accuracy && gps.accuracy > 50) {
        return res.status(400).json({
          error: 'GPS signal too weak',
          accuracy_meters: gps.accuracy,
          required: '< 50m'
        });
      }
      
      // Check geofence
      if (geofence_id) {
        const geofence = await Geofence.findById(geofence_id);
        if (!geofence) {
          return res.status(404).json({ error: 'Geofence not found' });
        }
        
        const distance = calculateDistance(
          gps.lat, gps.lng,
          geofence.center.lat, geofence.center.lng
        );
        
        if (distance > geofence.radius_meters) {
          return res.status(400).json({
            error: 'Location outside service area',
            distance_meters: Math.round(distance),
            allowed_radius_meters: geofence.radius_meters
          });
        }
        
        // Record geofence check
        data._geofence_check = {
          distance_meters: distance,
          status: 'passed'
        };
      }
    }
    
    // 4. Generate ticket number
    const ticket_no = await generateTicketNumber(companyId);
    
    // 5. Calculate SLA due date
    const sla_due_at = new Date(Date.now() + template.sla_seconds * 1000);
    
    // 6. Create ticket
    const ticket = new Ticket({
      id: uuidv4(),
      ticket_no,
      company_id: companyId,
      template_id: template._id,
      template_version: template.version,
      data,
      gps,
      status: 'open',
      sla_due_at,
      created_by: userId,
      created_at: new Date()
    });
    
    await ticket.save();
    
    // 7. Create audit log
    await AuditLog.create({
      resource_type: 'ticket',
      resource_id: ticket._id,
      action: 'created',
      actor_id: userId,
      details: { ticket_no, template_id },
      created_at: new Date()
    });
    
    // 8. Emit socket event
    const io = require('../server').io;
    io.to(`company:${companyId}`).emit('ticket:created', {
      ticket_no,
      service_type: template.service_type,
      status: 'open'
    });
    
    res.status(201).json({
      id: ticket.id,
      ticket_no,
      status: 'open',
      sla_due_at
    });
    
  } catch (err) {
    console.error('Ticket creation error:', err);
    res.status(500).json({ error: 'Failed to create ticket' });
  }
});

module.exports = router;
```

---

## Part 3: Flutter Implementation

### 3.1 Dynamic Form Renderer

```dart
// field_check/lib/widgets/DynamicFormRenderer.dart
import 'package:flutter/material.dart';
import 'package:json_schema_forms/json_schema_forms.dart';

class DynamicFormRenderer extends StatefulWidget {
  final Map<String, dynamic> jsonSchema;
  final Function(Map<String, dynamic>) onSubmit;
  final Map<String, dynamic>? initialData;
  
  const DynamicFormRenderer({
    required this.jsonSchema,
    required this.onSubmit,
    this.initialData,
  });
  
  @override
  State<DynamicFormRenderer> createState() => _DynamicFormRendererState();
}

class _DynamicFormRendererState extends State<DynamicFormRenderer> {
  final _formKey = GlobalKey<FormState>();
  final _formData = {};
  
  @override
  void initState() {
    super.initState();
    // Initialize form with data
    if (widget.initialData != null) {
      _formData.addAll(widget.initialData!);
    }
  }
  
  Widget _buildField(String fieldName, Map<String, dynamic> fieldSchema) {
    final title = fieldSchema['title'] ?? fieldName;
    final required = widget.jsonSchema['required']?.contains(fieldName) ?? false;
    
    // Text field
    if (fieldSchema['type'] == 'string') {
      return TextFormField(
        initialValue: _formData[fieldName],
        decoration: InputDecoration(
          labelText: title,
          border: OutlineInputBorder(),
          suffixIcon: required ? Icon(Icons.required) : null,
        ),
        validator: (value) {
          if (required && (value?.isEmpty ?? true)) {
            return '$title is required';
          }
          return null;
        },
        onChanged: (value) => _formData[fieldName] = value,
      );
    }
    
    // Boolean field (checkbox)
    else if (fieldSchema['type'] == 'boolean') {
      return CheckboxListTile(
        title: Text(title),
        value: _formData[fieldName] ?? false,
        onChanged: (value) {
          setState(() => _formData[fieldName] = value);
        },
      );
    }
    
    // Enum field (dropdown)
    else if (fieldSchema['enum'] != null) {
      return DropdownButtonFormField<String>(
        value: _formData[fieldName],
        items: (fieldSchema['enum'] as List)
            .map((v) => DropdownMenuItem(value: v, child: Text(v)))
            .toList(),
        onChanged: (value) => _formData[fieldName] = value,
        decoration: InputDecoration(
          labelText: title,
          border: OutlineInputBorder(),
        ),
        validator: (value) {
          if (required && value == null) {
            return '$title is required';
          }
          return null;
        },
      );
    }
    
    // Array of URIs (photo upload)
    else if (fieldSchema['type'] == 'array' && 
             fieldSchema['items']?['format'] == 'uri') {
      return AttachmentPickerWidget(
        title: title,
        required: required,
        onPhotosSelected: (urls) {
          setState(() => _formData[fieldName] = urls);
        },
        initialUrls: _formData[fieldName] ?? [],
      );
    }
    
    // Nested object (checklist)
    else if (fieldSchema['type'] == 'object') {
      return Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
              SizedBox(height: 12),
              ...(fieldSchema['properties'] as Map).entries.map((entry) {
                final nestedFieldName = entry.key;
                final nestedSchema = entry.value as Map;
                return _buildField(
                  '$fieldName.$nestedFieldName',
                  nestedSchema,
                );
              }).toList(),
            ],
          ),
        ),
      );
    }
    
    return SizedBox.shrink();
  }
  
  @override
  Widget build(BuildContext context) {
    final properties = widget.jsonSchema['properties'] as Map;
    
    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            ...properties.entries.map((entry) {
              final fieldName = entry.key;
              final fieldSchema = entry.value as Map;
              return Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: _buildField(fieldName, fieldSchema),
              );
            }).toList(),
            
            SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () {
                if (_formKey.currentState!.validate()) {
                  widget.onSubmit(_formData);
                }
              },
              icon: Icon(Icons.check),
              label: Text('Submit'),
            ),
          ],
        ),
      ),
    );
  }
}
```

### 3.2 Attachment Picker Widget

```dart
// field_check/lib/widgets/AttachmentPickerWidget.dart
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;

class AttachmentPickerWidget extends StatefulWidget {
  final String title;
  final bool required;
  final Function(List<String>) onPhotosSelected;
  final List<String> initialUrls;
  
  const AttachmentPickerWidget({
    required this.title,
    required this.required,
    required this.onPhotosSelected,
    this.initialUrls = const [],
  });
  
  @override
  State<AttachmentPickerWidget> createState() => _AttachmentPickerWidgetState();
}

class _AttachmentPickerWidgetState extends State<AttachmentPickerWidget> {
  List<String> _selectedUrls = [];
  bool _uploading = false;
  
  @override
  void initState() {
    super.initState();
    _selectedUrls.addAll(widget.initialUrls);
  }
  
  Future<void> _pickAndUploadPhoto() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.camera);
    
    if (pickedFile == null) return;
    
    setState(() => _uploading = true);
    
    try {
      // 1. Request signed URL from backend
      final signedUrlResponse = await http.post(
        Uri.parse('${ApiConstants.baseUrl}/api/uploads/signed-url'),
        headers: ApiConstants.authHeaders,
        body: {
          'file_type': 'image/jpeg',
          'file_size': File(pickedFile.path).lengthSync(),
        },
      );
      
      if (signedUrlResponse.statusCode != 200) {
        throw Exception('Failed to get signed URL');
      }
      
      final signedUrl = jsonDecode(signedUrlResponse.body)['signed_url'];
      
      // 2. Upload directly to Cloudinary
      final uploadResponse = await http.put(
        Uri.parse(signedUrl),
        body: await File(pickedFile.path).readAsBytes(),
        headers: { 'Content-Type': 'image/jpeg' },
      );
      
      if (uploadResponse.statusCode != 200) {
        throw Exception('Upload failed');
      }
      
      // 3. Parse response to get URL
      final cloudinaryResponse = jsonDecode(uploadResponse.body);
      final uploadedUrl = cloudinaryResponse['secure_url'];
      
      setState(() {
        _selectedUrls.add(uploadedUrl);
        widget.onPhotosSelected(_selectedUrls);
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Photo uploaded successfully')),
      );
      
    } catch (err) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload failed: $err')),
      );
    } finally {
      setState(() => _uploading = false);
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
            if (widget.required)
              Text(' *', style: TextStyle(color: Colors.red, fontSize: 18)),
          ],
        ),
        SizedBox(height: 12),
        
        // Photo grid
        GridView.builder(
          shrinkWrap: true,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            spacing: 8,
            childAspectRatio: 1,
          ),
          itemCount: _selectedUrls.length + 1,
          itemBuilder: (context, index) {
            // Add button
            if (index == _selectedUrls.length) {
              return GestureDetector(
                onTap: _uploading ? null : _pickAndUploadPhoto,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: _uploading
                      ? CircularProgressIndicator()
                      : Icon(Icons.add_a_photo, size: 32),
                ),
              );
            }
            
            // Photo thumbnail
            return Stack(
              children: [
                Image.network(_selectedUrls[index], fit: BoxFit.cover),
                Positioned(
                  top: 0,
                  right: 0,
                  child: GestureDetector(
                    onTap: () {
                      setState(() => _selectedUrls.removeAt(index));
                      widget.onPhotosSelected(_selectedUrls);
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.close, color: Colors.white, size: 16),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        
        // Validation message
        if (widget.required && _selectedUrls.isEmpty)
          Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'At least one photo required',
              style: TextStyle(color: Colors.red, fontSize: 12),
            ),
          ),
      ],
    );
  }
}
```

---

## Part 4: Seeded Data

### 4.1 Aircon Template JSON

Create seed script: `backend/seeds/aircon_template.js`

```javascript
const mongoose = require('mongoose');
const TicketTemplate = require('../models/TicketTemplate');

const airconTemplate = {
  name: 'Aircon Cleaning Service',
  description: 'Standard aircon unit cleaning and maintenance service',
  service_type: 'aircon_cleaning',
  
  json_schema: {
    '$id': 'aircon-cleaning-v1',
    '$schema': 'http://json-schema.org/draft-07/schema#',
    'type': 'object',
    'title': 'Aircon Cleaning Service Ticket',
    'required': [
      'customer_name',
      'service_type',
      'photos',
      'checklist',
      'gps'
    ],
    'properties': {
      'customer_name': {
        'type': 'string',
        'title': 'Customer Name',
        'minLength': 1
      },
      'service_type': {
        'type': 'string',
        'title': 'Service Type',
        'enum': ['inspection', 'deep_clean', 'repair', 'maintenance', 'emergency'],
        'default': 'inspection'
      },
      'unit_serial': {
        'type': 'string',
        'title': 'Unit Serial Number',
        'minLength': 3
      },
      'location_address': {
        'type': 'string',
        'title': 'Service Location Address',
        'minLength': 5
      },
      'checklist': {
        'type': 'object',
        'title': 'Service Checklist',
        'properties': {
          'filter_cleaned': {
            'type': 'boolean',
            'title': 'Filter Cleaned'
          },
          'coil_cleaned': {
            'type': 'boolean',
            'title': 'Coil Cleaned'
          },
          'drain_cleared': {
            'type': 'boolean',
            'title': 'Drain Cleared'
          },
          'refrigerant_checked': {
            'type': 'boolean',
            'title': 'Refrigerant Level Checked'
          },
          'electrical_tested': {
            'type': 'boolean',
            'title': 'Electrical Connections Tested'
          }
        },
        'required': ['filter_cleaned', 'coil_cleaned', 'drain_cleared']
      },
      'photos': {
        'type': 'array',
        'title': 'Service Photos (Before/After)',
        'items': { 'type': 'string', 'format': 'uri' },
        'minItems': 1,
        'maxItems': 10
      },
      'gps': {
        'type': 'object',
        'title': 'GPS Location',
        'required': ['lat', 'lng'],
        'properties': {
          'lat': {
            'type': 'number',
            'minimum': -90,
            'maximum': 90
          },
          'lng': {
            'type': 'number',
            'minimum': -180,
            'maximum': 180
          },
          'accuracy': {
            'type': 'number',
            'title': 'GPS Accuracy (meters)'
          }
        }
      },
      'notes': {
        'type': 'string',
        'title': 'Additional Notes',
        'maxLength': 500
      },
      'parts_replaced': {
        'type': 'array',
        'title': 'Parts Replaced',
        'items': {
          'type': 'object',
          'properties': {
            'part_name': { 'type': 'string' },
            'quantity': { 'type': 'integer', 'minimum': 1 }
          }
        }
      }
    },
    'additionalProperties': false
  },
  
  workflow: {
    states: ['open', 'in_progress', 'completed', 'cancelled', 'pending_review'],
    transitions: {
      'open': ['in_progress', 'cancelled'],
      'in_progress': ['completed', 'pending_review', 'open'],
      'pending_review': ['completed', 'open'],
      'completed': [],
      'cancelled': []
    },
    permissions: {
      'open': ['FieldWorker', 'Admin'],
      'in_progress': ['FieldWorker'],
      'pending_review': ['Manager', 'Admin'],
      'completed': ['Admin'],
      'cancelled': ['Admin']
    }
  },
  
  sla_seconds: 86400,  // 24 hours
  required_attachments: ['photos'],
  visibility: 'private',
  version: 1,
  tags: ['aircon', 'service', 'cleaning']
};

async function seedAirconTemplate() {
  try {
    const existing = await TicketTemplate.findOne({ name: 'Aircon Cleaning Service' });
    if (existing) {
      console.log('Aircon template already exists');
      return;
    }
    
    // Create template with default company ID
    const template = new TicketTemplate({
      ...airconTemplate,
      company_id: new mongoose.Types.ObjectId('626f3a9d4c7f6e4d3c2b1a0f'),  // Replace with actual company ID
      created_by: new mongoose.Types.ObjectId('626f3a9d4c7f6e4d3c2b1a0e')   // Replace with admin ID
    });
    
    await template.save();
    console.log('✅ Aircon template seeded successfully');
    
  } catch (err) {
    console.error('❌ Error seeding template:', err);
  }
}

module.exports = seedAirconTemplate;
```

Run seed:
```bash
node backend/seeds/aircon_template.js
```

---

## Part 5: Testing Checklist

### Backend Tests

```bash
✅ POST /api/companies/{id}/templates - Create aircon template
❌ POST /api/companies/{wrong_id}/templates - Reject unauthorized
✅ GET /api/companies/{id}/templates - List templates
✅ POST /api/tickets - Create ticket with valid form data
❌ POST /api/tickets - Reject invalid form data (missing required fields)
❌ POST /api/tickets - Reject GPS outside geofence
✅ POST /api/tickets - Accept GPS inside geofence
✅ GET /api/tickets/{id} - Retrieve ticket
❌ GET /api/tickets/{id} - Reject unauthorized access (different company)
```

Run tests:
```bash
npm test backend/tests/template.test.js
npm test backend/tests/ticket.test.js
```

### Flutter Tests

```
✅ DynamicFormRenderer renders aircon template
✅ Form validation rejects missing required fields
✅ AttachmentPicker uploads photo to Cloudinary
✅ Form submission sends valid JSON to server
✅ Error message shown if validation fails
```

---

## Part 6: Extensibility for Future Services

**By Design:** The template system is already built to support multiple service types.

**To Add Pest Control Service (Example):**

```javascript
// 1. Create new JSON Schema
const pestControlTemplate = {
  name: 'Pest Control Service',
  service_type: 'pest_control',
  json_schema: { /* pest control schema */ }
  // ... rest of template
};

// 2. Seed it
db.ticket_templates.insertOne({ ...pestControlTemplate, company_id: ... });

// 3. Flutter automatically renders it (no code change!)
// DynamicFormRenderer handles any schema
```

**No Code Changes Needed:**
- Backend API already handles any schema
- Flutter renderer works with any JSON Schema
- Just add new template with different `service_type`

**Variants for Same Service:**

```javascript
{
  name: 'Aircon Cleaning',
  variants: [
    { name: 'Residential', json_schema_overrides: { ... } },
    { name: 'Commercial', json_schema_overrides: { ... } }
  ]
}
```

---

## Deployment Checklist

- [ ] MongoDB collections created (TicketTemplate, Ticket, Attachment)
- [ ] Backend routes added and tested
- [ ] Flutter widgets added and tested
- [ ] Cloudinary/S3 account configured
- [ ] Environment variables set (API keys, Cloudinary URL)
- [ ] Aircon template seeded
- [ ] Demo script works end-to-end
- [ ] Production build tested

---

## Demo Script (5 minutes)

1. **Admin logs in** → Views Templates tab → Shows "Aircon Cleaning Service"
2. **Admin creates ticket** → Selects Aircon template → Fills customer name → Assigns to field worker
3. **Field worker logs in** → Views ticket "AC-0001"
4. **Field worker tries check-in outside geofence** → Error: "100m outside service area"
5. **Field worker moves into geofence** → Check-in succeeds
6. **Field worker opens form** → Dynamically rendered from template
7. **Field worker fills checklist** → Uploads photo (Cloudinary URL shown)
8. **Field worker submits** → Ticket status → "completed"
9. **Admin views ticket** → Shows photo, audit trail, SLA status → "Completed on time"

---

**Total Timeline:** ~3 days for one developer (with AI assistance for implementation)

**Ready to proceed?** You can now implement this step-by-step with the agent's help!
