/**
 * Audit Service — centralized helper for creating immutable audit log entries.
 * Every significant action (ticket creation, status change, geofence rejection, etc.)
 * should be logged through this service.
 */
const AuditLog = require('../models/AuditLog');

/**
 * Log an action to the audit trail.
 *
 * @param {Object} opts
 * @param {string} opts.resource_type - 'ticket', 'template', 'company', 'user', 'attendance'
 * @param {string} opts.resource_id   - ID of the resource being acted on
 * @param {string} opts.action        - e.g. 'created', 'status_changed', 'assigned'
 * @param {string|null} opts.actor_id - User ID of who performed the action (null = system)
 * @param {string|null} opts.company  - Company ID for scoping
 * @param {Object} opts.details       - Additional context (old/new values, etc.)
 */
const log = async ({ resource_type, resource_id, action, actor_id = null, company = null, details = {} }) => {
  try {
    await AuditLog.create({
      resource_type,
      resource_id: String(resource_id),
      action,
      actor_id: actor_id || null,
      company: company || null,
      details,
    });
  } catch (err) {
    // Audit logging should never crash the request — log and move on.
    console.error('AuditService: Failed to write audit log:', err.message || err);
  }
};

/**
 * Get the audit trail for a specific resource.
 */
const getTrail = async (resource_type, resource_id, { limit = 50, skip = 0 } = {}) => {
  return AuditLog.find({ resource_type, resource_id: String(resource_id) })
    .sort({ created_at: -1 })
    .skip(skip)
    .limit(limit)
    .populate('actor_id', 'name email employeeId role')
    .lean();
};

module.exports = { log, getTrail };
