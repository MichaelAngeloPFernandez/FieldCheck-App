/**
 * Seed Script: Plumbing Service Template
 * 
 * Run with: node backend/seeds/seedPlumbingTemplate.js
 * 
 * Creates a complete template for Plumbing service with:
 * - JSON Schema for form validation
 * - Workflow state machine
 * - SLA (24 hours)
 */

require('dotenv').config();
const mongoose = require('mongoose');
const TicketTemplate = require('../models/TicketTemplate');

const MONGO_URI = process.env.MONGODB_URI || process.env.MONGO_URI;

// JSON Schema for Plumbing Service
const PLUMBING_JSON_SCHEMA = {
  type: 'object',
  properties: {
    // Customer info
    customerName: {
      type: 'string',
      minLength: 2,
      maxLength: 100,
      title: 'Customer Name',
    },
    customerEmail: {
      type: 'string',
      format: 'email',
      title: 'Email Address',
    },
    customerPhone: {
      type: 'string',
      pattern: '^[0-9]{10,}$',
      title: 'Phone Number',
    },

    // Service location
    serviceAddress: {
      type: 'string',
      minLength: 5,
      maxLength: 500,
      title: 'Service Address',
    },
    propertyType: {
      type: 'string',
      enum: ['residential', 'commercial', 'industrial'],
      title: 'Property Type',
    },

    // Issue description
    issueType: {
      type: 'string',
      enum: [
        'leak_detection',
        'pipe_repair',
        'drain_cleaning',
        'fixture_replacement',
        'water_heater',
        'faucet_repair',
        'toilet_repair',
        'shower_repair',
        'emergency_water_shut',
        'other',
      ],
      title: 'Issue Type',
    },
    issueDescription: {
      type: 'string',
      minLength: 10,
      maxLength: 1000,
      title: 'Detailed Problem Description',
    },

    // Affected areas
    affectedAreas: {
      type: 'array',
      title: 'Affected Areas',
      items: {
        type: 'string',
        enum: ['kitchen', 'bathroom', 'laundry', 'basement', 'outdoor', 'other'],
      },
    },

    // Severity assessment
    severity: {
      type: 'string',
      enum: ['low', 'medium', 'high', 'emergency'],
      title: 'Issue Severity',
    },

    // Inspection findings
    inspectionFindings: {
      type: 'array',
      title: 'Inspection Findings',
      items: {
        type: 'object',
        properties: {
          finding: {
            type: 'string',
            enum: [
              'corroded_pipes',
              'mineral_buildup',
              'tree_root_intrusion',
              'leaking_joints',
              'cracked_pipes',
              'low_pressure',
              'water_discoloration',
              'no_issues_found',
              'other',
            ],
            title: 'Finding Type',
          },
          location: {
            type: 'string',
            maxLength: 200,
            title: 'Location in Property',
          },
          notes: {
            type: 'string',
            maxLength: 500,
            title: 'Notes',
          },
        },
        required: ['finding'],
      },
    },

    // Work performed
    workPerformed: {
      type: 'array',
      title: 'Work Performed',
      items: {
        type: 'object',
        properties: {
          task: {
            type: 'string',
            enum: [
              'pipe_repair',
              'pipe_replacement',
              'drain_clearing',
              'fixture_replacement',
              'joint_resealing',
              'pressure_relief',
              'water_shut_valve',
              'flushing',
              'other',
            ],
            title: 'Task Completed',
          },
          completed: {
            type: 'boolean',
            title: 'Completed',
          },
          notes: {
            type: 'string',
            maxLength: 500,
            title: 'Details',
          },
        },
        required: ['task', 'completed'],
      },
    },

    // Materials used
    materialsUsed: {
      type: 'array',
      title: 'Materials Used',
      items: {
        type: 'object',
        properties: {
          material: {
            type: 'string',
            title: 'Material Name',
          },
          quantity: {
            type: 'string',
            title: 'Quantity (e.g., 2 meters, 1 unit)',
          },
          cost: {
            type: 'number',
            minimum: 0,
            title: 'Cost (SGD)',
          },
        },
        required: ['material', 'quantity'],
      },
    },

    // Labor and cost
    laborHours: {
      type: 'number',
      minimum: 0,
      maximum: 48,
      title: 'Labor Hours',
    },
    laborCost: {
      type: 'number',
      minimum: 0,
      title: 'Labor Cost (SGD)',
    },

    // Testing and verification
    pressureTest: {
      type: 'boolean',
      title: 'Pressure Test Performed',
    },
    pressureTestResult: {
      type: 'string',
      enum: ['passed', 'failed', 'not_applicable'],
      title: 'Pressure Test Result',
    },
    leakTest: {
      type: 'boolean',
      title: 'Leak Test Performed',
    },
    leakTestResult: {
      type: 'string',
      enum: ['no_leaks', 'leaks_found', 'not_applicable'],
      title: 'Leak Test Result',
    },

    // Recommendations
    recommendations: {
      type: 'string',
      maxLength: 1000,
      title: 'Recommendations for Future Maintenance',
    },

    // Warranty
    warrantyOffered: {
      type: 'boolean',
      title: 'Warranty Offered',
    },
    warrantyDuration: {
      type: 'string',
      enum: ['3_months', '6_months', '1_year', 'not_applicable'],
      title: 'Warranty Duration',
    },

    // Photos (will be stored as attachment IDs)
    photosRequired: {
      type: 'boolean',
      title: 'Before/After Photos Attached',
      default: false,
    },

    // Follow-up
    followUpRequired: {
      type: 'boolean',
      title: 'Follow-up Visit Needed',
    },
    followUpDate: {
      type: 'string',
      format: 'date',
      title: 'Suggested Follow-up Date',
    },

    // Plumber notes
    plumberNotes: {
      type: 'string',
      maxLength: 2000,
      title: 'Plumber Notes',
    },
  },

  required: [
    'customerName',
    'customerEmail',
    'customerPhone',
    'serviceAddress',
    'propertyType',
    'issueType',
    'issueDescription',
    'affectedAreas',
    'severity',
    'inspectionFindings',
    'workPerformed',
  ],
};

