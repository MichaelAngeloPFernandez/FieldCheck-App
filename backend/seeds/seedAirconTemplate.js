/**
 * Seed Script: Aircon Cleaning Template
 * 
 * Run with: node backend/seeds/seedAirconTemplate.js
 * 
 * Creates a complete template for Aircon Cleaning service with:
 * - JSON Schema for form validation
 * - Workflow state machine
 * - SLA (24 hours)
 */

require('dotenv').config();
const mongoose = require('mongoose');
const TicketTemplate = require('../models/TicketTemplate');

const MONGO_URI = process.env.MONGODB_URI || process.env.MONGO_URI;

// JSON Schema for Aircon Cleaning Service
const AIRCON_JSON_SCHEMA = {
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
    buildingType: {
      type: 'string',
      enum: ['residential', 'commercial', 'industrial'],
      title: 'Building Type',
    },

    // Aircon details
    unitCount: {
      type: 'integer',
      minimum: 1,
      maximum: 50,
      title: 'Number of AC Units',
    },
    unitBrand: {
      type: 'string',
      enum: [
        'daikin',
        'fujitsu',
        'lg',
        'panasonic',
        'midea',
        'gree',
        'other',
      ],
      title: 'Primary AC Brand',
    },

    // Service checklist
    serviceChecklist: {
      type: 'array',
      title: 'Service Tasks',
      items: {
        type: 'object',
        properties: {
          task: {
            type: 'string',
            enum: [
              'filter_replacement',
              'condenser_cleaning',
              'evaporator_cleaning',
              'drain_cleaning',
              'refrigerant_check',
              'electrical_inspection',
              'performance_test',
            ],
            title: 'Task',
          },
          completed: {
            type: 'boolean',
            title: 'Completed',
          },
          notes: {
            type: 'string',
            maxLength: 500,
            title: 'Notes',
          },
        },
        required: ['task', 'completed'],
      },
    },

    // Issues found
    issuesFound: {
      type: 'string',
      enum: ['none', 'minor', 'major'],
      title: 'Issues Identified',
    },
    issueDescription: {
      type: 'string',
      maxLength: 1000,
      title: 'Issue Details (if any)',
    },

    // Recommended parts
    partsReplaced: {
      type: 'array',
      title: 'Parts Replaced',
      items: {
        type: 'object',
        properties: {
          partName: {
            type: 'string',
            title: 'Part Name',
          },
          quantity: {
            type: 'integer',
            minimum: 1,
            title: 'Quantity',
          },
          cost: {
            type: 'number',
            minimum: 0,
            title: 'Cost (SGD)',
          },
        },
        required: ['partName', 'quantity'],
      },
    },

    // Labor and cost
    laborHours: {
      type: 'number',
      minimum: 0,
      maximum: 24,
      title: 'Labor Hours',
    },
    laborCost: {
      type: 'number',
      minimum: 0,
      title: 'Labor Cost (SGD)',
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

    // Technician notes
    techniciansNotes: {
      type: 'string',
      maxLength: 2000,
      title: 'Technician Notes',
    },
  },

  required: [
    'customerName',
    'customerEmail',
    'customerPhone',
    'serviceAddress',
    'buildingType',
    'unitCount',
    'unitBrand',
    'serviceChecklist',
    'issuesFound',
  ],
};

// Workflow states
const AIRCON_WORKFLOW = [
  {
    state: 'draft',
    label: 'Draft',
    allowedTransitions: ['assigned'],
    requiresApproval: false,
  },
  {
    state: 'assigned',
    label: 'Assigned to Technician',
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
    console.log('Connecting to MongoDB...');
    await mongoose.connect(MONGO_URI, {
      useNewUrlParser: true,
      useUnifiedTopology: true,
    });
    console.log('✓ Connected');

    // Check if template already exists
    const existing = await TicketTemplate.findOne({
      serviceType: 'aircon_cleaning',
    });

    if (existing) {
      console.log('Template already exists. Updating...');
      existing.jsonSchema = AIRCON_JSON_SCHEMA;
      existing.workflow = AIRCON_WORKFLOW;
      existing.version += 1;
      existing.updatedBy = existing.createdBy; // Keep original creator
      await existing.save();
      console.log('✓ Template updated (version ' + existing.version + ')');
    } else {
      // Create new template
      const template = new TicketTemplate({
        name: 'Aircon Cleaning Service',
        description:
          'Comprehensive air conditioning unit cleaning and maintenance service',
        serviceType: 'aircon_cleaning',
        jsonSchema: AIRCON_JSON_SCHEMA,
        workflow: AIRCON_WORKFLOW,
        slaSeconds: 86400, // 24 hours
        escalationTemplate: 'aircon_overdue',
        visibility: 'internal',
        version: 1,
        createdBy: new mongoose.Types.ObjectId('000000000000000000000000'), // System user
      });

      await template.save();
      console.log('✓ Template created: ' + template._id);
    }

    console.log('\n✓ Seed complete!');
    process.exit(0);
  } catch (error) {
    console.error('Seed error:', error);
    process.exit(1);
  }
}

seedTemplate();
