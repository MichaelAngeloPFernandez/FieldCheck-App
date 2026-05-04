const express = require('express');
const router = express.Router();
const {
  createTicket,
  getTickets,
  getTicketById,
} = require('../controllers/ticketController');

const { protect, admin, requireCompany } = require('../middleware/authMiddleware');

// All ticket endpoints require authentication, admin role, and company scoping
router.use(protect, admin, requireCompany);

// List and create tickets
router.get('/', getTickets);
router.post('/', createTicket);

// Get specific ticket with all tasks
router.get('/:id', getTicketById);

module.exports = router;
