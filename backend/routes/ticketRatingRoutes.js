const express = require('express');
const router = express.Router();
const ticketRatingController = require('../controllers/ticketRatingController');
const { protect, admin } = require('../middleware/authMiddleware');

/**
 * Admin-only routes (authentication required)
 */

// GET - List all ticket ratings with filters (admin only)
router.get(
  '/',
  protect,
  admin,
  ticketRatingController.listTicketRatings
);

module.exports = router;
