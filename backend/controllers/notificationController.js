const asyncHandler = require('express-async-handler');
const User = require('../models/User');
const sendEmail = require('../utils/emailService');
const appNotificationService = require('../services/appNotificationService');

module.exports = {
  // Multichannel (email + in-app) urgent announcement
  sendUrgentMultichannel: asyncHandler(async (req, res) => {
    const body = req.body || {};
    let { message, sendEmail: doEmail, sendInApp, recipientMode, employeeId } = body;

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

    const mode = (recipientMode || 'all').toString();
    const base = { role: 'employee', isActive: true };

    const query = { ...base };
    if (mode === 'single_employee') {
      const id = (employeeId || '').toString().trim();
      if (!id) {
        res.status(400);
        throw new Error('employeeId is required for single_employee');
      }
      query._id = id;
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
};