// Workflow states
const PLUMBING_WORKFLOW = [
  {
    state: 'draft',
    label: 'Draft',
    allowedTransitions: ['assigned'],
    requiresApproval: false,
  },
  {
    state: 'assigned',
    label: 'Assigned to Plumber',
    allowedTransitions: ['in_progress', 'cancelled'],
    requiresApproval: false,
  },
  {
    state: 'in_progress',
    label: 'Service in Progress',
    allowedTransitions: ['completed', 'cancelled'],
    requiresApproval: false,
  },
  {
    state: 'completed',
    label: 'Service Completed',
    allowedTransitions: ['closed'],
    requiresApproval: true,
  },
  {
    state: 'closed',
    label: 'Closed',
    allowedTransitions: [],
    requiresApproval: false,
  },
  {
    state: 'cancelled',
    label: 'Cancelled',
    allowedTransitions: [],
    requiresApproval: false,
  },
];

async function seedTemplate() {
  try {
    // Connect to MongoDB
    console.log('📌 Connecting to MongoDB...');
    await mongoose.connect(MONGO_URI, {
      useNewUrlParser: true,
      useUnifiedTopology: true,
    });
    console.log('✓ Connected');

    // Check if template already exists
    const existing = await TicketTemplate.findOne({
      serviceType: 'plumbing',
    });

    if (existing) {
      console.log('📝 Template already exists. Updating...');
      existing.jsonSchema = PLUMBING_JSON_SCHEMA;
      existing.workflow = PLUMBING_WORKFLOW;
      existing.version += 1;
      existing.updatedBy = existing.createdBy; // Keep original creator
      await existing.save();
      console.log('✓ Template updated (version ' + existing.version + ')');
      console.log('📋 Template ID: ' + existing._id);
    } else {
      // Create new template
      const template = new TicketTemplate({
        name: 'Plumbing Service',
        description:
          'Professional plumbing repair, maintenance, and inspection services',
        serviceType: 'plumbing',
        jsonSchema: PLUMBING_JSON_SCHEMA,
        workflow: PLUMBING_WORKFLOW,
        slaSeconds: 86400, // 24 hours
        escalationTemplate: 'plumbing_overdue',
        visibility: 'internal',
        version: 1,
        createdBy: new mongoose.Types.ObjectId('000000000000000000000000'), // System user
      });

      await template.save();
      console.log('✓ Template created!');
      console.log('📋 Template ID: ' + template._id);
      console.log('\n📋 Template Details:');
      console.log('   Name: ' + template.name);
      console.log('   Type: ' + template.serviceType);
      console.log('   SLA: 24 hours');
      console.log('   Fields: ' + Object.keys(template.jsonSchema.properties).length);
    }

    console.log('\n✅ Seed complete!');
    process.exit(0);
  } catch (error) {
    console.error('❌ Seed error:', error);
    process.exit(1);
  }
}

seedTemplate();
