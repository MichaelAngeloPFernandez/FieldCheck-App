const mongoose = require('mongoose');

/**
 * TicketTemplate
 * 
 * Defines custom form schemas for tickets (Aircon Cleaning, Plumbing, etc.)
 * Each template includes:
 * - JSON Schema for form validation
 * - Workflow state machine
 * - SLA (Service Level Agreement)
 * - Custom fields per service type
 */
const ticketTemplateSchema = new mongoose.Schema(
  {
    // Basic info
    name: {
      type: String,
      required: true,
      trim: true,
      example: 'Aircon Cleaning Service',
    },
    description: {
      type: String,
      trim: true,
    },

    // Service type identifier
    serviceType: {
      type: String,
      required: true,
      enum: [
        'aircon_cleaning',
        'plumbing',
        'electrical',
        'hvac_maintenance',
        'general_repair',
      ],
      index: true,
    },

    // JSON Schema v7 for dynamic form validation
    // Defines fields like: name, email, serviceAddress, checklist items, etc.
    jsonSchema: {
      type: mongoose.Schema.Types.Mixed,
      required: true,
      description: 'JSON Schema defining form fields and validation rules',
    },

    // Workflow state transitions
    // Example: draft -> assigned -> in_progress -> completed -> closed
    workflow: {
      type: [
        {
          state: String,
          label: String,
          allowedTransitions: [String],
          requiresApproval: Boolean,
        },
      ],
      required: true,
    },

    // Service Level Agreement
    slaSeconds: {
      type: Number,
      required: true,
      description: 'Time (in seconds) before ticket escalates',
      example: 86400, // 24 hours
    },
    escalationTemplate: {
      type: String,
      description: 'Email template for escalation',
    },

    // Who can create tickets with this template
    visibility: {
      type: String,
      enum: ['public', 'internal', 'admins_only'],
      default: 'internal',
    },

    // Schema versioning for backward compatibility
    version: {
      type: Number,
      default: 1,
    },

    // Audit
    createdBy: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
    },
    updatedBy: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
    },

    // Soft delete
    isActive: {
      type: Boolean,
      default: true,
      index: true,
    },
    archivedAt: Date,
    archivedBy: mongoose.Schema.Types.ObjectId,
  },
  { timestamps: true }
);

// Indexes
ticketTemplateSchema.index({ serviceType: 1, isActive: 1 });
ticketTemplateSchema.index({ createdBy: 1 });

module.exports = mongoose.model('TicketTemplate', ticketTemplateSchema);
