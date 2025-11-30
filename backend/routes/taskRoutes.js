const express = require('express');
const router = express.Router();
const {
  getTasks,
  createTask,
  updateTask,
  deleteTask,
  getUserTasks,
  getAssignedTasks,
  assignTaskToUser,
  assignTaskToMultipleUsers,
  updateUserTaskStatus,
} = require('../controllers/taskController');
const { protect, admin } = require('../middleware/authMiddleware');

// List and create tasks
router.get('/', protect, getTasks);
router.post('/', protect, admin, createTask);

// User task operations (must be BEFORE /:id routes to avoid conflicts)
router.get('/user/:userId', protect, getUserTasks);
router.get('/assigned/:userId', protect, getAssignedTasks);
router.post('/:taskId/assign/:userId', protect, admin, assignTaskToUser);
router.post('/:taskId/assign-multiple', protect, admin, assignTaskToMultipleUsers);
router.put('/user-task/:userTaskId/status', protect, updateUserTaskStatus);

// Update/delete specific task (must be AFTER specific routes)
router.put('/:id', protect, admin, updateTask);
router.delete('/:id', protect, admin, deleteTask);

module.exports = router;