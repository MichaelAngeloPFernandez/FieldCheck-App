const asyncHandler = require('express-async-handler');
const User = require('../models/User');
const notificationService = require('../services/notificationService');
const sendEmail = require('../utils/emailService');
const appNotificationService = require('../services/appNotificationService');

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

// @desc Send task assignment SMS
// @route POST /api/notifications/task-assignment
// @access Private/Admin
const sendTaskAssignmentSms = asyncHandler(async (req, res) => {
  const { employeeId, taskTitle, taskDescription, message } = req.body;

  if (!employeeId || !taskTitle) {
    res.status(400);
    throw new Error('employeeId and taskTitle are required');
  }

  const user = await User.findById(employeeId).select('phone name');
  if (!user || !user.phone) {
    return res.status(404).json({ error: 'Employee not found or no phone number' });
  }

  const smsBody = message || `New Task: ${taskTitle}. Check your app for details.`;
  await notificationService.sendSms(user.phone, smsBody);

  res.status(200).json({
    sent: 1,
    employeeName: user.name,
    employeePhone: user.phone,
  });
});

// @desc Send overdue task SMS
// @route POST /api/notifications/overdue-task
// @access Private/Admin
const sendOverdueTaskSms = asyncHandler(async (req, res) => {
  const { employeeId, taskTitle, hoursOverdue, message } = req.body;

  if (!employeeId || !taskTitle || hoursOverdue === undefined) {
    res.status(400);
    throw new Error('employeeId, taskTitle, and hoursOverdue are required');
  }

  const user = await User.findById(employeeId).select('phone name');
  if (!user || !user.phone) {
    return res.status(404).json({ error: 'Employee not found or no phone number' });
  }

  const smsBody = message || `URGENT: Task "${taskTitle}" is ${hoursOverdue} hours overdue. Please complete immediately.`;
  await notificationService.sendSms(user.phone, smsBody);

  res.status(200).json({
    sent: 1,
    employeeName: user.name,
  });
});

// @desc Send attendance confirmation SMS
// @route POST /api/notifications/attendance
// @access Private
const sendAttendanceSms = asyncHandler(async (req, res) => {
  const { employeeId, isCheckIn, geofenceName, timestamp, message } = req.body;

  if (!employeeId || geofenceName === undefined) {
    res.status(400);
    throw new Error('employeeId and geofenceName are required');
  }

  const user = await User.findById(employeeId).select('phone name');
  if (!user || !user.phone) {
    return res.status(200).json({ sent: 0, reason: 'No phone number' });
  }

  const action = isCheckIn ? 'Checked In' : 'Checked Out';
  const smsBody = message || `${action} at ${geofenceName}. Your attendance has been recorded.`;
  await notificationService.sendSms(user.phone, smsBody);

  res.status(200).json({
    sent: 1,
    employeeName: user.name,
  });
});

// @desc Send workload warning SMS
// @route POST /api/notifications/workload-warning
// @access Private/Admin
const sendWorkloadWarningSms = asyncHandler(async (req, res) => {
  const { employeeId, activeTaskCount, difficultyWeight, message } = req.body;

  if (!employeeId || activeTaskCount === undefined || difficultyWeight === undefined) {
    res.status(400);
    throw new Error('employeeId, activeTaskCount, and difficultyWeight are required');
  }

  const user = await User.findById(employeeId).select('phone name');
  if (!user || !user.phone) {
    return res.status(404).json({ error: 'Employee not found or no phone number' });
  }

  const smsBody = message || `Workload Alert: You have ${activeTaskCount} active tasks. Consider completing some or requesting help.`;
  await notificationService.sendSms(user.phone, smsBody);

  res.status(200).json({
    sent: 1,
    employeeName: user.name,
  });
});

// @desc Send escalation SMS
// @route POST /api/notifications/escalation
// @access Private/Admin
const sendEscalationSms = asyncHandler(async (req, res) => {
  const { employeeId, taskTitle, escalationReason, message } = req.body;

  if (!employeeId || !taskTitle) {
    res.status(400);
    throw new Error('employeeId and taskTitle are required');
  }

  const user = await User.findById(employeeId).select('phone name');
  if (!user || !user.phone) {
    return res.status(404).json({ error: 'Employee not found or no phone number' });
  }

  const smsBody = message || `ESCALATION: Task "${taskTitle}" has been escalated. Please respond immediately.`;
  await notificationService.sendSms(user.phone, smsBody);

  res.status(200).json({
    sent: 1,
    employeeName: user.name,
  });
});

