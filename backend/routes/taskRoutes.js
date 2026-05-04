const express = require('express');
const router = express.Router();
const {
  getTask,
  getTaskAssignees,
  getTasks,
  getCurrentTasks,
  getArchivedTasks,
  getOverdueTasks,
  createTask,
  updateTask,
  deleteTask,
  getUserTasks,
  getAssignedTasks,
  assignTaskToUser,
  assignTaskToMultipleUsers,
  unassignTaskFromUser,
  updateUserTaskStatus,
  acceptUserTask,
  cancelUserTask,
  markUserTaskViewed,
  archiveUserTask,
  restoreUserTask,
  updateTaskChecklistItem,
  blockTask,
  unblockUserTask,
  closeUserTask,
  archiveTask,
  restoreTask,
  escalateTask,
  gradeUserTask,
  addCommentToUserTask,
  createAdHocTask,
  getTicketTasks,
  assignTaskToEmployee,
  updateTaskStatus,
  completeChecklistItem,
} = require('../controllers/taskController');

const { protect, admin, requireCompany } = require('../middleware/authMiddleware');

// List and create tasks
router.get('/', protect, getTasks);
router.post('/', protect, admin, createTask);

// Specific routes (must be BEFORE /:id routes to avoid conflicts)
router.get('/user/:userId', protect, getUserTasks);
router.get('/assigned/:userId', protect, getAssignedTasks);
router.get('/current', protect, admin, getCurrentTasks);
router.get('/archived', protect, admin, getArchivedTasks);
router.get('/overdue', protect, admin, getOverdueTasks);
router.get('/:taskId/assignees', protect, admin, getTaskAssignees);
router.post('/:taskId/assign/:userId', protect, admin, assignTaskToUser);
router.post('/:taskId/assign-multiple', protect, admin, assignTaskToMultipleUsers);
router.delete('/:taskId/unassign/:userId', protect, admin, unassignTaskFromUser);
router.post('/user-task/:userTaskId/accept', protect, acceptUserTask);
router.post('/user-task/:userTaskId/cancel', protect, cancelUserTask);
router.put('/user-task/:userTaskId/status', protect, updateUserTaskStatus);
router.put('/user-task/:userTaskId/view', protect, markUserTaskViewed);
router.put('/user-task/:userTaskId/archive', protect, archiveUserTask);
router.put('/user-task/:userTaskId/restore', protect, restoreUserTask);
router.put('/user-task/:userTaskId/unblock', protect, admin, unblockUserTask);
router.put('/user-task/:userTaskId/close', protect, admin, closeUserTask);
router.put('/user-task/:userTaskId/grade', protect, admin, gradeUserTask);
router.post('/user-task/:userTaskId/comment', protect, addCommentToUserTask);
router.put('/:id/archive', protect, admin, archiveTask);
router.put('/:id/restore', protect, admin, restoreTask);
router.post('/:id/escalate', protect, admin, escalateTask);

// Employee/admin actions on a specific task
router.put('/:id/checklist-item', protect, updateTaskChecklistItem);
router.put('/:id/block', protect, blockTask);

// Task Template System endpoints (must be BEFORE /:id routes)
// Create ad-hoc task for ticket
router.post('/ticket/:ticketId/create', protect, admin, requireCompany, createAdHocTask);

// Get tasks for ticket with filtering
router.get('/ticket/:ticketId/list', protect, requireCompany, getTicketTasks);

// Assign task to employee
router.put('/:id/assign', protect, admin, requireCompany, assignTaskToEmployee);

// Change task status
router.put('/:id/status', protect, requireCompany, updateTaskStatus);

// Complete checklist item
router.post('/:id/checklist/:itemIndex/complete', protect, requireCompany, completeChecklistItem);

// Generic /:id routes (must be LAST to avoid conflicts)
router.get('/:id', protect, getTask);
router.put('/:id', protect, admin, updateTask);
router.delete('/:id', protect, admin, deleteTask);

module.exports = router;