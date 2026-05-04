const Task = require('../models/Task');
const TaskTemplate = require('../models/TaskTemplate');
const Service = require('../models/Service');

/**
 * Clone all active templates for a service as tasks for a ticket
 * @param {string} ticketId - The ticket ID to clone tasks for
 * @param {string} serviceId - The service ID to get templates from
 * @param {string} companyId - The company ID for multi-tenancy
 * @param {string} userId - The user ID performing the cloning (assignedBy)
 * @returns {Promise<Array>} Array of cloned task documents
 * @throws {Error} If service not found or other critical errors
 */
async function cloneTemplateTasksForTicket(ticketId, serviceId, companyId, userId) {
  // Validate service exists and belongs to company
  const service = await Service.findOne({
    _id: serviceId,
    companyId,
  });

  if (!service) {
    throw new Error('Service not found');
  }

  // Get all active templates for the service
  const templates = await TaskTemplate.find({
    serviceId,
    companyId,
    isActive: true,
  });

  if (!templates.length) {
    return [];
  }

  // Clone each template as a task
  const clonedTasks = [];
  const errors = [];

  for (const template of templates) {
    try {
      const task = await Task.create({
        title: template.title,
        description: template.description,
        type: template.type,
        difficulty: template.difficulty,
        checklist: template.checklist.map((item) => ({
          label: item.label,
          isCompleted: false,
          completedAt: null,
        })),
        taskOrigin: 'template',
        templateId: template._id,
        ticketId,
        companyId,
        assignedBy: userId,
        status: 'pending',
        statusHistory: [
          {
            status: 'pending',
            changedBy: userId,
            changedAt: new Date(),
            reason: 'Task created from template',
          },
        ],
      });

      clonedTasks.push(task);
    } catch (error) {
      // Log error but continue with next template
      errors.push({
        templateId: template._id,
        templateTitle: template.title,
        error: error.message,
      });
      console.error(`Error cloning template ${template._id}:`, error);
    }
  }

  // Log any errors that occurred during cloning
  if (errors.length > 0) {
    console.warn(`Cloning completed with ${errors.length} errors:`, errors);
  }

  return clonedTasks;
}

module.exports = {
  cloneTemplateTasksForTicket,
};