// @desc Send location warning SMS
// @route POST /api/notifications/location-warning
// @access Private
const sendLocationWarningSms = asyncHandler(async (req, res) => {
  const { employeeId, reason, message } = req.body;

  if (!employeeId) {
    res.status(400);
    throw new Error('employeeId is required');
  }

  const user = await User.findById(employeeId).select('phone name');
  if (!user || !user.phone) {
    return res.status(200).json({ sent: 0, reason: 'No phone number' });
  }

  const smsBody = message || `Location Verification Failed: ${reason || 'Unknown reason'}. Please verify your GPS is enabled.`;
  await notificationService.sendSms(user.phone, smsBody);

  res.status(200).json({
    sent: 1,
    employeeName: user.name,
  });
});

// @desc Send batch SMS to multiple employees
// @route POST /api/notifications/batch
// @access Private/Admin
const sendBatchSms = asyncHandler(async (req, res) => {
  const { employeeIds, message, notificationType } = req.body;

  if (!Array.isArray(employeeIds) || !employeeIds.length || !message) {
    res.status(400);
    throw new Error('employeeIds array and message are required');
  }

  if (message.length > 320) {
    res.status(400);
    throw new Error('Message exceeds 320 characters');
  }

  const users = await User.find({ _id: { $in: employeeIds }, phone: { $exists: true, $ne: '' } }).select('phone name');

  if (!users.length) {
    return res.status(200).json({ sent: 0, reason: 'No users with phone numbers found' });
  }

  await Promise.all(
    users.map((u) => notificationService.sendSms(u.phone, message))
  );

  res.status(200).json({
    sent: users.length,
    notificationType,
    recipients: users.map(u => ({ id: u._id, name: u.name })),
  });
});

module.exports = {
  sendUrgentNotification,
  // Multichannel (email + in-app) urgent announcement
  sendUrgentMultichannel: asyncHandler(async (req, res) => {
    const body = req.body || {};
    let { message, sendEmail: doEmail, sendInApp, recipientMode } = body;

    if (!message || typeof message !== 'string' || !message.trim()) {
      res.status(400);
      throw new Error('message is required');
    }

    message = message.toString().trim();
    if (message.length > 320) {
      message = message.slice(0, 320);
    }

    const emailEnabled = doEmail === true;
    const inAppEnabled = sendInApp !== false;

    const mode = (recipientMode || 'all_with_numbers_and_emails').toString();
    const base = { role: 'employee', isActive: true };

    const query = { ...base };
    if (mode === 'all_with_emails') {
      query.email = { $exists: true, $ne: '' };
    } else if (mode === 'all_with_numbers') {
      query.phone = { $exists: true, $ne: '' };
    } else {
      // all_with_numbers_and_emails
      query.$or = [
        { phone: { $exists: true, $ne: '' } },
        { email: { $exists: true, $ne: '' } },
      ];
    }

    const users = await User.find(query).select('_id name email phone');
    if (!users.length) {
      return res
        .status(200)
        .json({ targets: 0, email: { attempted: 0, sent: 0, failed: 0 }, inApp: { created: 0 } });
    }

    // Create in-app notifications first (this should be fast and ensures the bell updates).
    let inAppCreated = 0;
    if (inAppEnabled) {
      for (const u of users) {
        try {
          await appNotificationService.createNotification({
            recipientUserId: u._id,
            scope: 'announcements',
            type: 'warning',
            action: 'urgent',
            title: 'Urgent announcement',
            message,
            payload: {},
          });
          inAppCreated += 1;
        } catch (_) {}
      }
    }

    // Respond immediately to avoid client/Render timeouts.
    // Email delivery will be attempted in the background and may fail due to SMTP network restrictions.
    let emailAttempted = 0;
    for (const u of users) {
      const to = (u.email || '').toString().trim();
      if (!to) continue;
      emailAttempted += 1;
    }

    res.status(200).json({
      targets: users.length,
      email: {
        attempted: emailAttempted,
        sent: 0,
        failed: 0,
        status: emailEnabled ? 'queued' : 'disabled',
      },
      inApp: { created: inAppCreated },
    });

    if (emailEnabled) {
      const subject = 'FieldCheck: Urgent announcement';
      setImmediate(async () => {
        for (const u of users) {
          const to = (u.email || '').toString().trim();
          if (!to) continue;
          try {
            await sendEmail({
              email: to,
              subject,
              message: `<p><strong>[URGENT]</strong> ${message}</p>`,
            });
          } catch (_) {
            // Errors are logged by emailService; do not throw.
          }
        }
      });
    }
  }),
  sendTaskAssignmentSms,
  sendOverdueTaskSms,
  sendAttendanceSms,
  sendWorkloadWarningSms,
  sendEscalationSms,
  sendLocationWarningSms,
  sendBatchSms,
};
