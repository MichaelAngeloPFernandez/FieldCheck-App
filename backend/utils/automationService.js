/**
 * Automation Service
 * Handles automated tasks like:
 * - Deleting unverified users after 24 hours
 * - Cleanup of expired verification tokens
 * - Scheduling email reminders
 */

const cron = require('node-cron');
const User = require('../models/User');
const Task = require('../models/Task');
const UserTask = require('../models/UserTask');
const Attendance = require('../models/Attendance');
const Report = require('../models/Report');
const Settings = require('../models/Settings');
const notificationService = require('../services/notificationService');

async function populateReportById(reportId) {
  return await Report.findById(reportId)
    .populate('employee', 'name email employeeId avatarUrl')
    .populate('task', 'title description difficulty dueDate status isArchived')
    .populate('attendance')
    .populate('geofence', 'name');
}

// Run daily cleanup at 2 AM (UTC)
// Format: '0 2 * * *' = every day at 02:00
const CLEANUP_SCHEDULE = '0 2 * * *';

// Check for overdue tasks every 15 minutes
const OVERDUE_TASK_SCHEDULE = '*/15 * * * *';

// Auto-checkout scan: check offline employees every 5 minutes
const AUTO_CHECKOUT_SCHEDULE = '*/5 * * * *';

// Auto-checkout thresholds (minutes) - default values
const AUTO_CHECKOUT_WARNING_MINUTES = 25;
const AUTO_CHECKOUT_MINUTES = 30;

// Alternatively, for testing: run every 1 minute
// const CLEANUP_SCHEDULE = '* * * * *';

let cleanupJobActive = false;

/**
 * Delete users who registered but haven't verified email after 24 hours
 */
const cleanupUnverifiedUsers = async () => {
  try {
    if (cleanupJobActive) {
      console.log('⏳ Cleanup already running, skipping...');
      return;
    }

    cleanupJobActive = true;
    console.log('🧹 Starting unverified user cleanup...');

    const twentyFourHoursAgo = new Date(Date.now() - 24 * 60 * 60 * 1000);

    const result = await User.deleteMany({
      isVerified: false,
      createdAt: { $lt: twentyFourHoursAgo },
    });

    console.log(`✅ Cleanup complete: Deleted ${result.deletedCount} unverified users`);

    cleanupJobActive = false;
  } catch (error) {
    console.error('❌ Cleanup failed:', error.message);
    cleanupJobActive = false;
  }
};

/**
 * Load per-employee auto-checkout config from Settings collection.
 * Key: `employeeCheckout.<employeeId>`
 * Value shape: { autoCheckoutMinutes: number, maxTasksPerDay: number, autoCheckoutEnabled: bool }
 */
const getEmployeeCheckoutConfig = async (employeeId) => {
  try {
    const key = `employeeCheckout.${String(employeeId)}`;
    const setting = await Settings.findOne({ key });
    if (!setting || !setting.value) return null;
    return setting.value;
  } catch (e) {
    console.error('getEmployeeCheckoutConfig failed:', e.message || e);
    return null;
  }
};

/**
 * Auto-checkout employees who have been offline for too long
 * Default rule:
 *  - At 25 minutes offline: send warning (once)
 *  - At 30+ minutes offline: auto-checkout and void attendance
 * Per-employee overrides are loaded from Settings if present.
 */
