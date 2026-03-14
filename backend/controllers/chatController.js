const asyncHandler = require('express-async-handler');
const mongoose = require('mongoose');

const Conversation = require('../models/Conversation');
const ChatMessage = require('../models/ChatMessage');
const User = require('../models/User');
const appNotificationService = require('../services/appNotificationService');

function _asId(v) {
  const s = String(v || '').trim();
  if (!mongoose.Types.ObjectId.isValid(s)) return null;
  return s;
}

async function _assertCanChat(reqUser, otherUserId) {
  const other = await User.findById(otherUserId).select('role isActive').lean();
  if (!other || other.isActive === false) {
    const err = new Error('User not found');
    err.statusCode = 404;
    throw err;
  }

  const a = reqUser.role;
  const b = other.role;
  const ok =
    (a === 'admin' && b === 'employee') || (a === 'employee' && b === 'admin');
  if (!ok) {
    const err = new Error('Chat is only allowed between admins and employees');
    err.statusCode = 403;
    throw err;
  }

  return other;
}

async function _findOrCreateConversation(userIdA, userIdB) {
  const ids = [String(userIdA), String(userIdB)].sort();
  let convo = await Conversation.findOne({ participants: { $all: ids, $size: 2 } });
  if (convo) return convo;

  convo = await Conversation.create({
    participants: ids,
    lastMessageAt: null,
    lastMessagePreview: '',
  });
  return convo;
}

// @desc    List conversations for current user
// @route   GET /api/chat/conversations
// @access  Private
const listConversations = asyncHandler(async (req, res) => {
  const userId = String(req.user._id);
  const convos = await Conversation.find({ participants: userId })
    .sort({ lastMessageAt: -1, updatedAt: -1 })
    .limit(100)
    .lean();

  const otherIds = new Set();
  for (const c of convos) {
    for (const p of c.participants || []) {
      const s = String(p);
      if (s !== userId) otherIds.add(s);
    }
  }

  const others = otherIds.size
    ? await User.find({ _id: { $in: Array.from(otherIds) } })
        .select('_id name employeeId email phone role avatarUrl isOnline')
        .lean()
    : [];
  const otherById = new Map(others.map((u) => [String(u._id), u]));

  // unread counts per conversation (for this user)
  const unreadAgg = await ChatMessage.aggregate([
    {
      $match: {
        conversation: { $in: convos.map((c) => c._id) },
        readBy: { $ne: new mongoose.Types.ObjectId(userId) },
        senderUser: { $ne: new mongoose.Types.ObjectId(userId) },
      },
    },
    { $group: { _id: '$conversation', count: { $sum: 1 } } },
  ]);
  const unreadByConvo = new Map(
    unreadAgg.map((r) => [String(r._id), Number(r.count || 0)]),
  );

  res.json(
    convos.map((c) => {
      const otherId = (c.participants || []).map(String).find((p) => p !== userId);
      const other = otherId ? otherById.get(otherId) : null;
      return {
        id: String(c._id),
        participants: (c.participants || []).map(String),
        otherUser: other
          ? {
              id: String(other._id),
              name: other.name,
              employeeId: other.employeeId,
              email: other.email,
              phone: other.phone,
              role: other.role,
              avatarUrl: other.avatarUrl,
              isOnline: other.isOnline === true,
            }
          : null,
        lastMessageAt: c.lastMessageAt ? new Date(c.lastMessageAt).toISOString() : null,
        lastMessagePreview: c.lastMessagePreview || '',
        unreadCount: unreadByConvo.get(String(c._id)) || 0,
      };
    }),
  );
});

// @desc    Find or create conversation with another user
// @route   POST /api/chat/conversations
// @access  Private
const getOrCreateConversation = asyncHandler(async (req, res) => {
  const otherUserId = _asId(req.body?.otherUserId);
  if (!otherUserId) {
    res.status(400);
    throw new Error('otherUserId is required');
  }

  await _assertCanChat(req.user, otherUserId);

  const convo = await _findOrCreateConversation(req.user._id, otherUserId);
  res.status(200).json({ id: String(convo._id) });
});

// @desc    Get messages for a conversation
// @route   GET /api/chat/conversations/:id/messages
// @access  Private
const listMessages = asyncHandler(async (req, res) => {
  const convoId = _asId(req.params.id);
  if (!convoId) {
    res.status(400);
    throw new Error('Invalid conversation id');
  }

  const convo = await Conversation.findById(convoId).select('participants').lean();
  if (!convo) {
    res.status(404);
    throw new Error('Conversation not found');
  }

  const userId = String(req.user._id);
  if (!(convo.participants || []).map(String).includes(userId)) {
    res.status(403);
    throw new Error('Not allowed');
  }

  const limitRaw = parseInt(String(req.query.limit || '50'), 10);
  const before = (req.query.before || '').toString().trim();
  const limit = Number.isFinite(limitRaw) ? Math.max(1, Math.min(200, limitRaw)) : 50;

  const q = { conversation: convoId };
  if (before && mongoose.Types.ObjectId.isValid(before)) {
    q._id = { $lt: new mongoose.Types.ObjectId(before) };
  }

  const items = await ChatMessage.find(q)
    .sort({ _id: -1 })
    .limit(limit)
    .populate('senderUser', '_id name role employeeId avatarUrl')
    .lean();

  const ordered = items.reverse();
  res.json(
    ordered.map((m) => ({
      id: String(m._id),
      conversationId: String(m.conversation),
      senderUser: m.senderUser
        ? {
            id: String(m.senderUser._id),
            name: m.senderUser.name,
            role: m.senderUser.role,
            employeeId: m.senderUser.employeeId,
            avatarUrl: m.senderUser.avatarUrl,
          }
        : { id: String(m.senderUser) },
      body: m.body,
      createdAt: m.createdAt ? new Date(m.createdAt).toISOString() : null,
      readBy: (m.readBy || []).map(String),
    })),
  );
});

