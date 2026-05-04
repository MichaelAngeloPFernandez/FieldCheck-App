const asyncHandler = require('express-async-handler');
const TaskTemplate = require('../models/TaskTemplate');
const Service = require('../models/Service');

/**
 * POST /api/templates/service/:serviceId
 * Create a new task template for a service
 * Auth: Admin only
 */
const createTemplate = asyncHandler(async (req, res) => {
  const { serviceId } = req.params;
  const companyId = req.companyId;
  const { title, description, type, difficulty, checklist } = req.body;

  // Validate required fields
  if (!title || !title.trim()) {
    res.status(400);
    throw new Error('Template title is required');
  }

  // Verify service exists and belongs to company
  const service = await Service.findOne({
    _id: serviceId,
    companyId,
  });

  if (!service) {
    res.status(404);
    throw new Error('Service not found');
  }

  // Validate type and difficulty if provided
  const validTypes = ['general', 'inspection', 'maintenance', 'delivery', 'other'];
  const validDifficulties = ['easy', 'medium', 'hard'];

  if (type && !validTypes.includes(type)) {
    res.status(400);
    throw new Error(`Invalid type. Must be one of: ${validTypes.join(', ')}`);
  }

  if (difficulty && !validDifficulties.includes(difficulty)) {
    res.status(400);
    throw new Error(`Invalid difficulty. Must be one of: ${validDifficulties.join(', ')}`);
  }

  // Validate checklist if provided
  let processedChecklist = [];
  if (checklist && Array.isArray(checklist)) {
    processedChecklist = checklist.map((item) => ({
      label: item.label ? String(item.label).trim() : '',
      isCompleted: false,
      itemCompletedAt: null,
    }));

    // Filter out empty labels
    processedChecklist = processedChecklist.filter((item) => item.label);
  }

  // Create template
  const template = await TaskTemplate.create({
    serviceId,
    companyId,
    title: title.trim(),
    description: description ? description.trim() : '',
    type: type || 'general',
    difficulty: difficulty || 'medium',
    checklist: processedChecklist,
    isActive: true,
  });

  res.status(201).json(template);
});

/**
 * GET /api/templates/service/:serviceId
 * List all templates for a service
 * Auth: Admin only
 * Query params: ?isActive=true&sort=title
 */
const getTemplatesByService = asyncHandler(async (req, res) => {
  const { serviceId } = req.params;
  const companyId = req.companyId;
  const { isActive, sort } = req.query;

  // Verify service exists and belongs to company
  const service = await Service.findOne({
    _id: serviceId,
    companyId,
  });

  if (!service) {
    res.status(404);
    throw new Error('Service not found');
  }

  // Build filter
  const filter = {
    serviceId,
    companyId,
  };

  if (isActive !== undefined) {
    filter.isActive = isActive === 'true';
  }

  // Build sort
  let sortObj = { createdAt: -1 };
  if (sort === 'title') {
    sortObj = { title: 1 };
  } else if (sort === '-title') {
    sortObj = { title: -1 };
  }

  const templates = await TaskTemplate.find(filter).sort(sortObj);

  res.json(templates);
});

/**
 * GET /api/templates/:id
 * Get template details
 * Auth: Admin only
 */
const getTemplateById = asyncHandler(async (req, res) => {
  const { id } = req.params;
  const companyId = req.companyId;

  const template = await TaskTemplate.findOne({
    _id: id,
    companyId,
  });

  if (!template) {
    res.status(404);
    throw new Error('Template not found');
  }

  res.json(template);
});

/**
 * PUT /api/templates/:id
 * Update template
 * Auth: Admin only
 * Body: { title, description, type, difficulty, checklist, isActive }
 */
const updateTemplate = asyncHandler(async (req, res) => {
  const { id } = req.params;
  const companyId = req.companyId;
  const { title, description, type, difficulty, checklist, isActive } = req.body;

  const template = await TaskTemplate.findOne({
    _id: id,
    companyId,
  });

  if (!template) {
    res.status(404);
    throw new Error('Template not found');
  }

  // Validate type if provided
  const validTypes = ['general', 'inspection', 'maintenance', 'delivery', 'other'];
  if (type && !validTypes.includes(type)) {
    res.status(400);
    throw new Error(`Invalid type. Must be one of: ${validTypes.join(', ')}`);
  }

  // Validate difficulty if provided
  const validDifficulties = ['easy', 'medium', 'hard'];
  if (difficulty && !validDifficulties.includes(difficulty)) {
    res.status(400);
    throw new Error(`Invalid difficulty. Must be one of: ${validDifficulties.join(', ')}`);
  }

  // Update fields
  if (title && title.trim()) {
    template.title = title.trim();
  }

  if (description !== undefined) {
    template.description = description ? description.trim() : '';
  }

  if (type) {
    template.type = type;
  }

  if (difficulty) {
    template.difficulty = difficulty;
  }

  if (checklist && Array.isArray(checklist)) {
    template.checklist = checklist.map((item) => ({
      label: item.label ? String(item.label).trim() : '',
      isCompleted: false,
      itemCompletedAt: null,
    }));

    // Filter out empty labels
    template.checklist = template.checklist.filter((item) => item.label);
  }

  if (isActive !== undefined) {
    template.isActive = !!isActive;
  }

  await template.save();

  res.json(template);
});

/**
 * DELETE /api/templates/:id
 * Delete template (does not affect cloned tasks)
 * Auth: Admin only
 */
const deleteTemplate = asyncHandler(async (req, res) => {
  const { id } = req.params;
  const companyId = req.companyId;

  const template = await TaskTemplate.findOne({
    _id: id,
    companyId,
  });

  if (!template) {
    res.status(404);
    throw new Error('Template not found');
  }

  await TaskTemplate.deleteOne({
    _id: id,
  });

  res.json({
    success: true,
    message: 'Template deleted successfully',
  });
});

module.exports = {
  createTemplate,
  getTemplatesByService,
  getTemplateById,
  updateTemplate,
  deleteTemplate,
};