const autoCheckoutOfflineEmployees = async () => {
  try {
    const now = new Date();

    // Find all open attendance records (no checkout, not voided)
    const openRecords = await Attendance.find({
      checkOut: { $exists: false },
      isVoid: { $ne: true },
    }).populate('employee', 'name lastLocationUpdate isOnline');

    if (!openRecords.length) {
      return;
    }

    for (const record of openRecords) {
      try {
        const employee = record.employee;
        if (!employee) continue;

        const lastLocationUpdate = employee.lastLocationUpdate;
        if (!lastLocationUpdate) continue;

        const diffMs = now.getTime() - new Date(lastLocationUpdate).getTime();
        const diffMinutes = diffMs / (60 * 1000);

        // Load per-employee configuration (if any)
        let autoMinutes = AUTO_CHECKOUT_MINUTES;
        let warningMinutes = AUTO_CHECKOUT_WARNING_MINUTES;
        let autoEnabled = true;

        try {
          const cfg = await getEmployeeCheckoutConfig(employee._id);
          if (cfg && typeof cfg === 'object') {
            if (
              Object.prototype.hasOwnProperty.call(cfg, 'autoCheckoutEnabled') &&
              cfg.autoCheckoutEnabled === false
            ) {
              autoEnabled = false;
            }
            if (
              Object.prototype.hasOwnProperty.call(cfg, 'autoCheckoutMinutes') &&
              typeof cfg.autoCheckoutMinutes === 'number' &&
              cfg.autoCheckoutMinutes > 0
            ) {
              autoMinutes = cfg.autoCheckoutMinutes;
            }
          }
        } catch (e) {
          console.error(
            'Error loading employee auto-checkout config:',
            e.message || e,
          );
        }

        // If auto-checkout disabled for this employee, skip
        if (!autoEnabled) {
          continue;
        }

        // Derive warning threshold as 5 minutes before auto-checkout (min 1)
        warningMinutes = Math.max(1, autoMinutes - 5);

        // Send warning once between warningMinutes and autoMinutes
        if (
          diffMinutes >= warningMinutes &&
          diffMinutes < autoMinutes &&
          !record.checkoutWarningSent
        ) {
          const minutesRemaining = Math.max(
            1,
            Math.round(autoMinutes - diffMinutes),
          );

          // Emit Socket.io warning event
          if (global.io) {
            global.io.emit('checkoutWarning', {
              employeeId: String(employee._id),
              employeeName: employee.name,
              minutesRemaining,
              message: `⚠️ You will be auto-checked out in ${minutesRemaining} minutes if you remain offline`,
              timestamp: now.toISOString(),
            });
          }

          // Optional: notification service (SMS/email) if configured
          try {
            if (notificationService.notifyAutoCheckoutWarning) {
              await notificationService.notifyAutoCheckoutWarning(
                employee,
                minutesRemaining,
              );
            }
          } catch (_) {}

          record.checkoutWarningSent = true;
          await record.save();
          console.log(
            `⚠️ Auto-checkout warning sent to ${employee.name} (${employee._id})`,
          );
        }

        // Auto-checkout at autoMinutes or more offline
        if (diffMinutes >= autoMinutes && !record.autoCheckout) {
          record.checkOut = now;
          record.status = 'out';
          record.isVoid = true;
          record.voidReason = 'Offline for extended period';
          record.autoCheckout = true;
          await record.save();

          await User.findByIdAndUpdate(employee._id, {
            isOnline: false,
            status: 'offline',
          });

          // Create attendance report
          try {
            const rep = await Report.create({
              type: 'attendance',
              attendance: record._id,
              employee: record.employee,
              geofence: record.geofence,
              content:
                'Attendance auto-checked out and voided (offline too long)',
            });
            if (global.io) {
              try {
                const populated = await populateReportById(rep._id);
                global.io.emit('newReport', populated || rep);
              } catch (_) {
                global.io.emit('newReport', rep);
              }
            }
          } catch (e) {
            console.error(
              'Failed to auto-create auto-checkout report (cron):',
              e.message || e,
            );
          }

          // Emit auto-checkout event
          if (global.io) {
            global.io.emit('employeeAutoCheckout', {
              employeeId: String(employee._id),
              employeeName: employee.name,
              reason: 'Offline for extended period',
              timestamp: now.toISOString(),
              isVoid: true,
            });
            global.io.emit('employeeOffline', {
              employeeId: String(employee._id),
              timestamp: now.toISOString(),
            });
          }

          console.log(
            `🔴 Auto-checkout (cron) for ${employee.name} (${employee._id})`,
          );
        }
      } catch (e) {
        console.error(
          'Error processing auto-checkout record:',
          e.message || e,
        );
      }
    }
  } catch (e) {
    console.error('autoCheckoutOfflineEmployees failed:', e.message || e);
  }
};

/**
 * Detect tasks that are overdue and notify assigned employees via SMS.
 * Uses the Task.overdueNotified flag to avoid duplicate notifications.
 */
