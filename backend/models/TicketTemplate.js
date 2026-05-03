const mongoose = require('mongoose');

/**
 * TicketTemplate — defines the form schema, workflow, and SLA for a type of
 * ticket within a company.  Admins create templates; field workers select a
 * template from a dropdown when creating a ticket.
 *
 * `json_schema` stores a JSON-Schema-draft-07-compatible object that is
 * validated server-side with AJV and rendered client-side into a dynamic form.
 */
const ticketTemplateSchema = new mongoose.Schema(
  {
    company: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Company',
      required: true,
      index: true,
    },
    name: { type: String, required: true, trim: true },
    description: { type: String, default: '', trim: true },
    // The JSON Schema that describes the ticket data payload.
    json_schema: { type: mongoose.Schema.Types.Mixed, required: true },
    // Ordered list of valid statuses and allowed transitions.
    workflow: {
      statuses: {
        type: [String],
        default: ['open', 'in_progress', 'completed', 'verified', 'closed'],
      },
      transitions: {
        // Map of "fromStatus" -> [array of allowed "toStatus"]
        type: mongoose.Schema.Types.Mixed,
        default: {
          open: ['in_progress', 'closed'],
          in_progress: ['completed', 'blocked', 'closed'],
          blocked: ['in_progress', 'closed'],
          completed: ['verified', 'in_progress'],
          verified: ['closed'],
          closed: [],
        },
      },
    },
    // SLA in seconds from ticket creation to expected completion.
    sla_seconds: { type: Number, default: null },
    // Who can see this template: 'company' = same company only, 'public' = any.
    visibility: {
      type: String,
      enum: ['company', 'public'],
      default: 'company',
    },
    // Monotonic version so ticket records remember which schema revision they used.
    version: { type: Number, default: 1, min: 1 },
    isActive: { type: Boolean, default: true },
    created_by: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
    },
  },
  { timestamps: true }
);

ticketTemplateSchema.index({ company: 1, isActive: 1 });

module.exports = mongoose.model('TicketTemplate', ticketTemplateSchema);
