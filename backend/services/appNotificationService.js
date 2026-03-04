const AppNotification = require('../models/AppNotification');
const User = require('../models/User');

async function getUnreadCountsForUser(userId) {
  const [tasks, adminFeed] = await Promise.all([
    AppNotification.countDocuments({ recipientUser: userId, scope: 'tasks', readAt: null }),
    AppNotification.countDocuments({ recipientUser: userId, scope: 'adminFeed', readAt: null }),
  ]);

  return {
    tasks,
    adminFeed,
    total: tasks + adminFeed,
  };
}

async function emitUnreadCounts(userId) {
  try {
    const io = global.io;
    if (!io) return;

    const counts = await getUnreadCountsForUser(userId);
    io.to(`user:${String(userId)}`).emit('unreadCounts', counts);
  } catch (_) {}
}

async function emitUnreadNotifications(userId, { scope, limit } = {}) {
  try {
    const io = global.io;
    if (!io) return;

    const cleanUserId = String(userId || '').trim();
    if (cleanUserId.length !== 24) return;

    const q = { recipientUser: cleanUserId, readAt: null };
    if (scope) {
      q.scope = String(scope);
    }

    const n =
      typeof limit === 'number' && Number.isFinite(limit)
        ? Math.max(1, Math.min(50, limit))
        : 20;

    const items = await AppNotification.find(q)
      .sort({ createdAt: -1 })
      .limit(n)
      .lean();

    if (!items.length) return;

    for (const doc of items.reverse()) {
      io.to(`user:${cleanUserId}`).emit('notificationCreated', {
        id: String(doc._id),
        scope: doc.scope,
        type: doc.type,
        action: doc.action,
        title: doc.title,
        message: doc.message,
        payload: doc.payload,
        createdAt: doc.createdAt?.toISOString?.() || new Date().toISOString(),
        readAt: null,
        replay: true,
      });
    }
  } catch (_) {}
}

async function createNotification({
  recipientUserId,
  scope,
  type,
  action,
  title,
  message,
  payload,
}) {
  const doc = await AppNotification.create({
    recipientUser: recipientUserId,
    scope,
    type: type || 'info',
    action: action || 'info',
    title: title || 'Notification',
    message: message || '',
    payload: payload || {},
  });

  try {
    const io = global.io;
    if (io) {
      io.to(`user:${String(recipientUserId)}`).emit('notificationCreated', {
        id: doc._id.toString(),
        scope: doc.scope,
        type: doc.type,
        action: doc.action,
        title: doc.title,
        message: doc.message,
        payload: doc.payload,
        createdAt: doc.createdAt?.toISOString?.() || new Date().toISOString(),
        readAt: null,
      });
    }
  } catch (_) {}

  await emitUnreadCounts(recipientUserId);

  return doc;
}

async function createForAdmins({
  excludeUserId,
  type,
  action,
  title,
  message,
  payload,
}) {
  const admins = await User.find({ role: 'admin', isActive: { $ne: false } }).select('_id');
  const ids = admins
    .map((u) => u._id)
    .filter((id) => !excludeUserId || String(id) !== String(excludeUserId));

  if (!ids.length) return [];

  const created = [];
  for (const adminId of ids) {
    created.push(
      await createNotification({
        recipientUserId: adminId,
        scope: 'adminFeed',
        type: type || 'info',
        action: action || 'info',
        title: title || 'Notification',
        message: message || '',
        payload: payload || {},
      }),
    );
  }

  return created;
}

module.exports = {
  getUnreadCountsForUser,
  emitUnreadCounts,
  emitUnreadNotifications,
  createNotification,
  createForAdmins,
};
