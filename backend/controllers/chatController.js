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

async function _assertEmployeeMayStartConversationWithAdmin(reqUser) {
  if (!reqUser || reqUser.role !== 'employee') return;
  const onlineAdmin = await User.findOne({ role: 'admin', isOnline: true, isActive: true })
    .select('_id')
    .lean();
  if (!onlineAdmin) {
    const err = new Error('No admin is currently online');
    err.statusCode = 403;
    throw err;
  }
}

async function _findOrCreateConversation(userIdA, userIdB) {
  const ids = [String(userIdA), String(userIdB)].sort();
  let convo = await Conversation.findOne({
    participants: { $all: ids, $size: 2 },
    isGroup: false,
  });
  if (convo) return convo;

  convo = await Conversation.create({
    participants: ids,
    isGroup: false,
    title: '',
    createdBy: null,
    lastMessageAt: null,
    lastMessagePreview: '',
  });
  return convo;
}

function _asBool(v) {
  if (v == null) return null;
  const s = String(v).trim().toLowerCase();
  if (s === 'true' || s === '1' || s === 'yes') return true;
  if (s === 'false' || s === '0' || s === 'no') return false;
  return null;
}

function _isArchivedFor(convo, userId) {
  try {
    return (convo.archivedBy || []).some((r) => String(r.userId) === String(userId));
  } catch (_) {
    return false;
  }
}

function _isDeletedFor(convo, userId) {
  try {
    return (convo.deletedBy || []).some((r) => String(r.userId) === String(userId));
  } catch (_) {
    return false;
  }
}

