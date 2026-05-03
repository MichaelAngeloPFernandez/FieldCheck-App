const AppNotification = require('../models/AppNotification');
const User = require('../models/User');

async function getUnreadCountsForUser(userId) {
  const [tasks, adminFeed, announcements, geofences, messages] = await Promise.all([
    AppNotification.countDocuments({ recipientUser: userId, scope: 'tasks', readAt: null }),
    AppNotification.countDocuments({ recipientUser: userId, scope: 'adminFeed', readAt: null }),
    AppNotification.countDocuments({ recipientUser: userId, scope: 'announcements', readAt: null }),
    AppNotification.countDocuments({ recipientUser: userId, scope: 'geofences', readAt: null }),
    AppNotification.countDocuments({ recipientUser: userId, scope: 'messages', readAt: null }),
  ]);

  return {
    tasks,
    adminFeed,
    announcements,
    geofences,
    messages,
    total: tasks + adminFeed + announcements + geofences + messages,
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
  
  // Additional methods for notification management
  async getNotificationsByScope(userId, scope, { limit = 50, offset = 0 } = {}) {
    try {
      const query = { recipientUser: userId };
      if (scope) {
        query.scope = scope;
      }

      const notifications = await AppNotification.find(query)
        .sort({ createdAt: -1 })
        .limit(parseInt(limit))
        .skip(parseInt(offset))
        .lean();

      return notifications.map(n => ({
        id: String(n._id),
        scope: n.scope,
        type: n.type,
        action: n.action,
        title: n.title,
        message: n.message,
        payload: n.payload,
        isRead: !!n.readAt,
        createdAt: n.createdAt?.toISOString?.() || new Date().toISOString(),
        readAt: n.readAt?.toISOString?.() || null,
      }));
    } catch (error) {
      console.error('Error fetching notifications:', error);
      return [];
    }
  },

  async markNotificationAsRead(notificationId, userId) {
    try {
      const notification = await AppNotification.findOneAndUpdate(
        { _id: notificationId, recipientUser: userId },
        { readAt: new Date() },
        { new: true }
      );

      if (notification) {
        await this.emitUnreadCounts(userId);
        const io = global.io;
        if (io) {
          io.to(`user:${String(userId)}`).emit('notificationRead', {
            id: String(notification._id),
          });
        }
      }

      return notification;
    } catch (error) {
      console.error('Error marking notification as read:', error);
      return null;
    }
  },

  async markNotificationAsUnread(notificationId, userId) {
    try {
      const notification = await AppNotification.findOneAndUpdate(
        { _id: notificationId, recipientUser: userId },
        { readAt: null },
        { new: true }
      );

      if (notification) {
        await this.emitUnreadCounts(userId);
      }

      return notification;
    } catch (error) {
      console.error('Error marking notification as unread:', error);
      return null;
    }
  },

  async markScopeAsRead(userId, scope) {
    try {
      const query = { recipientUser: userId, readAt: null };
      if (scope) {
        query.scope = scope;
      }

      const result = await AppNotification.updateMany(query, { readAt: new Date() });

      if (result.modifiedCount > 0) {
        await this.emitUnreadCounts(userId);
        const io = global.io;
        if (io) {
          io.to(`user:${String(userId)}`).emit('scopeMarkedAsRead', { scope });
        }
      }

      return result;
    } catch (error) {
      console.error('Error marking scope as read:', error);
      return null;
    }
  },

  async deleteNotification(notificationId, userId) {
    try {
      const notification = await AppNotification.findOneAndDelete({
        _id: notificationId,
        recipientUser: userId,
      });

      if (notification) {
        await this.emitUnreadCounts(userId);
        const io = global.io;
        if (io) {
          io.to(`user:${String(userId)}`).emit('notificationDeleted', {
            id: String(notificationId),
          });
        }
      }

      return notification;
    } catch (error) {
      console.error('Error deleting notification:', error);
      return null;
    }
  },

  async deleteNotificationsByScope(userId, scope) {
    try {
      const query = { recipientUser: userId };
      if (scope) {
        query.scope = scope;
      }

      const result = await AppNotification.deleteMany(query);

      if (result.deletedCount > 0) {
        await this.emitUnreadCounts(userId);
        const io = global.io;
        if (io) {
          io.to(`user:${String(userId)}`).emit('scopeNotificationsDeleted', { scope });
        }
      }

      return result;
    } catch (error) {
      console.error('Error deleting notifications by scope:', error);
      return null;
    }
  },

  async getNotificationCount(userId, scope) {
    try {
      const query = { recipientUser: userId };
      if (scope) {
        query.scope = scope;
      }

      const count = await AppNotification.countDocuments(query);
      return count;
    } catch (error) {
      console.error('Error getting notification count:', error);
      return 0;
    }
  },
};
