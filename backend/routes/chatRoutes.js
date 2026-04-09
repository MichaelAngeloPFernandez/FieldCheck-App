const express = require('express');
const router = express.Router();

const { protect, admin } = require('../middleware/authMiddleware');
const {
  listConversations,
  getOrCreateConversation,
  listMessages,
  sendMessage,
  markConversationRead,
  archiveConversation,
  unarchiveConversation,
  deleteConversation,
  listOnlineAdmins,
  createGroupConversation,
  addGroupMembers,
  removeGroupMembers,
} = require('../controllers/chatController');

router.get('/admins/online', protect, listOnlineAdmins);

router.get('/conversations', protect, listConversations);
router.post('/conversations', protect, getOrCreateConversation);
router.post('/conversations/:id/archive', protect, archiveConversation);
router.post('/conversations/:id/unarchive', protect, unarchiveConversation);
router.post('/conversations/:id/delete', protect, deleteConversation);
router.get('/conversations/:id/messages', protect, listMessages);
router.post('/conversations/:id/messages', protect, sendMessage);
router.post('/conversations/:id/mark-read', protect, markConversationRead);

router.post('/group-conversations', protect, admin, createGroupConversation);
router.post(
  '/group-conversations/:id/members/add',
  protect,
  admin,
  addGroupMembers,
);
router.post(
  '/group-conversations/:id/members/remove',
  protect,
  admin,
  removeGroupMembers,
);

module.exports = router;
