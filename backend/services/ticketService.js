/**
 * TicketService
 *
 * Business logic for ticket creation, state transitions, and SLA tracking.
 * All field names align with the live Mongoose schemas (Ticket, TicketTemplate, Counter).
 */

const Ticket = require('../models/Ticket');
const Counter = require('../models/Counter');
const TicketTemplate = require('../models/TicketTemplate');
const validationService = require('./validationService');

class TicketService {
  /**
   * Generate next ticket number atomically using the company-scoped Counter.
   *
   * @param {string} companyId   - MongoDB ObjectId of the company
   * @param {string} companyCode - Human-readable company code (e.g. "ACME")
   * @returns {Promise<string>}  - Ticket number like "ACME-0001"
   */
  static async generateTicketNumber(companyId, companyCode) {
    const seq = await Counter.getNextSequence(companyId);
    const prefix = (companyCode || 'TKT').toUpperCase();
    return `${prefix}-${String(seq).padStart(4, '0')}`;
  }

  /**
   * Validate ticket data against a template's json_schema.
   *
   * @param {Object} template - TicketTemplate document (must have json_schema)
   * @param {Object} data     - Form payload to validate
   * @returns {{ valid: boolean, errors: Array }}
   */
  static validateData(template, data) {
    return validationService.validate(template.json_schema, data);
  }

  /**
   * Finalize sla_status when a ticket transitions to 'closed' or 'verified'.
   *
   * Rules:
   *  - If sla_deadline is null → sla_status stays null (no SLA configured)
   *  - If completedAt ≤ sla_deadline → sla_status = 'on_time'
   *  - If completedAt > sla_deadline → sla_status stays 'overdue'
   *
   * @param {Object} ticket - Mongoose Ticket document (mutated in place, not saved)
   * @returns {Object} The mutated ticket document
   */
  static finalizeSlaStatus(ticket) {
    if (!ticket.sla_deadline) {
      // No SLA configured — leave sla_status as-is (null)
      return ticket;
    }

    const completedAt = ticket.completedAt || new Date();
    if (completedAt <= ticket.sla_deadline) {
      ticket.sla_status = 'on_time';
    }
    // else: keep existing sla_status (typically 'overdue')

    return ticket;
  }

  /**
   * Compute the SLA deadline from a template's sla_seconds.
   *
   * @param {Object} template  - TicketTemplate document
   * @param {Date}   createdAt - Ticket creation timestamp (defaults to now)
   * @returns {{ sla_deadline: Date|null, sla_status: string|null }}
   */
  static computeSla(template, createdAt = new Date()) {
    if (template.sla_seconds && template.sla_seconds > 0) {
      return {
        sla_deadline: new Date(createdAt.getTime() + template.sla_seconds * 1000),
        sla_status: 'on_time',
      };
    }
    return { sla_deadline: null, sla_status: null };
  }

  /**
   * Check whether a workflow transition is permitted.
   *
   * @param {Object} template  - TicketTemplate document (must have workflow.transitions)
   * @param {string} fromStatus
   * @param {string} toStatus
   * @returns {{ allowed: boolean, allowedTransitions: string[] }}
   */
  static isTransitionAllowed(template, fromStatus, toStatus) {
    if (!template || !template.workflow || !template.workflow.transitions) {
      return { allowed: true, allowedTransitions: [] };
    }
    const allowed = template.workflow.transitions[fromStatus];
    if (!Array.isArray(allowed)) {
      return { allowed: true, allowedTransitions: [] };
    }
    return { allowed: allowed.includes(toStatus), allowedTransitions: allowed };
  }
}

module.exports = TicketService;
