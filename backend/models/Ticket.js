const mongoose = require('mongoose');

/**
 * Ticket
 * 
 * Individual service requests created from a TicketTemplate.
 * Contains all field values + metadata.
 */
const ticketSchema = new mongoose.Schema(
  {
    // Unique identifier
    ticketNumber: {
      type: String,
      unique: true,
      index: true,
      example: 'AC-0001',
      description: 'Human-readable ticket number (e.g., AC-0001 for Aircon)',
    },

    // Template reference
    templateId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'TicketTemplate',
      required: true,
      index: true,
    },
    templateVersion: {
      type: Number,
      required: true,
      description: 'Version of template used at creation time',
    },

    // Form data (JSON)
    // Structure matches the template's JSON schema
    // Example: { name: "John", email: "john@example.com", serviceAddress: "...", checklist: [...] }
    data: {
      type: mongoose.Schema.Types.Mixed,
      required: true,
      description: 'Form submission data matching template schema',
    },

    // Requester info
    requestedBy: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
    },
    requesterName: String,
    requesterEmail: String,
    requesterPhone: String,

    // Assignment
    assignedTo: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      description: 'Field worker assigned to this ticket',
    },
    assignedAt: Date,

    // Location / Geofence
    geofence: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Geofence',
    },
    gpsLocation: {
      type: {
        type: String,
        enum: ['Point'],
        default: 'Point',
      },
      coordinates: {
        type: [Number], // [longitude, latitude]
        index: '2dsphere',
      },
    },

    // Attachments (references to Attachment collection)
    attachmentIds: [
      {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'Attachment',
      },
    ],

    // Workflow state
    status: {
      type: String,
      enum: ['draft', 'assigned', 'in_progress', 'completed', 'closed', 'cancelled'],
      default: 'draft',
      index: true,
    },

    // SLA tracking
    slaCalculatedAt: Date,
    slaDueAt: Date,
    slaBreachedAt: Date,
    isEscalated: {
      type: Boolean,
      default: false,
      index: true,
    },

    // Status history (audit trail)
    statusHistory: [
      {
        status: String,
        changedAt: Date,
        changedBy: mongoose.Schema.Types.ObjectId,
        reason: String,
      },
    ],

    // Completion details
    completedAt: Date,
    completedBy: mongoose.Schema.Types.ObjectId,
    completionNotes: String,

    // Feedback/Rating
    rating: {
      type: Number,
      min: 1,
      max: 5,
      description: 'Customer satisfaction rating',
    },
    feedback: String,

    // Soft delete
    isCancelled: {
      type: Boolean,
      default: false,
      index: true,
    },
    cancelledAt: Date,
    cancelledBy: mongoose.Schema.Types.ObjectId,
    cancellationReason: String,
  },
  { timestamps: true }
);

// Indexes for common queries
ticketSchema.index({ ticketNumber: 1 });
ticketSchema.index({ templateId: 1, status: 1 });
ticketSchema.index({ requestedBy: 1, createdAt: -1 });
ticketSchema.index({ assignedTo: 1, status: 1 });
ticketSchema.index({ slaDueAt: 1, isEscalated: 1 });
ticketSchema.index({ 'gpsLocation': '2dsphere' });

module.exports = mongoose.model('Ticket', ticketSchema);
