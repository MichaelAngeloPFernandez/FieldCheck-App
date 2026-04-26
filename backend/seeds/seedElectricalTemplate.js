/**
 * Seed Script: Electrical Service Template
 * 
 * Run with: node backend/seeds/seedElectricalTemplate.js
 * 
 * Creates a complete template for Electrical service with:
 * - JSON Schema for form validation
 * - Workflow state machine
 * - SLA (24 hours)
 */

require('dotenv').config();
const mongoose = require('mongoose');
const TicketTemplate = require('../models/TicketTemplate');

const MONGO_URI = process.env.MONGODB_URI || process.env.MONGO_URI;

// JSON Schema for Electrical Service
const ELECTRICAL_JSON_SCHEMA = {
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

    // Electrical system info
    voltage: {
      type: 'string',
      enum: ['110V', '220V', '380V', 'three_phase', 'other'],
      title: 'Main Voltage',
    },
    panelType: {
      type: 'string',
      enum: ['fuse_box', 'breaker_box', 'smart_panel', 'other'],
      title: 'Main Panel Type',
    },
    panelAmps: {
      type: 'string',
      enum: ['60', '100', '150', '200', '300', '400', 'other'],
      title: 'Panel Amperage',
    },

    // Issue description
    issueType: {
      type: 'string',
      enum: [
        'power_outage',
        'flickering_lights',
        'dead_outlet',
        'tripped_breaker',
        'burning_smell',
        'wire_installation',
        'rewiring',
        'panel_upgrade',
        'circuit_installation',
        'light_fixture',
        'switch_replacement',
        'safety_inspection',
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

    // Affected circuits
    affectedCircuits: {
      type: 'array',
      title: 'Affected Circuits/Areas',
      items: {
        type: 'string',
        enum: [
          'kitchen',
          'bathroom',
          'bedroom',
          'living_room',
          'garage',
          'outdoor',
          'entire_house',
          'other',
        ],
      },
    },

    // Safety concerns
    safetyIssues: {
      type: 'array',
      title: 'Safety Concerns Noted',
      items: {
        type: 'string',
        enum: [
          'overloaded_circuits',
          'exposed_wiring',
          'improper_grounding',
          'outdated_wiring',
          'fire_hazard',
          'damaged_outlet',
          'damaged_switch',
          'none',
          'other',
        ],
      },
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
              'faulty_breaker',
              'burned_outlet',
              'loose_connection',
              'bad_wire',
              'blown_fuse',
              'short_circuit',
              'ground_fault',
              'voltage_imbalance',
              'no_issues_found',
              'other',
            ],
            title: 'Finding Type',
          },
          location: {
            type: 'string',
            maxLength: 200,
            title: 'Location',
          },
          severity: {
            type: 'string',
            enum: ['low', 'medium', 'high', 'critical'],
            title: 'Severity',
          },
          notes: {
            type: 'string',
            maxLength: 500,
            title: 'Details',
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
              'outlet_replacement',
              'switch_replacement',
              'breaker_replacement',
              'wire_repair',
              'wire_replacement',
              'circuit_installation',
              'grounding_repair',
              'light_fixture_installation',
              'panel_upgrade',
              'load_testing',
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

    // Parts/Materials
    partsReplaced: {
      type: 'array',
      title: 'Parts and Materials',
      items: {
        type: 'object',
        properties: {
          part: {
            type: 'string',
            title: 'Part Name',
          },
          quantity: {
            type: 'string',
            title: 'Quantity (e.g., 5 outlets, 10 meters wire)',
          },
          cost: {
            type: 'number',
            minimum: 0,
            title: 'Cost (SGD)',
          },
        },
        required: ['part', 'quantity'],
      },
    },

    // Testing and certification
    voltageTest: {
      type: 'boolean',
      title: 'Voltage Test Performed',
    },
    continuityTest: {
      type: 'boolean',
      title: 'Continuity Test Performed',
    },
    groundTest: {
      type: 'boolean',
      title: 'Ground Test Performed',
    },
    loadTest: {
      type: 'boolean',
      title: 'Load Test Performed',
    },

    allTestsPassed: {
      type: 'boolean',
      title: 'All Tests Passed',
    },

    // Certification
    certificationRequired: {
      type: 'boolean',
      title: 'Safety Certification Issued',
    },
    certificationNumber: {
      type: 'string',
      maxLength: 100,
      title: 'Certification Number',
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

    // Recommendations
    recommendations: {
      type: 'string',
      maxLength: 1000,
      title: 'Recommendations for Future Maintenance',
    },
    urgentRepairsNeeded: {
      type: 'boolean',
      title: 'Urgent Future Repairs Needed',
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
      title: 'Photos Attached',
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

    // Electrician notes
    electricianNotes: {
      type: 'string',
      maxLength: 2000,
      title: 'Electrician Notes',
    },
  },

  required: [
    'customerName',
    'customerEmail',
    'customerPhone',
    'serviceAddress',
    'propertyType',
    'voltage',
    'panelType',
    'issueType',
    'issueDescription',
    'affectedCircuits',
    'inspectionFindings',
    'workPerformed',
  ],
};

// Workflow states
const ELECTRICAL_WORKFLOW = [
  {
    state: 'draft',
    label: 'Draft',
    allowedTransitions: ['assigned'],
    requiresApproval: false,
  },
  {
    state: 'assigned',
    label: 'Assigned to Electrician',
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
    console.log('⚡ Connecting to MongoDB...');
    await mongoose.connect(MONGO_URI, {
      useNewUrlParser: true,
      useUnifiedTopology: true,
    });
    console.log('✓ Connected');

    // Check if template already exists
    const existing = await TicketTemplate.findOne({
      serviceType: 'electrical',
    });

    if (existing) {
      console.log('📝 Template already exists. Updating...');
      existing.jsonSchema = ELECTRICAL_JSON_SCHEMA;
      existing.workflow = ELECTRICAL_WORKFLOW;
      existing.version += 1;
      existing.updatedBy = existing.createdBy;
      await existing.save();
      console.log('✓ Template updated (version ' + existing.version + ')');
      console.log('📋 Template ID: ' + existing._id);
    } else {
      // Create new template
      const template = new TicketTemplate({
        name: 'Electrical Service',
        description:
          'Professional electrical repair, maintenance, and safety inspection services',
        serviceType: 'electrical',
        jsonSchema: ELECTRICAL_JSON_SCHEMA,
        workflow: ELECTRICAL_WORKFLOW,
        slaSeconds: 86400, // 24 hours
        escalationTemplate: 'electrical_overdue',
        visibility: 'internal',
        version: 1,
        createdBy: new mongoose.Types.ObjectId('000000000000000000000000'), // System user
      });

      await template.save();
      console.log('✓ Template created!');
      console.log('📋 Template ID: ' + template._id);
      console.log('\n⚡ Template Details:');
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
