const express = require('express');
const router = express.Router();
const { protect, admin } = require('../middleware/authMiddleware');
const { sendUrgentNotification } = require('../controllers/notificationController');

router.post('/urgent', protect, admin, sendUrgentNotification);

module.exports = router;
