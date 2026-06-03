const Task = require('../models/Task');
const ClientTicket = require('../models/ClientTicket');

/**
 * Status Synchronization Service
 * 
 * Automatically synchronizes client ticket status based on linked task status changes.
 * This service is designed to be non-blocking, fail-safe, and includes comprehensive
 * error handling and logging.
 * 
 * Status Mapping (1:1):
 * - Task 'in_progress' -> Ticket 'in_progress'
 * - Task 'pending_review' -> Ticket 'pending_review'
 * - Task 'completed' -> Ticket 'completed'
 * - Task 'closed' -> Ticket 'closed'
 * 
 * Unmapped task statuses (no synchronization):
 * - pending, created, assigned, accepted, blocked, reviewed
 */

/**
 * Direct 1:1 status mapping between task and ticket statuses
 */
const STATUS_MAPPING = {
  'in_progress': 'in_progress',
  'pending_review': 'pending_review',
  'completed': 'completed',
  'closed': 'closed'
};

/**
 * Terminal ticket statuses that cannot be changed
 */
const TERMINAL_STATUSES = ['closed', 'expired'];

/**
 * Synchronize client ticket status based on task status change
 * 
 * @param {String|ObjectId} taskId - The ID of the task that was updated
 * @returns {Promise<void>} - Resolves when synchronization is complete (or skipped)
 * 
 * @example
 * // After updating a task status
 * await syncTicketStatus(task._id);
 * 
 * @description
 * This function:
 * 1. Retrieves the task and linked ticket
 * 2. Checks if the task status maps to a ticket status
 * 3. Validates the ticket is not in a terminal state
 * 4. Updates the ticket status and saves it
 * 5. Triggers email notification (non-blocking)
 * 
 * All errors are caught and logged without throwing to ensure
 * synchronization failures don't interrupt task update operations.
 */
async function syncTicketStatus(taskId) {
  try {
    console.log('Starting ticket status synchronization', { taskId: taskId.toString() });

    // 1. Retrieve Task
    const task = await Task.findById(taskId).select('status');
    if (!task) {
      console.debug('Task not found for synchronization', { taskId: taskId.toString() });
      return;
    }

    console.debug('Task retrieved for synchronization', { 
      taskId: taskId.toString(), 
      taskStatus: task.status
    });

    // 2. Find ticket that links to this task
    const ticket = await ClientTicket.findOne({ linkedTaskId: taskId });
    if (!ticket) {
      console.debug('No ticket found linked to this task', { 
        taskId: taskId.toString() 
      });
      return;
    }

    console.debug('Ticket retrieved for synchronization', {
      ticketNumber: ticket.ticketNumber,
      currentStatus: ticket.status,
      taskStatus: task.status
    });

    // 3. Check if task status maps to a ticket status
    const newTicketStatus = STATUS_MAPPING[task.status];
    if (!newTicketStatus) {
      console.debug('Task status not mapped to ticket status', { 
        taskId: taskId.toString(),
        taskStatus: task.status,
        ticketNumber: ticket.ticketNumber
      });
      return;
    }

    // 4. Terminal status protection
    if (TERMINAL_STATUSES.includes(ticket.status)) {
      console.debug('Ticket is in terminal status, skipping update', {
        ticketNumber: ticket.ticketNumber,
        currentStatus: ticket.status,
        attemptedStatus: newTicketStatus
      });
      return;
    }

    // 5. Check if status actually changed
    if (ticket.status === newTicketStatus) {
      console.debug('Ticket status already matches target status, skipping update', {
        ticketNumber: ticket.ticketNumber,
        status: ticket.status
      });
      return;
    }

    // 6. Update ticket status
    const oldStatus = ticket.status;
    ticket.status = newTicketStatus;
    // updatedAt is automatically set by Mongoose pre-save hook

    try {
      await ticket.save(); // Use save() to trigger validations and hooks
      console.log('Ticket status synchronized', {
        ticketNumber: ticket.ticketNumber,
        taskId: taskId.toString(),
        oldStatus,
        newStatus: newTicketStatus
      });
    } catch (error) {
      console.error('Failed to update ticket status', {
        ticketNumber: ticket.ticketNumber,
        taskId: taskId.toString(),
        attemptedStatus: newTicketStatus,
        error: error.message
      });
      // Don't throw - let synchronization fail gracefully
      return;
    }

    // 7. Trigger email notification (non-blocking)
    // Email sending is deferred to avoid blocking ticket update
    setImmediate(async () => {
      try {
        // Import email service here to avoid circular dependencies
        const { sendStatusUpdateEmail } = require('../utils/emailService');
        
        await sendStatusUpdateEmail(ticket, newTicketStatus);
        console.log('Status update email sent', {
          ticketNumber: ticket.ticketNumber,
          clientEmail: ticket.clientEmail,
          newStatus: newTicketStatus
        });
      } catch (emailError) {
        console.error('Failed to send status update email', {
          ticketNumber: ticket.ticketNumber,
          clientEmail: ticket.clientEmail,
          newStatus: newTicketStatus,
          error: emailError.message
        });
        // Email failure doesn't affect ticket update
      }
    });

  } catch (error) {
    // Catch any unexpected errors to prevent interrupting task updates
    console.error('Unexpected error in ticket status synchronization', {
      taskId: taskId ? taskId.toString() : 'unknown',
      error: error.message,
      stack: error.stack
    });
    // Don't throw - synchronization should never interrupt task operations
  }
}

module.exports = {
  syncTicketStatus
};
