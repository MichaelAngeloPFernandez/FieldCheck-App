/**
 * Ticket Routes
 * 
 * POST   /api/tickets - Create new ticket
 * GET    /api/tickets - List tickets
 * GET    /api/tickets/:id - Get ticket details
 * PATCH  /api/tickets/:id/status - Update status
 * 
 * POST   /api/templates - Create template (admin)
 * GET    /api/templates - List templates
 * GET    /api/templates/:id - Get template
 */

const express = require('express');
const router = express.Router();
const { protect } = require('../middleware/authMiddleware');
const Ticket = require('../models/Ticket');
const TicketTemplate = require('../models/TicketTemplate');
const TicketService = require('../services/TicketService');

// ==================
// TEMPLATE ROUTES
// ==================

/**
 * POST /api/templates
 * Create new template (admin only)
 */
router.post('/templates', protect, async (req, res) => {
  try {
    // Authorization: admin only
    if (req.user.role !== 'admin') {
      return res.status(403).json({ error: 'Admin access required' });
    }

    const {
      name,
      description,
      serviceType,
      jsonSchema,
      workflow,
      slaSeconds,
      escalationTemplate,
      visibility,
    } = req.body;

    // Validate required fields
    if (!name || !serviceType || !jsonSchema || !workflow || !slaSeconds) {
      return res.status(400).json({
        error: 'name, serviceType, jsonSchema, workflow, slaSeconds required',
      });
    }

    const template = new TicketTemplate({
      name,
      description,
      serviceType,
      jsonSchema,
      workflow,
      slaSeconds,
      escalationTemplate,
      visibility: visibility || 'internal',
      version: 1,
      createdBy: req.user._id,
    });

    await template.save();

    res.status(201).json({
      _id: template._id,
      name: template.name,
      serviceType: template.serviceType,
      version: template.version,
      message: 'Template created',
    });
  } catch (error) {
    console.error('Create template error:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * GET /api/templates
 * List all active templates
 */
router.get('/templates', protect, async (req, res) => {
  try {
    const { serviceType } = req.query;

    const filter = { isActive: true };
    if (serviceType) {
      filter.serviceType = serviceType;
    }

    const templates = await TicketTemplate.find(filter)
      .select('_id name description serviceType version slaSeconds')
      .lean();

    res.json({
      count: templates.length,
      templates,
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

/**
 * GET /api/templates/:id
 * Get template with full schema
 */
router.get('/templates/:id', protect, async (req, res) => {
  try {
    const template = await TicketTemplate.findById(req.params.id);

    if (!template || !template.isActive) {
      return res.status(404).json({ error: 'Template not found' });
    }

    res.json({
      _id: template._id,
      name: template.name,
      description: template.description,
      serviceType: template.serviceType,
      jsonSchema: template.jsonSchema,
      workflow: template.workflow,
      slaSeconds: template.slaSeconds,
      version: template.version,
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// ==================
// TICKET ROUTES
// ==================

/**
 * POST /api/tickets
 * Create new ticket
 */
router.post('/', protect, async (req, res) => {
  try {
    const {
      templateId,
      data,
      requesterName,
      requesterEmail,
      requesterPhone,
      gpsLocation,
      attachmentIds,
    } = req.body;

    if (!templateId || !data) {
      return res
        .status(400)
        .json({ error: 'templateId and data required' });
    }

    // Create ticket with validation
    const ticket = await TicketService.createTicket({
      templateId,
      data,
      requestedBy: req.user._id,
      requesterName: requesterName || req.user.name,
      requesterEmail: requesterEmail || req.user.email,
      requesterPhone,
      gpsLocation,
      attachmentIds,
    });

    res.status(201).json({
      _id: ticket._id,
      ticketNumber: ticket.ticketNumber,
      status: ticket.status,
      slaDueAt: ticket.slaDueAt,
      message: 'Ticket created successfully',
    });
  } catch (error) {
    console.error('Create ticket error:', error);

    // Return validation errors with 400 status
    if (error.statusCode === 400 && error.validationErrors) {
      return res.status(400).json({
        error: 'Validation failed',
        details: error.validationErrors,
      });
    }

    res.status(500).json({ error: error.message });
  }
});

/**
 * GET /api/tickets
 * List tickets with filtering
 */
router.get('/', protect, async (req, res) => {
  try {
    const {
      status,
      templateId,
      assignedTo,
      requestedBy,
      isEscalated,
      limit = 20,
      skip = 0,
    } = req.query;

    const filter = {};

    if (status) filter.status = status;
    if (templateId) filter.templateId = templateId;
    if (assignedTo) filter.assignedTo = assignedTo;
    if (requestedBy) filter.requestedBy = requestedBy;
    if (isEscalated === 'true') filter.isEscalated = true;
    if (isEscalated === 'false') filter.isEscalated = false;

    // Role-based scoping
    if (req.user.role !== 'admin') {
      // Employees can only see their own tickets
      filter.$or = [{ requestedBy: req.user._id }, { assignedTo: req.user._id }];
    }

    const tickets = await Ticket.find(filter)
      .select(
        '_id ticketNumber status slaDueAt isEscalated requestedBy assignedTo createdAt'
      )
      .populate('templateId', 'name serviceType')
      .populate('requestedBy', 'name email')
      .populate('assignedTo', 'name email')
      .limit(parseInt(limit))
      .skip(parseInt(skip))
      .sort({ createdAt: -1 });

    const total = await Ticket.countDocuments(filter);

    res.json({
      count: tickets.length,
      total,
      tickets,
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

/**
 * GET /api/tickets/:id
 * Get ticket details
 */
router.get('/:id', protect, async (req, res) => {
  try {
    const ticket = await Ticket.findById(req.params.id)
      .populate('templateId', 'name serviceType jsonSchema workflow')
      .populate('requestedBy', 'name email')
      .populate('assignedTo', 'name email')
      .populate('attachmentIds');

    if (!ticket) {
      return res.status(404).json({ error: 'Ticket not found' });
    }

    // Authorization: can view if admin, requester, or assignee
    const canView =
      req.user.role === 'admin' ||
      ticket.requestedBy._id.equals(req.user._id) ||
      (ticket.assignedTo && ticket.assignedTo._id.equals(req.user._id));

    if (!canView) {
      return res.status(403).json({ error: 'Not authorized' });
    }

    res.json(ticket);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

/**
 * PATCH /api/tickets/:id/status
 * Update ticket status
 */
router.patch('/:id/status', protect, async (req, res) => {
  try {
    const { status, reason } = req.body;

    if (!status) {
      return res.status(400).json({ error: 'status required' });
    }

    const ticket = await Ticket.findById(req.params.id);
    if (!ticket) {
      return res.status(404).json({ error: 'Ticket not found' });
    }

    // Authorization: admin or assignee
    const canUpdate =
      req.user.role === 'admin' ||
      (ticket.assignedTo && ticket.assignedTo.equals(req.user._id));

    if (!canUpdate) {
      return res.status(403).json({ error: 'Not authorized' });
    }

    // Update status
    const updated = await TicketService.updateStatus(
      req.params.id,
      status,
      req.user._id,
      reason || 'Status updated'
    );

    res.json({
      _id: updated._id,
      ticketNumber: updated.ticketNumber,
      status: updated.status,
      statusHistory: updated.statusHistory,
    });
  } catch (error) {
    console.error('Update status error:', error);
    res.status(500).json({ error: error.message });
  }
});

module.exports = router;