// @desc    Send a message
// @route   POST /api/chat/conversations/:id/messages
// @access  Private
const sendMessage = asyncHandler(async (req, res) => {
  const convoId = _asId(req.params.id);
  if (!convoId) {
    res.status(400);
    throw new Error('Invalid conversation id');
  }

  const body = (req.body?.body || '').toString().trim();
  if (!body) {
    res.status(400);
    throw new Error('Message body is required');
  }

  const convo = await Conversation.findById(convoId).select('participants').lean();
  if (!convo) {
    res.status(404);
    throw new Error('Conversation not found');
  }

  const userId = String(req.user._id);
  const participants = (convo.participants || []).map(String);
  if (!participants.includes(userId)) {
    res.status(403);
    throw new Error('Not allowed');
  }

  // enforce admin<->employee rule
  const otherId = participants.find((p) => p !== userId);
  if (!otherId) {
    res.status(400);
    throw new Error('Invalid conversation');
  }
  await _assertCanChat(req.user, otherId);

  const msg = await ChatMessage.create({
    conversation: convoId,
    senderUser: req.user._id,
    body,
    readBy: [req.user._id],
  });

  const preview = body.length > 120 ? `${body.slice(0, 120)}…` : body;
  await Conversation.findByIdAndUpdate(convoId, {
    $set: {
      lastMessageAt: msg.createdAt,
      lastMessagePreview: preview,
    },
  });

  // Persist a notification for the other participant so it shows in the bell
  // and contributes to unreadCounts.
  try {
    await appNotificationService.createNotification({
      recipientUserId: otherId,
      scope: 'messages',
      type: 'info',
      action: 'chatMessage',
      title: 'New message',
      message: preview,
      payload: {
        conversationId: String(convoId),
        senderUserId: userId,
      },
    });
  } catch (_) {}

  // Emit realtime event to both users
  try {
    const io = global.io;
    if (io) {
      const payload = {
        id: String(msg._id),
        conversationId: String(convoId),
        senderUserId: userId,
        body,
        createdAt: msg.createdAt?.toISOString?.() || new Date().toISOString(),
      };
      io.to(`user:${userId}`).emit('chatMessage', payload);
      io.to(`user:${otherId}`).emit('chatMessage', payload);
    }
  } catch (_) {}

  res.status(201).json({
    id: String(msg._id),
    conversationId: String(convoId),
    body,
    createdAt: msg.createdAt?.toISOString?.() || new Date().toISOString(),
  });
});

// @desc    Mark all messages in conversation as read for current user
// @route   POST /api/chat/conversations/:id/mark-read
// @access  Private
const markConversationRead = asyncHandler(async (req, res) => {
  const convoId = _asId(req.params.id);
  if (!convoId) {
    res.status(400);
    throw new Error('Invalid conversation id');
  }

  const convo = await Conversation.findById(convoId).select('participants').lean();
  if (!convo) {
    res.status(404);
    throw new Error('Conversation not found');
  }

  const userId = String(req.user._id);
  if (!(convo.participants || []).map(String).includes(userId)) {
    res.status(403);
    throw new Error('Not allowed');
  }

  // Add this user to readBy for all messages in convo
  const result = await ChatMessage.updateMany(
    { conversation: convoId, readBy: { $ne: req.user._id } },
    { $addToSet: { readBy: req.user._id } },
  );

  // Mark persisted message notifications as read for this conversation.
  // This keeps bell clean.
  try {
    const AppNotification = require('../models/AppNotification');
    await AppNotification.updateMany(
      {
        recipientUser: req.user._id,
        scope: 'messages',
        readAt: null,
        'payload.conversationId': String(convoId),
      },
      { $set: { readAt: new Date() } },
    );
  } catch (_) {}

  try {
    await appNotificationService.emitUnreadCounts(req.user._id);
  } catch (_) {}

  res.json({
    updated:
      typeof result.modifiedCount === 'number'
        ? result.modifiedCount
        : typeof result.nModified === 'number'
          ? result.nModified
          : 0,
  });
});

module.exports = {
  listConversations,
  getOrCreateConversation,
  listMessages,
  sendMessage,
  markConversationRead,
};
