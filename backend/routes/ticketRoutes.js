/**
 * Ticket Routes — create, list, transition, and manage tickets.
 * Tickets are validated against their template's JSON Schema via AJV.
 */
const express = require('express');
const router = express.Router();
const mongoose = require('mongoose');
const multer = require('multer');
const Ajv = require('ajv');
const addFormats = require('ajv-formats');
const { protect, requireRole } = require('../middleware/authMiddleware');
const Ticket = require('../models/Ticket');
const TicketTemplate = require('../models/TicketTemplate');
const Company = require('../models/Company');
const Counter = require('../models/Counter');
const Geofence = require('../models/Geofence');
const auditService = require('../services/auditService');
const storageService = require('../services/storageService');

// AJV instance for server-side schema validation
const ajv = new Ajv({ allErrors: true, strict: false });
addFormats(ajv);

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 10 * 1024 * 1024 }, // 10 MB
});

// Haversine distance (meters)
const _haversineMeters = (lat1, lon1, lat2, lon2) => {
  const toRad = (deg) => (deg * Math.PI) / 180;
  const R = 6371000;
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
};

// ─── List tickets ────────────────────────────────────────────────────────────
// GET /api/tickets
// Admins see all tickets for their company; employees see only assigned.
router.get('/', protect, async (req, res) => {
  try {
    const userCompany = req.user.company
      ? String(req.user.company._id || req.user.company)
      : null;

    const filter = {};
    if (userCompany) filter.company = userCompany;
    if (req.user.role !== 'admin') {
      filter.assignee = req.user._id;
    }
    if (req.query.status) filter.status = req.query.status;
    if (req.query.template) filter.template = req.query.template;
    if (req.query.archived === 'true') {
      filter.isArchived = true;
    } else {
      filter.isArchived = { $ne: true };
    }

    const tickets = await Ticket.find(filter)
      .populate('template', 'name description')
      .populate('assignee', 'name email employeeId')
      .populate('created_by', 'name email')
      .populate('company', 'name code')
      .populate('geofence', 'name')
      .sort({ createdAt: -1 })
      .lean();

    res.json(tickets);
  } catch (err) {
    console.error('GET /api/tickets error:', err);
    res.status(500).json({ message: 'Failed to fetch tickets' });
  }
});

// ─── Get single ticket ───────────────────────────────────────────────────────
// GET /api/tickets/:id
router.get('/:id', protect, async (req, res) => {
  try {
    const ticket = await Ticket.findById(req.params.id)
      .populate('template', 'name description json_schema workflow sla_seconds')
      .populate('assignee', 'name email employeeId')
      .populate('created_by', 'name email')
      .populate('company', 'name code')
      .populate('geofence', 'name latitude longitude radius')
      .lean();

    if (!ticket) {
      return res.status(404).json({ message: 'Ticket not found' });
    }

    // Company scoping
    const userCompany = req.user.company
      ? String(req.user.company._id || req.user.company)
      : null;
    const ticketCompany = ticket.company
      ? String(ticket.company._id || ticket.company)
      : null;
    if (userCompany && ticketCompany && userCompany !== ticketCompany) {
      return res.status(403).json({ message: 'Access denied' });
    }

    res.json(ticket);
  } catch (err) {
    console.error('GET /api/tickets/:id error:', err);
    res.status(500).json({ message: 'Failed to fetch ticket' });
  }
});

// ─── Get audit trail for a ticket ────────────────────────────────────────────
// GET /api/tickets/:id/audit
router.get('/:id/audit', protect, async (req, res) => {
  try {
    const trail = await auditService.getTrail('ticket', req.params.id);
    res.json(trail);
  } catch (err) {
    console.error('GET /api/tickets/:id/audit error:', err);
    res.status(500).json({ message: 'Failed to fetch audit trail' });
  }
});

