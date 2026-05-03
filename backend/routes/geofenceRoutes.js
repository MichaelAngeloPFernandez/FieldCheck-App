const express = require('express');
const router = express.Router();
const { createGeofence, getGeofences, getGeofenceById, updateGeofence, deleteGeofence } = require('../controllers/geofenceController');
const { protect } = require('../middleware/authMiddleware');

router.route('/').post(protect, createGeofence).get(protect, getGeofences);
router.route('/:id').get(protect, getGeofenceById).put(protect, updateGeofence).delete(protect, deleteGeofence);

module.exports = router;