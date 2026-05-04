const Task = require('../models/Task');

// Valid status transitions
const VALID_TRANSITIONS = {
  pending: ['in_progress', 'blocked'],
  in_progress: ['completed', 'blocked'],
  blocked: ['in_progress'],
  completed: ['reviewed'],
  reviewed: ['closed'],
};

// Any status can transition to blocked
const ALLOW_BLOCK_FROM_ANY = true;

/**
 * Validate if a status transition is allowed
 * @param {string} currentStatus - Current task status
 * @param {string} newStatus - New task status
 * @returns {boolean} True if transition is valid
 */
function isValidTransition(currentStatus, newStatus) {
  // Normalize statuses
  const current = String(currentStatus || 'pending').toLowerCase();
  const next = String(newStatus || '').toLowerCase();

  // Any status can transition to blocked
  if (next === 'blocked' && ALLOW_BLOCK_FROM_ANY) {
    return true;
  }

  // Check if transition is in valid transitions map
  const validNextStatuses = VALID_TRANSITIONS[current] || [];
  return validNextStatuses.includes(next);
}

/**
 * Update task status with validation and history recording
 * @param {string} taskId - The task ID to update
 * @param {string} newStatus - The new status
 * @param {string} userId - The user ID performing the update
 * @param {string} reason - Optional reason for status change
 * @returns {Promise<Object>} Updated task document
 * @throws {Error} If task not found or transition is invalid
 */
async function updateTaskStatus(taskId, newStatus, userId, reason = '') {
  // Get current task
  const task = await Task.findById(taskId);

  if (!task) {
    throw new Error('Task not found');
  }

  const currentStatus = task.status || 'pending';

  // Validate transition
  if (!isValidTransition(currentStatus, newStatus)) {
    throw new Error(
      `Invalid status transition from "${currentStatus}" to "${newStatus}"`
    );
  }

  // If transitioning to blocked, require a reason
  if (newStatus === 'blocked' && !reason) {
    throw new Error('Block reason is required when blocking a task');
  }

  // Update task status
  task.status = newStatus;

  // Record status change in history
  task.statusHistory.push({
    status: newStatus,
    changedBy: userId,
    changedAt: new Date(),
    reason: reason || '',
  });

  // If blocked, record the block reason
  if (newStatus === 'blocked') {
    task.blockReason = reason;
  }

  // If completed, record completion details
  if (newStatus === 'completed') {
    task.completedAt = new Date();
    task.completedBy = userId;

    // Calculate task duration (in milliseconds)
    if (task.createdAt) {
      task.taskDuration = task.completedAt.getTime() - task.createdAt.getTime();
    }
  }

  // Save updated task
  await task.save();

  return task;
}

/**
 * Get task status history
 * @param {string} taskId - The task ID
 * @returns {Promise<Array>} Array of status history entries
 * @throws {Error} If task not found
 */
async function getTaskStatusHistory(taskId) {
  const task = await Task.findById(taskId).populate('statusHistory.changedBy', 'name email');

  if (!task) {
    throw new Error('Task not found');
  }

  return task.statusHistory;
}

/**
 * Get valid next statuses for a task
 * @param {string} currentStatus - Current task status
 * @returns {Array<string>} Array of valid next statuses
 */
function getValidNextStatuses(currentStatus) {
  const current = String(currentStatus || 'pending').toLowerCase();
  const validStatuses = VALID_TRANSITIONS[current] || [];

  // Add blocked as always valid
  if (!validStatuses.includes('blocked')) {
    validStatuses.push('blocked');
  }

  return validStatuses;
}

module.exports = {
  isValidTransition,
  updateTaskStatus,
  getTaskStatusHistory,
  getValidNextStatuses,
  VALID_TRANSITIONS,
};
