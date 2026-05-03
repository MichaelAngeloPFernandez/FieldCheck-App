const mongoose = require('mongoose');

/**
 * AuditLog — immutable record of who changed what and when.
 * Entries are never updated or deleted.
 */
const auditLogSchema = new mongoose.Schema(
  {
    resource_type: {
      type: String,
      required: true,
      enum: ['ticket', 'template', 'company', 'user', 'attendance'],
    },
    resource_id: { type: String, required: true },
    action: {
      type: String,
      required: true,
      // e.g. 'created', 'status_changed', 'data_updated', 'attachment_added',
      //      'assigned', 'sla_breached', 'geofence_rejected'
    },
    actor_id: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      default: null, // null = system action (e.g. SLA cron)
    },
    company: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Company',
      default: null,
    },
    details: { type: mongoose.Schema.Types.Mixed, default: {} },
  },
  {
    timestamps: { createdAt: 'created_at', updatedAt: false },
  }
);

auditLogSchema.index({ resource_type: 1, resource_id: 1, created_at: -1 });
auditLogSchema.index({ company: 1, created_at: -1 });

module.exports = mongoose.model('AuditLog', auditLogSchema);
