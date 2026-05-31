const express = require('express');
const router = express.Router();
const ticketRatingController = require('../controllers/ticketRatingController');

/**
 * Public routes (no authentication required)
 * Note: Admin grading has been removed - only clients can rate and view their own ratings
 */

// GET - Get all ticket ratings for a client (public, email-based)
router.get('/', ticketRatingController.getClientRatings);

module.exports = router;
