/**
 * Ticket Expiration Job
 * 
 * Auto-expires client tickets that have been in 'open' status for more than 3 days.
 * Runs every 5 minutes to check for expired tickets.
 */

const ClientTicket = require('../models/ClientTicket');
const appNotificationService = require('../services/appNotificationService');

const EXPIRATION_DAYS = 3;
const CHECK_INTERVAL = 5 * 60 * 1000; // 5 minutes

let jobRunning = false;

async function checkAndExpireTickets() {
  if (jobRunning) {
    console.log('[TicketExpiration] Job already running, skipping...');
    return;
  }

  jobRunning = true;
  const jobStartTime = new Date();

  try {
    // Calculate the cutoff time: 3 days ago from now
    const expirationTime = new Date();
    expirationTime.setDate(expirationTime.getDate() - EXPIRATION_DAYS);

    console.log(`[TicketExpiration] Checking for tickets created before ${expirationTime.toISOString()}`);

    // Find all 'open' tickets older than 3 days
    const expiredTickets = await ClientTicket.find({
      status: 'open',
      createdAt: { $lt: expirationTime },
    });

    if (expiredTickets.length === 0) {
      console.log('[TicketExpiration] No expired tickets found');
      jobRunning = false;
      return;
    }

    console.log(`[TicketExpiration] Found ${expiredTickets.length} tickets to expire`);

    // Update all expired tickets
    const result = await ClientTicket.updateMany(
      {
        status: 'open',
        createdAt: { $lt: expirationTime },
      },
      {
        $set: {
          status: 'expired',
          expiresAt: new Date(),
          updatedAt: new Date(),
        },
      }
    );

    console.log(`[TicketExpiration] Updated ${result.modifiedCount} tickets to expired status`);

    // Notify admins about batch expiration
    if (result.modifiedCount > 0) {
      try {
        await appNotificationService.createForAdmins({
          scope: 'clientTickets',
          type: 'batch_expiration',
          title: `${result.modifiedCount} Client Tickets Expired`,
          message: `${result.modifiedCount} tickets that were open for over ${EXPIRATION_DAYS} days have been automatically expired.`,
          action: 'view_tickets',
          payload: {
            expiredCount: result.modifiedCount,
            expiredAt: new Date(),
          },
        });
      } catch (notifError) {
        console.error('[TicketExpiration] Failed to send notification:', notifError && notifError.message ? notifError.message : notifError);
      }
    }

    const jobDuration = new Date() - jobStartTime;
    console.log(`[TicketExpiration] Job completed in ${jobDuration}ms`);
  } catch (error) {
    console.error(
      '[TicketExpiration] Error during ticket expiration:',
      error && error.message ? error.message : error
    );
  } finally {
    jobRunning = false;
  }
}

function initializeTicketExpirationJob() {
  console.log('[TicketExpiration] Initializing ticket expiration scheduler...');

  // Run once immediately on startup
  checkAndExpireTickets().catch((err) => {
    console.error('[TicketExpiration] Initial check failed:', err && err.message ? err.message : err);
  });

  // Then run every CHECK_INTERVAL
  const interval = setInterval(() => {
    checkAndExpireTickets().catch((err) => {
      console.error('[TicketExpiration] Check failed:', err && err.message ? err.message : err);
    });
  }, CHECK_INTERVAL);

  // Cleanup on process exit
  process.on('SIGTERM', () => {
    console.log('[TicketExpiration] Clearing interval on SIGTERM');
    clearInterval(interval);
  });

  process.on('SIGINT', () => {
    console.log('[TicketExpiration] Clearing interval on SIGINT');
    clearInterval(interval);
  });

  console.log('[TicketExpiration] Scheduler initialized, will check every 5 minutes');
}

module.exports = initializeTicketExpirationJob;
