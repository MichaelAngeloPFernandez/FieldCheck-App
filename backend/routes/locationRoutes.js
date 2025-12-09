const express = require('express');
const router = express.Router();
const locationController = require('../controllers/locationController');
const { authenticate, admin } = require('../middleware/authMiddleware');

/**
 * Location Tracking Routes
 * All routes require authentication
 */

// Employee location update (real-time)
router.post('/update', authenticate, locationController.updateLocation);

// Get all online employees
router.get('/online-employees', authenticate, locationController.getOnlineEmployees);

// Get location history for employee
router.get('/history/:employeeId', authenticate, locationController.getLocationHistory);

// Mark employee as offline
router.post('/offline', authenticate, locationController.markOffline);

// Get specific employee location
router.get('/:employeeId', authenticate, locationController.getEmployeeLocation);

// Admin: Update employee status
router.post('/status/:employeeId', authenticate, admin, locationController.updateEmployeeStatus);

module.exports = router;
