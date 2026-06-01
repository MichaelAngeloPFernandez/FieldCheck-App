const express = require('express');
const router = express.Router();
const clientTicketController = require('../controllers/clientTicketController');
const { protect, admin } = require('../middleware/authMiddleware');

/**
 * Admin-only routes (authentication required)
 */

// GET - List all client tickets with filters (admin only)
router.get(
  '/',
  protect,
  admin,
  clientTicketController.listClientTickets
);

router.get(
  '/admin/:ticketNumber',
  protect,
  admin,
  clientTicketController.getClientTicketAdmin
);

// POST - Assign ticket to employee
router.post(
  '/:ticketNumber/assign/:employeeId',
  protect,
  admin,
  clientTicketController.assignTicketToEmployee
);

// POST - Assign ticket to multiple employees
router.post(
  '/:ticketNumber/assign',
  protect,
  admin,
  clientTicketController.assignTicketToEmployee
);

// PUT - Update ticket status
router.put(
  '/:ticketNumber/status',
  protect,
  admin,
  clientTicketController.updateTicketStatus
);

// PUT - Archive ticket (soft delete)
router.put(
  '/:ticketNumber/archive',
  protect,
  admin,
  clientTicketController.archiveTicket
);

// DELETE - Permanently delete ticket
router.delete(
  '/:ticketNumber',
  protect,
  admin,
  clientTicketController.deleteTicket
);

/**
 * Public routes (no authentication required)
 */

// POST - Create client ticket (public submission)
router.post('/', clientTicketController.createClientTicket);

// GET - View ticket details (public tracking via ticket number)
router.get('/:ticketNumber', clientTicketController.getClientTicket);

// POST - Request secure access token for ticket tracking/grading
router.post('/:ticketNumber/access', clientTicketController.requestTicketAccess);

// POST - Submit rating (public, email-based auth)
router.post('/:ticketNumber/rating', clientTicketController.submitTicketRating);

// POST - Add comment as client
router.post('/:ticketNumber/comment', clientTicketController.addTicketComment);

module.exports = router;
