const express = require('express');
const router = express.Router();
const { protect } = require('../middleware/authMiddleware');

const {
  getUnreadCount,
  listNotifications,
  markRead,
  markUnread,
  markReadScope,
  markAllRead,
  deleteByIds,
} = require('../controllers/appNotificationController');

router.get('/unread-count', protect, getUnreadCount);
router.get('/', protect, listNotifications);
router.post('/mark-read', protect, markRead);
router.post('/mark-unread', protect, markUnread);
router.post('/mark-read-scope', protect, markReadScope);
router.post('/mark-all-read', protect, markAllRead);
router.post('/delete', protect, deleteByIds);

module.exports = router;