// ─── Create ticket ───────────────────────────────────────────────────────────
// POST /api/tickets
// Body: { template_id, data, assignee_id?, gps?, geofence_id?, notes? }
router.post('/', protect, async (req, res) => {
  try {
    const { template_id, data, assignee_id, gps, geofence_id, notes } = req.body;

    if (!template_id) {
      return res.status(400).json({ message: 'template_id is required' });
    }

    // Fetch template
    const template = await TicketTemplate.findById(template_id);
    if (!template || !template.isActive) {
      return res.status(404).json({ message: 'Template not found or inactive' });
    }

    // Resolve company from template
    const companyId = String(template.company);

    // Validate data against template JSON Schema
    const validate = ajv.compile(template.json_schema);
    const valid = validate(data || {});
    if (!valid) {
      return res.status(400).json({
        message: 'Ticket data validation failed',
        errors: validate.errors.map((e) => ({
          path: e.instancePath || e.dataPath || '',
          message: e.message,
          params: e.params,
        })),
      });
    }

    // Geofence enforcement
    if (geofence_id && gps && typeof gps.lat === 'number' && typeof gps.lng === 'number') {
      const geofence = await Geofence.findById(geofence_id);
      if (geofence && geofence.isActive) {
        const distance = _haversineMeters(
          geofence.latitude,
          geofence.longitude,
          gps.lat,
          gps.lng
        );
        if (distance > geofence.radius) {
          await auditService.log({
            resource_type: 'ticket',
            resource_id: 'rejected',
            action: 'geofence_rejected',
            actor_id: req.user._id,
            company: companyId,
            details: {
              geofence_id: geofence_id,
              geofence_name: geofence.name,
              distance_meters: Math.round(distance),
              radius_meters: geofence.radius,
              gps,
            },
          });
          return res.status(403).json({
            message: `Location is ${Math.round(distance)}m away from ${geofence.name} (max ${geofence.radius}m). Please move closer.`,
            distance: Math.round(distance),
            required_radius: geofence.radius,
          });
        }
      }
    }

    // Generate ticket number
    const company = await Company.findById(companyId).lean();
    const companyCode = company ? company.code : 'TKT';
    const seq = await Counter.getNextSequence(companyId);
    const ticket_no = `${companyCode}-${String(seq).padStart(4, '0')}`;

    // Compute SLA deadline
    let sla_deadline = null;
    let sla_status = null;
    if (template.sla_seconds && template.sla_seconds > 0) {
      sla_deadline = new Date(Date.now() + template.sla_seconds * 1000);
      sla_status = 'on_time';
    }

    const ticket = await Ticket.create({
      ticket_no,
      company: companyId,
      template: template._id,
      template_version: template.version || 1,
      data: data || {},
      status: 'open',
      assignee: assignee_id || null,
      created_by: req.user._id,
      sla_deadline,
      sla_status,
      gps: gps || {},
      geofence: geofence_id || null,
      notes: notes || '',
    });

    await auditService.log({
      resource_type: 'ticket',
      resource_id: ticket._id,
      action: 'created',
      actor_id: req.user._id,
      company: companyId,
      details: {
        ticket_no,
        template_name: template.name,
        assignee_id: assignee_id || null,
      },
    });

    // Real-time notification
    if (global.io) {
      global.io.emit('ticketCreated', {
        ticketId: String(ticket._id),
        ticket_no,
        templateName: template.name,
        status: 'open',
        assignee: assignee_id || null,
        company: companyId,
      });
    }

    const populated = await Ticket.findById(ticket._id)
      .populate('template', 'name description')
      .populate('assignee', 'name email employeeId')
      .populate('created_by', 'name email')
      .populate('company', 'name code')
      .lean();

    res.status(201).json(populated);
  } catch (err) {
    console.error('POST /api/tickets error:', err);
    res.status(500).json({ message: 'Failed to create ticket' });
  }
});

// ─── Update ticket data ──────────────────────────────────────────────────────
// PATCH /api/tickets/:id
router.patch('/:id', protect, async (req, res) => {
  try {
    const ticket = await Ticket.findById(req.params.id);
    if (!ticket) return res.status(404).json({ message: 'Ticket not found' });

    const { data, notes, assignee_id } = req.body;

    // If data is provided, re-validate against template
    if (data) {
      const template = await TicketTemplate.findById(ticket.template);
      if (template) {
        const validate = ajv.compile(template.json_schema);
        const valid = validate(data);
        if (!valid) {
          return res.status(400).json({
            message: 'Ticket data validation failed',
            errors: validate.errors,
          });
        }
      }
      ticket.data = data;
    }

    if (notes !== undefined) ticket.notes = notes;
    if (assignee_id !== undefined) ticket.assignee = assignee_id || null;

    await ticket.save();

    await auditService.log({
      resource_type: 'ticket',
      resource_id: ticket._id,
      action: 'data_updated',
      actor_id: req.user._id,
      company: ticket.company,
      details: {
        updatedFields: Object.keys(req.body),
      },
    });

    const populated = await Ticket.findById(ticket._id)
      .populate('template', 'name description')
      .populate('assignee', 'name email employeeId')
      .populate('created_by', 'name email')
      .populate('company', 'name code')
      .lean();

    res.json(populated);
  } catch (err) {
    console.error('PATCH /api/tickets/:id error:', err);
    res.status(500).json({ message: 'Failed to update ticket' });
  }
});

