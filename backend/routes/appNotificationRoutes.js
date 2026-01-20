const express = require('express');
const router = express.Router();
const { protect } = require('../middleware/authMiddleware');

const {
  getUnreadCount,
  listNotifications,
  markRead,
  markReadScope,
} = require('../controllers/appNotificationController');

router.get('/unread-count', protect, getUnreadCount);
router.get('/', protect, listNotifications);
router.post('/mark-read', protect, markRead);
router.post('/mark-read-scope', protect, markReadScope);

module.exports = router;
