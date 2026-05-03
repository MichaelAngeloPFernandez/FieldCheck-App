const mongoose = require('mongoose');

/**
 * Ticket — a single unit of field work created from a TicketTemplate.
 * The `data` field holds the worker's form submission and is validated
 * against the template's json_schema on create/update.
 */
const ticketSchema = new mongoose.Schema(
  {
    // Human-readable ticket number, e.g. "AC-0001".
    ticket_no: { type: String, required: true, unique: true },
    company: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Company',
      required: true,
      index: true,
    },
    template: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'TicketTemplate',
      required: true,
    },
    // Snapshot of the template version at creation time.
    template_version: { type: Number, default: 1 },
    // The actual form data — validated by AJV against template.json_schema.
    data: { type: mongoose.Schema.Types.Mixed, default: {} },
    status: {
      type: String,
      default: 'open',
    },
    assignee: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      default: null,
    },
    created_by: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      default: null,
    },
    // GridFS attachment references (array of relative URL paths).
    attachments: [{ type: String }],
    // SLA deadline computed from template.sla_seconds at creation.
    sla_deadline: { type: Date, default: null },
    sla_status: {
      type: String,
      enum: ['on_time', 'at_risk', 'overdue'],
      default: null,
    },
    // GPS captured at submission.
    gps: {
      lat: { type: Number },
      lng: { type: Number },
    },
    // Geofence the ticket was created within (optional enforcement).
    geofence: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Geofence',
      default: null,
    },
    notes: { type: String, default: '' },
    isArchived: { type: Boolean, default: false },
    completedAt: { type: Date, default: null },
  },
  { timestamps: true }
);

ticketSchema.index({ company: 1, status: 1 });
ticketSchema.index({ assignee: 1, status: 1 });
// List query: filter by company + archive flag, sorted by creation date
ticketSchema.index({ company: 1, isArchived: 1, createdAt: -1 });
// SLA job: find tickets approaching/past deadline by status
ticketSchema.index({ sla_deadline: 1, status: 1 });

module.exports = mongoose.model('Ticket', ticketSchema);
