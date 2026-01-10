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
  archiveUserTask,
  restoreUserTask,
  updateTaskChecklistItem,
  blockTask,
  archiveTask,
  restoreTask,
  escalateTask,
} = require('../controllers/taskController');

const { protect, admin } = require('../middleware/authMiddleware');

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
router.put('/user-task/:userTaskId/status', protect, updateUserTaskStatus);
router.put('/user-task/:userTaskId/archive', protect, archiveUserTask);
router.put('/user-task/:userTaskId/restore', protect, restoreUserTask);
router.put('/:id/archive', protect, admin, archiveTask);
router.put('/:id/restore', protect, admin, restoreTask);
router.post('/:id/escalate', protect, admin, escalateTask);

// Employee/admin actions on a specific task
router.put('/:id/checklist-item', protect, updateTaskChecklistItem);
router.put('/:id/block', protect, blockTask);

// Generic /:id routes (must be LAST to avoid conflicts)
router.get('/:id', protect, getTask);
router.put('/:id', protect, admin, updateTask);
router.delete('/:id', protect, admin, deleteTask);

module.exports = router;