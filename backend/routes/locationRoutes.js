const express = require('express');
const router = express.Router();
const locationController = require('../controllers/locationController');
const { protect, admin } = require('../middleware/authMiddleware');

/**
 * Location Tracking Routes
 * All routes require authentication
 */

// Employee location update (real-time)
router.post('/update', protect, locationController.updateLocation);

// Get all online employees
router.get('/online-employees', protect, locationController.getOnlineEmployees);

// Get location history for employee
router.get('/history/:employeeId', protect, locationController.getLocationHistory);

// Mark employee as offline
router.post('/offline', protect, locationController.markOffline);

// Get specific employee location
router.get('/:employeeId', protect, locationController.getEmployeeLocation);

// Admin: Update employee status
router.post('/status/:employeeId', protect, admin, locationController.updateEmployeeStatus);

// Admin: Auto-checkout employee due to offline status
router.post('/auto-checkout/:employeeId', protect, admin, locationController.autoCheckoutEmployee);

// Admin: Send checkout warning to employee
router.post('/checkout-warning/:employeeId', protect, admin, locationController.sendCheckoutWarning);

module.exports = router;
