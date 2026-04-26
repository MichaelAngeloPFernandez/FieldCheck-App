/**
 * TicketService
 * 
 * Business logic for ticket creation, state transitions, and SLA tracking.
 */

const Ticket = require('../models/Ticket');
const Counter = require('../models/Counter');
const TicketTemplate = require('../models/TicketTemplate');
const ValidationService = require('./ValidationService');

class TicketService {
  /**
   * Generate next ticket number atomically
   * 
   * @param {string} templateId - MongoDB ObjectId of template
   * @returns {Promise<string>} - Ticket number like "AC-0001"
   */
  static async generateTicketNumber(templateId) {
    try {
      const template = await TicketTemplate.findById(templateId);
      if (!template) {
        throw new Error('Template not found');
      }

      // Get counter ID from service type (e.g., 'aircon_cleaning' -> 'ac')
      const counterId = this._getCounterId(template.serviceType);
      const prefix = this._getPrefix(template.serviceType);
      const digits = 4; // AC-0001, AC-0002, etc.

      // Atomic increment
      const counter = await Counter.findByIdAndUpdate(
        counterId,
        { $inc: { seq: 1 } },
        { new: true, upsert: true }
      );

      // Format: "AC-0001"
      const ticketNumber = `${prefix}-${counter.seq.toString().padStart(digits, '0')}`;
      return ticketNumber;
    } catch (error) {
      throw new Error(`Failed to generate ticket number: ${error.message}`);
    }
  }

  /**
   * Create new ticket with validation
   * 
   * @param {Object} options
   * @param {string} options.templateId
   * @param {Object} options.data
   * @param {string} options.requestedBy - User ID
   * @param {string} options.requesterName
   * @param {string} options.requesterEmail
   * @param {string} options.requesterPhone
   * @param {Object} options.gpsLocation - { coordinates: [long, lat] }
   * @param {Array} options.attachmentIds
   * 
   * @returns {Promise<Object>} - Created ticket
   */
  static async createTicket({
    templateId,
    data,
    requestedBy,
    requesterName,
    requesterEmail,
    requesterPhone,
    gpsLocation,
    attachmentIds,
  }) {
    try {
      // 1. Get template
      const template = await TicketTemplate.findById(templateId);
      if (!template) {
        throw new Error('Template not found');
      }

      if (!template.isActive) {
        throw new Error('Template is archived');
      }

      // 2. Validate data against schema
      const validation = ValidationService.validate(template.jsonSchema, data);
      if (!validation.valid) {
        const error = new Error('Validation failed');
        error.validationErrors = validation.errors;
        error.statusCode = 400;
        throw error;
      }

      // 3. Generate ticket number
      const ticketNumber = await this.generateTicketNumber(templateId);

      // 4. Calculate SLA
      const now = new Date();
      const slaDueAt = new Date(now.getTime() + template.slaSeconds * 1000);

      // 5. Create ticket
      const ticket = new Ticket({
        ticketNumber,
        templateId,
        templateVersion: template.version,
        data,
        requestedBy,
        requesterName,
        requesterEmail,
        requesterPhone,
        gpsLocation,
        attachmentIds: attachmentIds || [],
        status: 'draft',
        slaCalculatedAt: now,
        slaDueAt,
        statusHistory: [
          {
            status: 'draft',
            changedAt: now,
            changedBy: requestedBy,
            reason: 'Initial creation',
          },
        ],
      });

      await ticket.save();
      return ticket;
    } catch (error) {
      throw error;
    }
  }

  /**
   * Transition ticket to new status with validation
   */
  static async updateStatus(ticketId, newStatus, changedBy, reason) {
    try {
      const ticket = await Ticket.findById(ticketId);
      if (!ticket) {
        throw new Error('Ticket not found');
      }

      // Get template for workflow rules
      const template = await TicketTemplate.findById(ticket.templateId);
      if (!template) {
        throw new Error('Template not found');
      }

      // Check if transition is allowed
      const currentWorkflowState = template.workflow.find(
        (w) => w.state === ticket.status
      );
      if (
        !currentWorkflowState ||
        !currentWorkflowState.allowedTransitions.includes(newStatus)
      ) {
        throw new Error(
          `Cannot transition from ${ticket.status} to ${newStatus}`
        );
      }

      // Update status
      ticket.status = newStatus;
      ticket.statusHistory.push({
        status: newStatus,
        changedAt: new Date(),
        changedBy,
        reason,
      });

      // Set completion details
      if (newStatus === 'completed') {
        ticket.completedAt = new Date();
        ticket.completedBy = changedBy;
      }

      await ticket.save();
      return ticket;
    } catch (error) {
      throw error;
    }
  }

  /**
   * Check and escalate overdue tickets
   */
  static async escalateOverdueTickets() {
    try {
      const now = new Date();
      const tickets = await Ticket.find({
        status: { $in: ['assigned', 'in_progress'] },
        slaDueAt: { $lt: now },
        isEscalated: false,
      });

      const updates = tickets.map((ticket) => {
        ticket.isEscalated = true;
        ticket.slaBreachedAt = now;
        return ticket.save();
      });

      await Promise.all(updates);
      return { escalated: tickets.length };
    } catch (error) {
      console.error('Escalation error:', error);
      throw error;
    }
  }

  /**
   * Get counter ID from service type
   * @private
   */
  static _getCounterId(serviceType) {
    const map = {
      aircon_cleaning: 'ac',
      plumbing: 'pl',
      electrical: 'el',
      hvac_maintenance: 'hv',
      general_repair: 'gr',
    };
    return map[serviceType] || serviceType.substring(0, 2).toLowerCase();
  }

  /**
   * Get prefix from service type
   * @private
   */
  static _getPrefix(serviceType) {
    const map = {
      aircon_cleaning: 'AC',
      plumbing: 'PL',
      electrical: 'EL',
      hvac_maintenance: 'HV',
      general_repair: 'GR',
    };
    return map[serviceType] || serviceType.substring(0, 2).toUpperCase();
  }
}

module.exports = TicketService;
