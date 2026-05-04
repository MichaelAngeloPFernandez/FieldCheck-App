const Task = require('../models/Task');
const Ticket = require('../models/Ticket');
const User = require('../models/User');

async function sendSms() {
  return;
}

async function notifyTaskAssigned() {
  return;
}

async function notifyTaskOverdue() {
  return;
}

async function notifyTaskEscalated() {
  return;
}

async function notifyAttendanceCheckIn() {
  return;
}

async function notifyAttendanceCheckOut() {
  return;
}

async function notifyAutoCheckoutWarning() {
  return;
}

async function notifyLocationWarning() {
  return;
}

async function notifyWorkloadWarning() {
  return;
}

/**
 * Notify employee when a task is assigned to them
 * @param {string} taskId - The task ID
 * @param {string} employeeId - The employee ID being assigned
 * @param {string} assignedById - The user ID who assigned the task
 * @returns {Promise<void>}
 */
async function notifyTaskAssignment(taskId, employeeId, assignedById) {
  try {
    const task = await Task.findById(taskId)
      .populate('ticketId', 'title')
      .populate('templateId', 'title');
    const employee = await User.findById(employeeId);
    const assignedBy = await User.findById(assignedById);

    if (!task || !employee || !assignedBy) {
      console.warn('Missing data for task assignment notification');
      return;
    }

    const taskOriginLabel = task.taskOrigin === 'template' ? 'Template Task' : 'Ad-hoc Task';
    const ticketTitle = task.ticketId?.title || 'Unknown Ticket';

    const notificationData = {
      type: 'task_assigned',
      title: `New ${taskOriginLabel} Assigned`,
      message: `${assignedBy.name} assigned you task: "${task.title}" for ticket "${ticketTitle}"`,
      taskId: task._id,
      ticketId: task.ticketId,
      taskOrigin: task.taskOrigin,
      description: task.description,
      type: task.type,
      difficulty: task.difficulty,
    };

    // Emit socket event if available
    if (global.io) {
      global.io.to(`user_${employeeId}`).emit('taskAssigned', notificationData);
    }

    console.log(`Task assignment notification sent to ${employee.name}`);
  } catch (error) {
    console.error('Error sending task assignment notification:', error);
  }
}

/**
 * Notify relevant users when a task is completed
 * @param {string} taskId - The task ID
 * @param {string} completedById - The user ID who completed the task
 * @returns {Promise<void>}
 */
async function notifyTaskCompletion(taskId, completedById) {
  try {
    const task = await Task.findById(taskId)
      .populate('ticketId', 'title')
      .populate('assignedBy', 'name')
      .populate('completedBy', 'name');

    if (!task) {
      console.warn('Task not found for completion notification');
      return;
    }

    const completedBy = await User.findById(completedById);
    const ticketTitle = task.ticketId?.title || 'Unknown Ticket';

    const notificationData = {
      type: 'task_completed',
      title: 'Task Completed',
      message: `${completedBy?.name || 'Employee'} completed task: "${task.title}"`,
      taskId: task._id,
      ticketId: task.ticketId,
      taskOrigin: task.taskOrigin,
      completedAt: task.completedAt,
      taskDuration: task.taskDuration,
    };

    // Notify the person who assigned the task
    if (task.assignedBy) {
      if (global.io) {
        global.io.to(`user_${task.assignedBy}`).emit('taskCompleted', notificationData);
      }
    }

    console.log(`Task completion notification sent for task ${task._id}`);
  } catch (error) {
    console.error('Error sending task completion notification:', error);
  }
}

/**
 * Notify relevant users when task status changes
 * @param {string} taskId - The task ID
 * @param {string} oldStatus - The previous status
 * @param {string} newStatus - The new status
 * @param {string} changedById - The user ID who changed the status
 * @param {string} reason - Optional reason for status change
 * @returns {Promise<void>}
 */
async function notifyTaskStatusChange(taskId, oldStatus, newStatus, changedById, reason = '') {
  try {
    const task = await Task.findById(taskId)
      .populate('ticketId', 'title')
      .populate('assignedTo', 'name');
    const changedBy = await User.findById(changedById);

    if (!task || !changedBy) {
      console.warn('Missing data for task status change notification');
      return;
    }

    const ticketTitle = task.ticketId?.title || 'Unknown Ticket';

    const notificationData = {
      type: 'task_status_changed',
      title: 'Task Status Updated',
      message: `Task "${task.title}" status changed from "${oldStatus}" to "${newStatus}" by ${changedBy.name}`,
      taskId: task._id,
      ticketId: task.ticketId,
      oldStatus,
      newStatus,
      reason,
      changedBy: changedBy.name,
      taskOrigin: task.taskOrigin,
    };

    // Notify the assigned employee
    if (task.assignedTo) {
      if (global.io) {
        global.io.to(`user_${task.assignedTo}`).emit('taskStatusChanged', notificationData);
      }
    }

    // Notify the person who assigned the task
    if (task.assignedBy && task.assignedBy.toString() !== changedById) {
      if (global.io) {
        global.io.to(`user_${task.assignedBy}`).emit('taskStatusChanged', notificationData);
      }
    }

    console.log(`Task status change notification sent for task ${task._id}`);
  } catch (error) {
    console.error('Error sending task status change notification:', error);
  }
}

module.exports = {
  sendSms,
  notifyTaskAssigned,
  notifyTaskOverdue,
  notifyTaskEscalated,
  notifyAttendanceCheckIn,
  notifyAttendanceCheckOut,
  notifyAutoCheckoutWarning,
  notifyLocationWarning,
  notifyWorkloadWarning,
  notifyTaskAssignment,
  notifyTaskCompletion,
  notifyTaskStatusChange,
};
