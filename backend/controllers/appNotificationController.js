const asyncHandler = require('express-async-handler');
const AppNotification = require('../models/AppNotification');
const appNotificationService = require('../services/appNotificationService');

// @desc    Get unread counts for the current user
// @route   GET /api/app-notifications/unread-count
// @access  Private
const getUnreadCount = asyncHandler(async (req, res) => {
  const counts = await appNotificationService.getUnreadCountsForUser(req.user._id);
  res.json(counts);
});

// @desc    List notifications for the current user
// @route   GET /api/app-notifications
// @access  Private
const listNotifications = asyncHandler(async (req, res) => {
  const scope = (req.query.scope || '').toString().trim();
  const unreadOnly = String(req.query.unreadOnly || 'false').toLowerCase() === 'true';
  const limitRaw = parseInt(String(req.query.limit || '50'), 10);
  const pageRaw = parseInt(String(req.query.page || '1'), 10);

  const limit = Number.isFinite(limitRaw) ? Math.max(1, Math.min(100, limitRaw)) : 50;
  const page = Number.isFinite(pageRaw) ? Math.max(1, pageRaw) : 1;
  const skip = (page - 1) * limit;

  const filter = { recipientUser: req.user._id };
  if (scope) {
    filter.scope = scope;
  }
  if (unreadOnly) {
    filter.readAt = null;
  }

  const items = await AppNotification.find(filter)
    .sort({ createdAt: -1 })
    .skip(skip)
    .limit(limit);

  res.json(
    items.map((n) => ({
      id: n._id.toString(),
      scope: n.scope,
      type: n.type,
      action: n.action,
      title: n.title,
      message: n.message,
      payload: n.payload,
      createdAt: n.createdAt?.toISOString?.() || null,
      readAt: n.readAt?.toISOString?.() || null,
    })),
  );
});

// @desc    Mark notifications as read by IDs
// @route   POST /api/app-notifications/mark-read
// @access  Private
const markRead = asyncHandler(async (req, res) => {
  const ids = Array.isArray(req.body?.ids) ? req.body.ids : [];
  const clean = ids
    .map((id) => String(id || '').trim())
    .filter((id) => id.length === 24);

  if (!clean.length) {
    return res.json({ updated: 0 });
  }

  const result = await AppNotification.updateMany(
    { recipientUser: req.user._id, _id: { $in: clean }, readAt: null },
    { $set: { readAt: new Date() } },
  );

  await appNotificationService.emitUnreadCounts(req.user._id);

  res.json({
    updated:
      typeof result.modifiedCount === 'number'
        ? result.modifiedCount
        : typeof result.nModified === 'number'
          ? result.nModified
          : 0,
  });
});

// @desc    Mark notifications as read by scope
// @route   POST /api/app-notifications/mark-read-scope
// @access  Private
const markReadScope = asyncHandler(async (req, res) => {
  const scope = (req.body?.scope || '').toString().trim();
  if (!scope) {
    res.status(400);
    throw new Error('scope is required');
  }

  const result = await AppNotification.updateMany(
    { recipientUser: req.user._id, scope, readAt: null },
    { $set: { readAt: new Date() } },
  );

  await appNotificationService.emitUnreadCounts(req.user._id);

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
  getUnreadCount,
  listNotifications,
  markRead,
  markReadScope,
};