// @desc    List conversations for current user
// @route   GET /api/chat/conversations
// @access  Private
const listConversations = asyncHandler(async (req, res) => {
  const userId = String(req.user._id);
  const archivedQuery = _asBool(req.query.archived);
  const includeArchived = archivedQuery === true;

  const convos = await Conversation.find({
    participants: userId,
    'deletedBy.userId': { $ne: new mongoose.Types.ObjectId(userId) },
    ...(includeArchived
      ? { 'archivedBy.userId': new mongoose.Types.ObjectId(userId) }
      : { 'archivedBy.userId': { $ne: new mongoose.Types.ObjectId(userId) } }),
  })
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
      const other = (!c.isGroup && otherId) ? otherById.get(otherId) : null;
      return {
        id: String(c._id),
        participants: (c.participants || []).map(String),
        isGroup: c.isGroup === true,
        title: c.title || '',
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
        archived: _isArchivedFor(c, userId),
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

  await _assertEmployeeMayStartConversationWithAdmin(req.user);
  await _assertCanChat(req.user, otherUserId);

  const convo = await _findOrCreateConversation(req.user._id, otherUserId);
  res.status(200).json({ id: String(convo._id) });
});

// @desc    List online admins (for employee CTA)
// @route   GET /api/chat/admins/online
// @access  Private
const listOnlineAdmins = asyncHandler(async (req, res) => {
  const admins = await User.find({ role: 'admin', isOnline: true, isActive: true })
    .select('_id name employeeId email phone role avatarUrl isOnline')
    .limit(50)
    .lean();

  res.json(
    (admins || []).map((a) => ({
      id: String(a._id),
      name: a.name,
      employeeId: a.employeeId,
      email: a.email,
      phone: a.phone,
      role: a.role,
      avatarUrl: a.avatarUrl,
      isOnline: a.isOnline === true,
    })),
  );
});

// @desc    Archive conversation for current user
// @route   POST /api/chat/conversations/:id/archive
// @access  Private
const archiveConversation = asyncHandler(async (req, res) => {
  const convoId = _asId(req.params.id);
  if (!convoId) {
    res.status(400);
    throw new Error('Invalid conversation id');
  }

  const convo = await Conversation.findById(convoId).select('participants isGroup').lean();
  if (!convo) {
    res.status(404);
    throw new Error('Conversation not found');
  }

  const userId = String(req.user._id);
  if (!(convo.participants || []).map(String).includes(userId)) {
    res.status(403);
    throw new Error('Not allowed');
  }

  // Employees cannot archive group chats.
  if (req.user.role === 'employee' && convo.isGroup === true) {
    res.status(403);
    throw new Error('Not allowed');
  }

  await Conversation.findByIdAndUpdate(convoId, {
    $pull: { deletedBy: { userId: req.user._id } },
    $addToSet: { archivedBy: { userId: req.user._id, at: new Date() } },
  });

  res.json({ ok: true });
});

// @desc    Unarchive conversation for current user
// @route   POST /api/chat/conversations/:id/unarchive
// @access  Private
const unarchiveConversation = asyncHandler(async (req, res) => {
  const convoId = _asId(req.params.id);
  if (!convoId) {
    res.status(400);
    throw new Error('Invalid conversation id');
  }

  const convo = await Conversation.findById(convoId).select('participants isGroup').lean();
  if (!convo) {
    res.status(404);
    throw new Error('Conversation not found');
  }

  const userId = String(req.user._id);
  if (!(convo.participants || []).map(String).includes(userId)) {
    res.status(403);
    throw new Error('Not allowed');
  }

  if (req.user.role === 'employee' && convo.isGroup === true) {
    res.status(403);
    throw new Error('Not allowed');
  }

  await Conversation.findByIdAndUpdate(convoId, {
    $pull: { archivedBy: { userId: req.user._id } },
  });

  res.json({ ok: true });
});

// @desc    Delete (hide) conversation for current user
// @route   POST /api/chat/conversations/:id/delete
// @access  Private
const deleteConversation = asyncHandler(async (req, res) => {
  const convoId = _asId(req.params.id);
  if (!convoId) {
    res.status(400);
    throw new Error('Invalid conversation id');
  }

  const convo = await Conversation.findById(convoId).select('participants isGroup').lean();
  if (!convo) {
    res.status(404);
    throw new Error('Conversation not found');
  }

  const userId = String(req.user._id);
  if (!(convo.participants || []).map(String).includes(userId)) {
    res.status(403);
    throw new Error('Not allowed');
  }

  // Employees cannot delete group chats.
  if (req.user.role === 'employee' && convo.isGroup === true) {
    res.status(403);
    throw new Error('Not allowed');
  }

  await Conversation.findByIdAndUpdate(convoId, {
    $pull: { archivedBy: { userId: req.user._id } },
    $addToSet: { deletedBy: { userId: req.user._id, at: new Date() } },
  });

  res.json({ ok: true });
});

// @desc    Create a group conversation (admin only)
// @route   POST /api/chat/group-conversations
// @access  Private/Admin
const createGroupConversation = asyncHandler(async (req, res) => {
  const title = (req.body?.title || '').toString().trim();
  const raw = Array.isArray(req.body?.participantUserIds)
    ? req.body.participantUserIds
    : [];
  const participantIds = raw
    .map(_asId)
    .filter((v) => v)
    .map(String);

  if (!title) {
    res.status(400);
    throw new Error('title is required');
  }
  if (participantIds.length < 1) {
    res.status(400);
    throw new Error('participantUserIds must have at least 1 user');
  }

  // validate users exist
  const users = await User.find({ _id: { $in: participantIds }, isActive: true })
    .select('_id')
    .lean();
  if (users.length !== participantIds.length) {
    res.status(400);
    throw new Error('One or more participants are invalid');
  }

  const allParticipants = Array.from(
    new Set([String(req.user._id), ...participantIds].filter((v) => v)),
  );
  if (allParticipants.length < 2) {
    res.status(400);
    throw new Error('Group conversation must have at least 2 participants');
  }

  const convo = await Conversation.create({
    participants: allParticipants,
    isGroup: true,
    title,
    createdBy: req.user._id,
    lastMessageAt: null,
    lastMessagePreview: '',
  });

  res.status(201).json({ id: String(convo._id) });
});

async function _assertAdminMayManageGroup(reqUser, convoId) {
  const convo = await Conversation.findById(convoId)
    .select('isGroup createdBy participants')
    .lean();
  if (!convo) {
    const err = new Error('Conversation not found');
    err.statusCode = 404;
    throw err;
  }
  if (convo.isGroup !== true) {
    const err = new Error('Not a group conversation');
    err.statusCode = 400;
    throw err;
  }
  if (String(convo.createdBy || '') !== String(reqUser._id)) {
    const err = new Error('Only the creating admin may manage this group');
    err.statusCode = 403;
    throw err;
  }
  return convo;
}

// @desc    Add group members (admin only)
// @route   POST /api/chat/group-conversations/:id/members/add
// @access  Private/Admin
const addGroupMembers = asyncHandler(async (req, res) => {
  const convoId = _asId(req.params.id);
  if (!convoId) {
    res.status(400);
    throw new Error('Invalid conversation id');
  }

  await _assertAdminMayManageGroup(req.user, convoId);

  const raw = Array.isArray(req.body?.userIds) ? req.body.userIds : [];
  const ids = raw.map(_asId).filter((v) => v).map(String);
  if (ids.length === 0) {
    res.status(400);
    throw new Error('userIds is required');
  }

  const users = await User.find({ _id: { $in: ids }, isActive: true })
    .select('_id role')
    .lean();
  if (users.length !== ids.length) {
    res.status(400);
    throw new Error('One or more users are invalid');
  }
  const bad = users.find((u) => u.role !== 'employee');
  if (bad) {
    res.status(400);
    throw new Error('Group conversations can only include employees');
  }

  await Conversation.findByIdAndUpdate(convoId, {
    $addToSet: { participants: { $each: ids } },
  });

  res.json({ ok: true });
});

// @desc    Remove group members (admin only)
// @route   POST /api/chat/group-conversations/:id/members/remove
// @access  Private/Admin
const removeGroupMembers = asyncHandler(async (req, res) => {
  const convoId = _asId(req.params.id);
  if (!convoId) {
    res.status(400);
    throw new Error('Invalid conversation id');
  }

  const convo = await _assertAdminMayManageGroup(req.user, convoId);

  const raw = Array.isArray(req.body?.userIds) ? req.body.userIds : [];
  const ids = raw.map(_asId).filter((v) => v).map(String);
  if (ids.length === 0) {
    res.status(400);
    throw new Error('userIds is required');
  }

  // employees only
  const users = await User.find({ _id: { $in: ids }, isActive: true })
    .select('_id role')
    .lean();
  if (users.length !== ids.length) {
    res.status(400);
    throw new Error('One or more users are invalid');
  }
  const bad = users.find((u) => u.role !== 'employee');
  if (bad) {
    res.status(400);
    throw new Error('Group conversations can only include employees');
  }

  const currentParticipants = (convo.participants || []).map(String);
  const nextParticipants = currentParticipants.filter((p) => !ids.includes(p));

  if (nextParticipants.length <= 1) {
    // prevent dangling groups by making it invisible (admin-only archive + delete)
    await Conversation.findByIdAndUpdate(convoId, {
      $set: { participants: nextParticipants },
      $addToSet: {
        archivedBy: { userId: req.user._id, at: new Date() },
        deletedBy: { userId: req.user._id, at: new Date() },
      },
    });
    res.json({ ok: true, archived: true, reason: 'group_size_too_small' });
    return;
  }

  await Conversation.findByIdAndUpdate(convoId, {
    $set: { participants: nextParticipants },
  });

  res.json({ ok: true });
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

  const convo = await Conversation.findById(convoId)
    .select('participants isGroup title')
    .lean();
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

  // enforce rules
  if (convo.isGroup === true) {
    // group chats: any participant (admin/employee) may send
  } else {
    // 1:1 must be admin<->employee
    const otherId = participants.find((p) => p !== userId);
    if (!otherId) {
      res.status(400);
      throw new Error('Invalid conversation');
    }
    await _assertCanChat(req.user, otherId);
  }

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

  // Persist notifications + Emit realtime event to all participants except sender
  const recipients = participants.filter((p) => p !== userId);

  let senderName = req.user?.name;
  let senderEmployeeId = req.user?.employeeId;
  let senderRole = req.user?.role;
  if (!senderName || senderEmployeeId === undefined || !senderRole) {
    try {
      const sender = await User.findById(req.user._id)
        .select('name employeeId role')
        .lean();
      if (sender) {
        senderName = senderName || sender.name;
        if (senderEmployeeId === undefined) senderEmployeeId = sender.employeeId;
        senderRole = senderRole || sender.role;
      }
    } catch (_) {}
  }

  const senderLabel = (() => {
    const name = (senderName || 'User').toString().trim();
    const emp = (senderEmployeeId || '').toString().trim();
    if (emp) return `${name} (${emp})`;
    if (senderRole && String(senderRole).toLowerCase() === 'admin') return `${name} (Admin)`;
    return name;
  })();

  const groupTitle = (convo.title || '').toString().trim();
  const notificationTitle =
    convo.isGroup === true
      ? `New message in ${groupTitle || 'Group chat'} from ${senderLabel}`
      : `New message from ${senderLabel}`;

  for (const rid of recipients) {
    try {
      await appNotificationService.createNotification({
        recipientUserId: rid,
        scope: 'messages',
        type: 'info',
        action: 'chatMessage',
        title: notificationTitle,
        message: preview,
        payload: {
          conversationId: String(convoId),
          senderUserId: userId,
          senderName: (senderName || '').toString(),
          senderEmployeeId: (senderEmployeeId || '').toString(),
          isGroup: convo.isGroup === true,
          groupTitle: groupTitle,
        },
      });
    } catch (_) {}
  }

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
      for (const rid of recipients) {
        io.to(`user:${rid}`).emit('chatMessage', payload);
      }
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
  listOnlineAdmins,
  listMessages,
  sendMessage,
  markConversationRead,
  archiveConversation,
  unarchiveConversation,
  deleteConversation,
  createGroupConversation,
  addGroupMembers,
  removeGroupMembers,
};
