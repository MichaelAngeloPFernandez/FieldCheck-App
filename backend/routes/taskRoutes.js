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
  updateUserTaskStatus,
} = require('../controllers/taskController');
const { protect, admin } = require('../middleware/authMiddleware');

// List and create tasks
router.get('/', protect, getTasks);
router.post('/', protect, admin, createTask);

// Update/delete specific task
router.put('/:id', protect, admin, updateTask);
router.delete('/:id', protect, admin, deleteTask);

// User task operations
router.get('/user/:userId', protect, getUserTasks);
router.get('/assigned/:userId', protect, getAssignedTasks);
router.post('/:taskId/assign/:userId', protect, admin, assignTaskToUser);
router.put('/user-task/:userTaskId/status', protect, updateUserTaskStatus);

module.exports = router;