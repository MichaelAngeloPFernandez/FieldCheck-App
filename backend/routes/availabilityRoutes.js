const express = require('express');
const router = express.Router();
const { protect, admin } = require('../middleware/authMiddleware');
const {
  getOnlineEmployeesAvailability,
  getNearbyEmployeesForGeofence,
  getNearbyEmployeesForTask,
} = require('../controllers/availabilityController');

router.get('/online', protect, admin, getOnlineEmployeesAvailability);
router.get('/geofence/:geofenceId', protect, admin, getNearbyEmployeesForGeofence);
router.get('/task/:taskId', protect, admin, getNearbyEmployeesForTask);

module.exports = router;