// ─── Change ticket status ────────────────────────────────────────────────────
// PATCH /api/tickets/:id/status
// Body: { status }
router.patch('/:id/status', protect, async (req, res) => {
  try {
    const ticket = await Ticket.findById(req.params.id);
    if (!ticket) return res.status(404).json({ message: 'Ticket not found' });

    const { status } = req.body;
    if (!status) return res.status(400).json({ message: 'status is required' });

    const oldStatus = ticket.status;

    // Validate workflow transition
    const template = await TicketTemplate.findById(ticket.template).lean();
    if (template && template.workflow && template.workflow.transitions) {
      const allowed = template.workflow.transitions[oldStatus];
      if (Array.isArray(allowed) && !allowed.includes(status)) {
        return res.status(400).json({
          message: `Cannot transition from "${oldStatus}" to "${status}". Allowed: ${allowed.join(', ') || 'none'}`,
        });
      }
    }

    ticket.status = status;
    if (status === 'completed' || status === 'verified' || status === 'closed') {
      ticket.completedAt = ticket.completedAt || new Date();
    }

    await ticket.save();

    await auditService.log({
      resource_type: 'ticket',
      resource_id: ticket._id,
      action: 'status_changed',
      actor_id: req.user._id,
      company: ticket.company,
      details: { from: oldStatus, to: status },
    });

    // Real-time notification
    if (global.io) {
      global.io.emit('ticketStatusChanged', {
        ticketId: String(ticket._id),
        ticket_no: ticket.ticket_no,
        from: oldStatus,
        to: status,
        changedBy: req.user._id,
      });
    }

    const populated = await Ticket.findById(ticket._id)
      .populate('template', 'name description')
      .populate('assignee', 'name email employeeId')
      .populate('created_by', 'name email')
      .populate('company', 'name code')
      .lean();

    res.json(populated);
  } catch (err) {
    console.error('PATCH /api/tickets/:id/status error:', err);
    res.status(500).json({ message: 'Failed to update ticket status' });
  }
});

// ─── Upload attachment for a ticket ──────────────────────────────────────────
// POST /api/tickets/:id/attachments
router.post('/:id/attachments', protect, upload.single('file'), async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ message: 'No file uploaded' });
    }

    const ticket = await Ticket.findById(req.params.id);
    if (!ticket) return res.status(404).json({ message: 'Ticket not found' });

    const result = await storageService.uploadBuffer(
      req.file.buffer,
      req.file.originalname,
      req.file.mimetype,
      String(req.user._id)
    );

    ticket.attachments.push(result.url);
    await ticket.save();

    await auditService.log({
      resource_type: 'ticket',
      resource_id: ticket._id,
      action: 'attachment_added',
      actor_id: req.user._id,
      company: ticket.company,
      details: { filename: req.file.originalname, checksum: result.checksum },
    });

    res.status(201).json({
      path: result.url,
      fileId: result.fileId,
      checksum: result.checksum,
      originalName: req.file.originalname,
      size: req.file.size,
    });
  } catch (err) {
    console.error('POST /api/tickets/:id/attachments error:', err);
    res.status(500).json({ message: 'Failed to upload attachment' });
  }
});

// ─── Download ticket attachment ──────────────────────────────────────────────
// GET /api/tickets/attachments/:fileId
router.get('/attachments/:fileId', protect, async (req, res) => {
  try {
    const result = await storageService.getFileStream(req.params.fileId);
    if (!result) {
      return res.status(404).json({ message: 'Attachment not found' });
    }

    const { stream, file } = result;
    const contentType = file.contentType || 'application/octet-stream';
    const filename =
      (file.metadata && file.metadata.originalName) || file.filename || req.params.fileId;

    res.setHeader('Content-Type', contentType);
    if (typeof file.length === 'number') {
      res.setHeader('Content-Length', String(file.length));
    }
    res.setHeader(
      'Content-Disposition',
      `inline; filename="${filename.replace(/"/g, '')}"`
    );

    stream.on('error', (err) => {
      console.error('Attachment stream error:', err);
      if (!res.headersSent) res.status(500).json({ message: 'Stream error' });
      else res.end();
    });

    stream.pipe(res);
  } catch (err) {
    console.error('GET /api/tickets/attachments/:fileId error:', err);
    res.status(500).json({ message: 'Failed to download attachment' });
  }
});

// ─── Archive/restore ticket ──────────────────────────────────────────────────
router.patch('/:id/archive', protect, requireRole('admin'), async (req, res) => {
  try {
    const ticket = await Ticket.findByIdAndUpdate(
      req.params.id,
      { isArchived: true },
      { new: true }
    );
    if (!ticket) return res.status(404).json({ message: 'Ticket not found' });
    res.json(ticket);
  } catch (err) {
    res.status(500).json({ message: 'Failed to archive ticket' });
  }
});

router.patch('/:id/restore', protect, requireRole('admin'), async (req, res) => {
  try {
    const ticket = await Ticket.findByIdAndUpdate(
      req.params.id,
      { isArchived: false },
      { new: true }
    );
    if (!ticket) return res.status(404).json({ message: 'Ticket not found' });
    res.json(ticket);
  } catch (err) {
    res.status(500).json({ message: 'Failed to restore ticket' });
  }
});

module.exports = router;
