const asyncHandler = require('express-async-handler');
const Service = require('../models/Service');
const TaskTemplate = require('../models/TaskTemplate');

/**
 * POST /api/services
 * Create a new service for the company
 * Auth: Admin only
 */
const createService = asyncHandler(async (req, res) => {
  const { name, description } = req.body;
  const companyId = req.companyId;

  // Validate required fields
  if (!name || !name.trim()) {
    res.status(400);
    throw new Error('Service name is required');
  }

  // Check if service with same name already exists for this company
  const existingService = await Service.findOne({
    companyId,
    name: name.trim(),
  });

  if (existingService) {
    res.status(400);
    throw new Error(`Service with name "${name}" already exists for this company`);
  }

  // Create new service
  const service = await Service.create({
    companyId,
    name: name.trim(),
    description: description ? description.trim() : '',
    isActive: true,
  });

  res.status(201).json(service);
});

/**
 * GET /api/services
 * List all services for the company
 * Auth: Admin only
 * Query params: ?isActive=true&sort=name
 */
const getServices = asyncHandler(async (req, res) => {
  const companyId = req.companyId;
  const { isActive, sort } = req.query;

  // Build filter
  const filter = { companyId };
  if (isActive !== undefined) {
    filter.isActive = isActive === 'true';
  }

  // Build sort
  let sortObj = { createdAt: -1 };
  if (sort === 'name') {
    sortObj = { name: 1 };
  } else if (sort === '-name') {
    sortObj = { name: -1 };
  }

  // Get services with template count
  const services = await Service.find(filter).sort(sortObj).lean();

  // Enrich with template count
  const enrichedServices = await Promise.all(
    services.map(async (service) => {
      const templateCount = await TaskTemplate.countDocuments({
        serviceId: service._id,
      });
      return {
        ...service,
        templateCount,
      };
    })
  );

  res.json(enrichedServices);
});

/**
 * GET /api/services/:id
 * Get service details with associated templates
 * Auth: Admin only
 */
const getServiceById = asyncHandler(async (req, res) => {
  const { id } = req.params;
  const companyId = req.companyId;

  // Get service
  const service = await Service.findOne({
    _id: id,
    companyId,
  });

  if (!service) {
    res.status(404);
    throw new Error('Service not found');
  }

  // Get associated templates
  const templates = await TaskTemplate.find({
    serviceId: id,
  }).select('_id title description type difficulty isActive createdAt');

  res.json({
    ...service.toObject(),
    templates,
  });
});

/**
 * PUT /api/services/:id
 * Update service
 * Auth: Admin only
 * Body: { name, description, isActive }
 */
const updateService = asyncHandler(async (req, res) => {
  const { id } = req.params;
  const companyId = req.companyId;
  const { name, description, isActive } = req.body;

  // Get service
  const service = await Service.findOne({
    _id: id,
    companyId,
  });

  if (!service) {
    res.status(404);
    throw new Error('Service not found');
  }

  // Check if new name conflicts with another service
  if (name && name.trim() && name.trim() !== service.name) {
    const existingService = await Service.findOne({
      companyId,
      name: name.trim(),
      _id: { $ne: id },
    });

    if (existingService) {
      res.status(400);
      throw new Error(`Service with name "${name}" already exists for this company`);
    }

    service.name = name.trim();
  }

  // Update optional fields
  if (description !== undefined) {
    service.description = description ? description.trim() : '';
  }

  if (isActive !== undefined) {
    service.isActive = !!isActive;
  }

  await service.save();

  res.json(service);
});

/**
 * DELETE /api/services/:id
 * Delete service and all associated templates
 * Auth: Admin only
 */
const deleteService = asyncHandler(async (req, res) => {
  const { id } = req.params;
  const companyId = req.companyId;

  // Get service
  const service = await Service.findOne({
    _id: id,
    companyId,
  });

  if (!service) {
    res.status(404);
    throw new Error('Service not found');
  }

  // Delete all associated templates
  await TaskTemplate.deleteMany({
    serviceId: id,
  });

  // Delete service
  await Service.deleteOne({
    _id: id,
  });

  res.json({
    success: true,
    message: 'Service and associated templates deleted successfully',
  });
});

module.exports = {
  createService,
  getServices,
  getServiceById,
  updateService,
  deleteService,
};
