const asyncHandler = require('express-async-handler');
const Ticket = require('../models/Ticket');
const Task = require('../models/Task');
const TaskTemplate = require('../models/TaskTemplate');
const Service = require('../models/Service');
const { cloneTemplateTasksForTicket } = require('../services/taskCloningService');

/**
 * POST /api/tickets
 * Create ticket with optional service
 * Auth: Admin only
 * Body: { title, description, serviceId }
 * Logic: If serviceId provided, clone all templates
 */
const createTicket = asyncHandler(async (req, res) => {
  const { title, description, serviceId } = req.body;
  const companyId = req.companyId;
  const userId = req.user._id;

  // Validate required fields
  if (!title || !title.trim()) {
    res.status(400);
    throw new Error('Ticket title is required');
  }

  // If serviceId provided, verify it exists and belongs to company
  if (serviceId) {
    const service = await Service.findOne({
      _id: serviceId,
      companyId,
    });

    if (!service) {
      res.status(404);
      throw new Error('Service not found');
    }
  }

  // Create ticket
  const ticket = await Ticket.create({
    companyId,
    serviceId: serviceId || null,
    title: title.trim(),
    description: description ? description.trim() : '',
    status: 'open',
  });

  // Clone templates if serviceId provided
  let clonedTasks = [];
  if (serviceId) {
    try {
      clonedTasks = await cloneTemplateTasksForTicket(ticket._id, serviceId, companyId, userId);
    } catch (error) {
      // Log error but don't fail ticket creation
      console.error('Error cloning template tasks:', error);
    }
  }

  // Return ticket with cloned tasks
  const response = {
    ...ticket.toObject(),
    tasks: clonedTasks,
  };

  res.status(201).json(response);
});

/**
 * GET /api/tickets
 * List tickets for company
 * Auth: Admin only
 * Query: ?status=open&serviceId=xxx&sort=createdAt
 */
const getTickets = asyncHandler(async (req, res) => {
  const companyId = req.companyId;
  const { status, serviceId, sort } = req.query;

  // Build filter
  const filter = { companyId };

  if (status) {
    filter.status = status;
  }

  if (serviceId) {
    filter.serviceId = serviceId;
  }

  // Build sort
  let sortObj = { createdAt: -1 };
  if (sort === 'title') {
    sortObj = { title: 1 };
  } else if (sort === '-title') {
    sortObj = { title: -1 };
  } else if (sort === 'status') {
    sortObj = { status: 1 };
  }

  const tickets = await Ticket.find(filter).sort(sortObj).populate('serviceId', 'name');

  res.json(tickets);
});

/**
 * GET /api/tickets/:id
 * Get ticket with all tasks
 * Auth: Admin, assigned Employees
 */
const getTicketById = asyncHandler(async (req, res) => {
  const { id } = req.params;
  const companyId = req.companyId;
  const userId = req.user._id;
  const userRole = req.user.role;

  // Get ticket
  const ticket = await Ticket.findOne({
    _id: id,
    companyId,
  }).populate('serviceId', 'name description');

  if (!ticket) {
    res.status(404);
    throw new Error('Ticket not found');
  }

  // Get all tasks for ticket
  const tasks = await Task.find({
    ticketId: id,
  })
    .populate('assignedTo', 'name employeeId')
    .populate('completedBy', 'name employeeId')
    .populate('templateId', 'title description type difficulty');

  // If user is employee, verify they have access to at least one task
  if (userRole === 'employee') {
    const hasAccess = tasks.some((task) => task.assignedTo && task.assignedTo._id.toString() === userId.toString());

    if (!hasAccess) {
      res.status(403);
      throw new Error('Not authorized to access this ticket');
    }
  }

  res.json({
    ...ticket.toObject(),
    tasks,
  });
});

/**
 * Clone all template tasks for a ticket
 * Internal helper function - now delegated to taskCloningService
 */
async function cloneTemplateTasksForTicket(ticketId, serviceId, companyId, userId) {
  // This function is now in taskCloningService
  // Kept here for backward compatibility
  const { cloneTemplateTasksForTicket: cloneService } = require('../services/taskCloningService');
  return cloneService(ticketId, serviceId, companyId, userId);
}

module.exports = {
  createTicket,
  getTickets,
  getTicketById,
  cloneTemplateTasksForTicket,
};
