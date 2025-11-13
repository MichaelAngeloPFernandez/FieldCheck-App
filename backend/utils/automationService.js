/**
 * Automation Service
 * Handles automated tasks like:
 * - Deleting unverified users after 24 hours
 * - Cleanup of expired verification tokens
 * - Scheduling email reminders
 */

const cron = require('node-cron');
const User = require('../models/User');

// Run daily cleanup at 2 AM (UTC)
// Format: '0 2 * * *' = every day at 02:00
const CLEANUP_SCHEDULE = '0 2 * * *';

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
};
