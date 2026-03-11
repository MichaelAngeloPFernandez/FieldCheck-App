const express = require('express');
const router = express.Router();
const { protect, admin } = require('../middleware/authMiddleware');
const {
  sendUrgentMultichannel,
} = require('../controllers/notificationController');

// Admin endpoints
router.post('/urgent-multichannel', protect, admin, sendUrgentMultichannel);

module.exports = router;
