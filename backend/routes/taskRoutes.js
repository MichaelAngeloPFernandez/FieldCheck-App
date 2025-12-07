const express = require('express');
const router = express.Router();
const {
  getTask,
  getTasks,
  getCurrentTasks,
  getArchivedTasks,
  createTask,
  updateTask,
  deleteTask,
  getUserTasks,
  getAssignedTasks,
  assignTaskToUser,
  assignTaskToMultipleUsers,
  updateUserTaskStatus,
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
router.post('/:taskId/assign/:userId', protect, admin, assignTaskToUser);
router.post('/:taskId/assign-multiple', protect, admin, assignTaskToMultipleUsers);
router.put('/user-task/:userTaskId/status', protect, updateUserTaskStatus);
router.put('/:id/archive', protect, admin, archiveTask);
router.put('/:id/restore', protect, admin, restoreTask);
router.post('/:id/escalate', protect, admin, escalateTask);

// Generic /:id routes (must be LAST to avoid conflicts)
router.get('/:id', protect, getTask);
router.put('/:id', protect, admin, updateTask);
router.delete('/:id', protect, admin, deleteTask);

module.exports = router;