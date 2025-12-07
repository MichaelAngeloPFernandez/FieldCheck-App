const asyncHandler = require('express-async-handler');
const User = require('../models/User');
const notificationService = require('../services/notificationService');

// @desc Send urgent SMS notification to users
// @route POST /api/notifications/urgent
// @access Private/Admin
const sendUrgentNotification = asyncHandler(async (req, res) => {
  const body = req.body || {};
  let { message, roles, userIds } = body;

  if (!message || typeof message !== 'string' || !message.trim()) {
    res.status(400);
    throw new Error('message is required');
  }

  message = message.toString().trim();
  if (message.length > 320) {
    message = message.slice(0, 320);
  }

  const baseFilter = {
    isActive: true,
    phone: { $exists: true, $ne: '' },
  };

  const filter = { ...baseFilter };

  if (Array.isArray(userIds) && userIds.length > 0) {
    filter._id = { $in: userIds };
  } else if (Array.isArray(roles) && roles.length > 0) {
    filter.role = { $in: roles };
  } else {
    // Default: all employees
    filter.role = 'employee';
  }

  const users = await User.find(filter).select('phone');

  if (!users.length) {
    return res.status(200).json({ sent: 0, targets: [] });
  }

  const smsBody = `[URGENT] ${message}`;
  await Promise.all(
    users.map((u) => notificationService.sendSms(u.phone, smsBody))
  );

  res.status(200).json({
    sent: users.length,
  });
});

module.exports = {
  sendUrgentNotification,
};
