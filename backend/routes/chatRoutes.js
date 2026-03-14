const express = require('express');
const router = express.Router();

const { protect } = require('../middleware/authMiddleware');
const {
  listConversations,
  getOrCreateConversation,
  listMessages,
  sendMessage,
  markConversationRead,
} = require('../controllers/chatController');

router.get('/conversations', protect, listConversations);
router.post('/conversations', protect, getOrCreateConversation);
router.get('/conversations/:id/messages', protect, listMessages);
router.post('/conversations/:id/messages', protect, sendMessage);
router.post('/conversations/:id/mark-read', protect, markConversationRead);

module.exports = router;