const notifyOverdueTasks = async () => {
  try {
    const now = new Date();
    const overdueTasks = await Task.find({
      dueDate: { $lt: now },
      status: { $ne: 'completed' },
      isArchived: { $ne: true },
      overdueNotified: { $ne: true },
    });

    if (!overdueTasks.length) {
      return;
    }

    for (const task of overdueTasks) {
      try {
        const assignments = await UserTask.find({ taskId: task._id });
        if (!assignments.length) {
          continue;
        }

        const userIds = assignments.map((a) => a.userId);
        const users = await User.find({ _id: { $in: userIds } });

        await Promise.all(
          users.map((u) => notificationService.notifyTaskOverdue(u, task))
        );

        try {
          if (global.io) {
            global.io.emit('adminNotification', {
              type: 'task',
              action: 'overdue',
              taskId: String(task._id),
              taskTitle: task.title,
              dueDate: task.dueDate,
              severity: 'warning',
              timestamp: new Date().toISOString(),
              message: `Task "${task.title}" is now overdue.`,
            });
          }
        } catch (err) {
          console.error('Failed to emit admin overdue notification:', err.message || err);
        }

        try {
          const appNotificationService = require('../services/appNotificationService');
          await appNotificationService.createForAdmins({
            type: 'task',
            action: 'overdue',
            title: 'Task Overdue',
            message: `Task "${task.title}" is now overdue.`,
            payload: {
              taskId: String(task._id),
              taskTitle: task.title,
              dueDate: task.dueDate,
            },
          });
        } catch (_) {}

        task.overdueNotified = true;
        await task.save();
      } catch (e) {
        console.error('Error processing overdue task notification:', e.message || e);
      }
    }
  } catch (e) {
    console.error('notifyOverdueTasks failed:', e.message || e);
  }
};

/**
 * Delete users with expired verification tokens (regardless of createdAt)
 * Useful if someone still has an old account from before this service existed
 */
const cleanupExpiredTokens = async () => {
  try {
    console.log('🔍 Checking for expired verification tokens...');

    const result = await User.deleteMany({
      isVerified: false,
      verificationTokenExpires: { $lt: Date.now() },
    });

    if (result.deletedCount > 0) {
      console.log(`✅ Deleted ${result.deletedCount} users with expired tokens`);
    }
  } catch (error) {
    console.error('❌ Token cleanup failed:', error.message);
  }
};

/**
 * Initialize automation jobs
 * Call this in server.js after database is connected
 */
const initializeAutomation = () => {
  console.log('⚙️  Initializing automation jobs...');

  // Schedule main cleanup (delete unverified users after 24h)
  cron.schedule(CLEANUP_SCHEDULE, cleanupUnverifiedUsers, {
    scheduled: true,
    timezone: 'UTC',
  });

  console.log(`✅ Scheduled cleanup job: ${CLEANUP_SCHEDULE} UTC (2 AM daily)`);

  // Also run cleanup on startup (delayed by 10 seconds to ensure DB is ready)
  setTimeout(() => {
    console.log('🚀 Running initial cleanup on startup...');
    cleanupUnverifiedUsers();
    cleanupExpiredTokens();
  }, 10000);

  // Schedule overdue task checks
  cron.schedule(OVERDUE_TASK_SCHEDULE, notifyOverdueTasks, {
    scheduled: true,
    timezone: 'UTC',
  });
  console.log(
    `✅ Scheduled overdue task notifications: ${OVERDUE_TASK_SCHEDULE} (every 15 minutes)`,
  );

  // Schedule auto-checkout/offline scan
  cron.schedule(AUTO_CHECKOUT_SCHEDULE, autoCheckoutOfflineEmployees, {
    scheduled: true,
    timezone: 'UTC',
  });
  console.log(
    `✅ Scheduled auto-checkout scan: ${AUTO_CHECKOUT_SCHEDULE} (every 5 minutes)`,
  );
};

/**
 * Manual trigger for testing (call from admin endpoint if needed)
 */
const manualCleanup = async () => {
  console.log('🔨 Manual cleanup triggered...');
  await cleanupUnverifiedUsers();
  await cleanupExpiredTokens();
};

module.exports = {
  initializeAutomation,
  manualCleanup,
  cleanupUnverifiedUsers,
  cleanupExpiredTokens,
  notifyOverdueTasks,
  autoCheckoutOfflineEmployees,
};
