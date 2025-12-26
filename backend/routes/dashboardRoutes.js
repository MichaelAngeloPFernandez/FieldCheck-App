const express = require('express');
const router = express.Router();
const { getDashboardStats, getRealtimeUpdates } = require('../controllers/dashboardController');
const { protect, admin } = require('../middleware/authMiddleware');

// Dashboard routes
router.get('/stats', protect, admin, getDashboardStats);
router.get('/realtime', protect, admin, getRealtimeUpdates);

module.exports = router;
