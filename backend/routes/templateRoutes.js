/**
 * Template Routes — CRUD for ticket templates.
 * Admin creates templates; field workers see them in a dropdown.
 */
const express = require('express');
const router = express.Router();
const { protect, requireRole, requireCompany } = require('../middleware/authMiddleware');
const TicketTemplate = require('../models/TicketTemplate');
const Company = require('../models/Company');
const auditService = require('../services/auditService');

// ─── List templates for the user's company ───────────────────────────────────
// GET /api/templates
// Admins see all; employees see active templates for their company.
router.get('/', protect, async (req, res) => {
  try {
    const companyId = req.user.company
      ? String(req.user.company._id || req.user.company)
      : null;

    const filter = { isActive: true };
    if (companyId) {
      filter.$or = [
        { company: companyId },
        { visibility: 'public' },
      ];
    }
    // If user has no company, show only public templates
    if (!companyId) {
      filter.visibility = 'public';
    }

    const templates = await TicketTemplate.find(filter)
      .populate('company', 'name code')
      .populate('created_by', 'name email')
      .sort({ createdAt: -1 })
      .lean();

    res.json(templates);
  } catch (err) {
    console.error('GET /api/templates error:', err);
    res.status(500).json({ message: 'Failed to fetch templates' });
  }
});

// ─── Get single template ─────────────────────────────────────────────────────
// GET /api/templates/:id
router.get('/:id', protect, async (req, res) => {
  try {
    const template = await TicketTemplate.findById(req.params.id)
      .populate('company', 'name code')
      .populate('created_by', 'name email')
      .lean();

    if (!template) {
      return res.status(404).json({ message: 'Template not found' });
    }

    // Company scoping: user must belong to the same company or template is public
    const userCompany = req.user.company
      ? String(req.user.company._id || req.user.company)
      : null;
    const templateCompany = template.company
      ? String(template.company._id || template.company)
      : null;

    if (template.visibility !== 'public' && userCompany !== templateCompany) {
      return res.status(403).json({ message: 'Access denied' });
    }

    res.json(template);
  } catch (err) {
    console.error('GET /api/templates/:id error:', err);
    res.status(500).json({ message: 'Failed to fetch template' });
  }
});

// ─── Create template ─────────────────────────────────────────────────────────
// POST /api/templates
// Admin only. Body: { name, description, json_schema, workflow, sla_seconds, company }
router.post('/', protect, requireRole('admin'), async (req, res) => {
  try {
    const {
      name,
      description,
      json_schema,
      workflow,
      sla_seconds,
      visibility,
      company: companyId,
    } = req.body;

    if (!name || !json_schema) {
      return res.status(400).json({ message: 'name and json_schema are required' });
    }

    // Resolve company: use explicit body value, or fall back to user's company
    let resolvedCompany = companyId || (req.user.company
      ? String(req.user.company._id || req.user.company)
      : null);

    if (!resolvedCompany) {
      return res.status(400).json({ message: 'company is required (set in body or user profile)' });
    }

    // Verify company exists
    const companyDoc = await Company.findById(resolvedCompany);
    if (!companyDoc) {
      return res.status(404).json({ message: 'Company not found' });
    }

    const template = await TicketTemplate.create({
      company: resolvedCompany,
      name,
      description: description || '',
      json_schema,
      workflow: workflow || undefined,
      sla_seconds: sla_seconds || null,
      visibility: visibility || 'company',
      created_by: req.user._id,
    });

    await auditService.log({
      resource_type: 'template',
      resource_id: template._id,
      action: 'created',
      actor_id: req.user._id,
      company: resolvedCompany,
      details: { name: template.name },
    });

    // Emit real-time event
    if (global.io) {
      global.io.emit('templateCreated', {
        templateId: String(template._id),
        name: template.name,
        company: resolvedCompany,
      });
    }

    const populated = await TicketTemplate.findById(template._id)
      .populate('company', 'name code')
      .populate('created_by', 'name email')
      .lean();

    res.status(201).json(populated);
  } catch (err) {
    console.error('POST /api/templates error:', err);
    res.status(500).json({ message: 'Failed to create template' });
  }
});

// ─── Update template ─────────────────────────────────────────────────────────
// PUT /api/templates/:id
router.put('/:id', protect, requireRole('admin'), async (req, res) => {
  try {
    const template = await TicketTemplate.findById(req.params.id);
    if (!template) {
      return res.status(404).json({ message: 'Template not found' });
    }

    const allowedFields = ['name', 'description', 'json_schema', 'workflow', 'sla_seconds', 'visibility', 'isActive'];
    const updates = {};
    for (const field of allowedFields) {
      if (req.body[field] !== undefined) {
        updates[field] = req.body[field];
      }
    }

    // Bump version if schema changed
    if (updates.json_schema) {
      updates.version = (template.version || 1) + 1;
    }

    Object.assign(template, updates);
    await template.save();

    await auditService.log({
      resource_type: 'template',
      resource_id: template._id,
      action: 'updated',
      actor_id: req.user._id,
      company: template.company,
      details: { updatedFields: Object.keys(updates) },
    });

    const populated = await TicketTemplate.findById(template._id)
      .populate('company', 'name code')
      .populate('created_by', 'name email')
      .lean();

    res.json(populated);
  } catch (err) {
    console.error('PUT /api/templates/:id error:', err);
    res.status(500).json({ message: 'Failed to update template' });
  }
});

// ─── Delete (soft) template ──────────────────────────────────────────────────
// DELETE /api/templates/:id
router.delete('/:id', protect, requireRole('admin'), async (req, res) => {
  try {
    const template = await TicketTemplate.findById(req.params.id);
    if (!template) {
      return res.status(404).json({ message: 'Template not found' });
    }

    template.isActive = false;
    await template.save();

    await auditService.log({
      resource_type: 'template',
      resource_id: template._id,
      action: 'deactivated',
      actor_id: req.user._id,
      company: template.company,
    });

    res.json({ message: 'Template deactivated' });
  } catch (err) {
    console.error('DELETE /api/templates/:id error:', err);
    res.status(500).json({ message: 'Failed to deactivate template' });
  }
});

module.exports = router;
