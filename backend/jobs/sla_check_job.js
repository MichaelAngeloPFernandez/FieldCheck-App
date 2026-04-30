const cron = require('node-cron');
const Ticket = require('../models/Ticket');
const auditService = require('../services/auditService');

const SLA_CHECK_SCHEDULE = '*/5 * * * *'; // every 5 minutes

const checkSlaDeadlines = async () => {
  try {
    const now = new Date();
    const atRiskThreshold = new Date(now.getTime() + 30 * 60 * 1000); // 30 min before

    // Mark at-risk tickets
    await Ticket.updateMany(
      {
        sla_deadline: { $lte: atRiskThreshold, $gt: now },
        sla_status: 'on_time',
        status: { $nin: ['completed', 'verified', 'closed'] },
      },
      { $set: { sla_status: 'at_risk' } }
    );

    // Mark overdue tickets
    const overdue = await Ticket.find({
      sla_deadline: { $lte: now },
      sla_status: { $ne: 'overdue' },
      status: { $nin: ['completed', 'verified', 'closed'] },
    }).select('_id ticket_no company assignee');

    for (const ticket of overdue) {
      ticket.sla_status = 'overdue';
      await ticket.save();

      await auditService.log({
        resource_type: 'ticket',
        resource_id: ticket._id,
        action: 'sla_breached',
        actor_id: null,
        company: ticket.company,
        details: { ticket_no: ticket.ticket_no },
      });

      if (global.io) {
        global.io.emit('ticketSlaBreached', {
          ticketId: String(ticket._id),
          ticket_no: ticket.ticket_no,
          assignee: ticket.assignee ? String(ticket.assignee) : null,
        });
      }
    }
  } catch (err) {
    console.error('SLA check failed:', err.message || err);
  }
};

const initializeSlaCheckJob = () => {
  cron.schedule(SLA_CHECK_SCHEDULE, checkSlaDeadlines, {
    scheduled: true,
    timezone: 'UTC',
  });
  console.log(`✅ SLA check job scheduled: ${SLA_CHECK_SCHEDULE}`);
};

module.exports = initializeSlaCheckJob;
