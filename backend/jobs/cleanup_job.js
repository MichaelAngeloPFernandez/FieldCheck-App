const cron = require('node-cron');
const AppNotification = require('../models/AppNotification');
const ChatMessage = require('../models/ChatMessage');
const Settings = require('../models/Settings');

/**
 * Periodically cleans up old notifications and messages based on Admin settings.
 * Runs every day at 1:00 AM.
 */
const initCleanupJob = () => {
  // schedule: '0 1 * * *' (Every day at 1:00 AM)
  // For testing/demo purposes, we could run it more often,
  // but daily is sufficient for a production-like environment.
  cron.schedule('0 1 * * *', async () => {
    console.log('[Cleanup Job] Starting daily data retention sweep...');
    try {
      // 1. Fetch relevant retention settings
      const settingsDocs = await Settings.find({
        key: { $in: ['autoDeleteNotifs', 'notifExpiryDays', 'autoDeleteMsgs', 'msgExpiryDays'] }
      }).lean();

      const settings = {};
      settingsDocs.forEach(s => { settings[s.key] = s.value; });

      const autoDeleteNotifs = settings.autoDeleteNotifs === true || settings.autoDeleteNotifs === 'true';
      const notifExpiryDays = parseInt(settings.notifExpiryDays) || 30;
      const autoDeleteMsgs = settings.autoDeleteMsgs === true || settings.autoDeleteMsgs === 'true';
      const msgExpiryDays = parseInt(settings.msgExpiryDays) || 30;

      // 2. Perform Notification Cleanup
      if (autoDeleteNotifs) {
        const threshold = new Date();
        threshold.setDate(threshold.getDate() - notifExpiryDays);
        
        const result = await AppNotification.deleteMany({
          createdAt: { $lt: threshold }
        });
        console.log(`[Cleanup Job] Deleted ${result.deletedCount} notifications older than ${notifExpiryDays} days.`);
      }

      // 3. Perform Message Cleanup
      if (autoDeleteMsgs) {
        const threshold = new Date();
        threshold.setDate(threshold.getDate() - msgExpiryDays);
        
        const result = await ChatMessage.deleteMany({
          createdAt: { $lt: threshold }
        });
        console.log(`[Cleanup Job] Deleted ${result.deletedCount} messages older than ${msgExpiryDays} days.`);
      }

      console.log('[Cleanup Job] Sweep completed successfully.');
    } catch (error) {
      console.error('[Cleanup Job] Error during sweep:', error);
    }
  });
  
  console.log('[Cleanup Job] Registered (Scheduled for 1:00 AM daily)');
};

module.exports = initCleanupJob;
