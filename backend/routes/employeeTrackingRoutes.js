const express = require('express');
const router = express.Router();
const { protect, admin } = require('../middleware/authMiddleware');
const {
  getNearbyEmployees,
  getEmployeeWorkload,
  getEmployeeAvailability,
  updateEmployeeLocation,
  getEmployeeStats,
  getOverdueTasksForEmployee,
} = require('../controllers/employeeTrackingController');

// Get nearby employees within radius
router.get('/nearby', protect, admin, getNearbyEmployees);

// Get employee workload
router.get('/workload/:employeeId', protect, admin, getEmployeeWorkload);

// Get employee availability
router.get('/availability/:employeeId', protect, admin, getEmployeeAvailability);

// Update employee location (called by frontend)
router.post('/location', protect, updateEmployeeLocation);

// Get employee statistics
router.get('/stats/:employeeId', protect, admin, getEmployeeStats);

// Get overdue tasks for employee
router.get('/overdue/:employeeId', protect, admin, getOverdueTasksForEmployee);

module.exports = router;
