const express = require('express');
const router = express.Router();
const ticketRatingController = require('../controllers/ticketRatingController');
const { protect, admin } = require('../middleware/authMiddleware');

/**
 * Employee-only routes (JWT auth required)
 * Must come before public routes to be matched first
 */

// GET - Get all grades that current employee RECEIVED from clients
router.get('/me/grades', protect, ticketRatingController.getEmployeeReceivedGrades);

/**
 * Admin-only routes
 */

// GET - Get all client ratings (admin only)
router.get('/admin/all', protect, admin, ticketRatingController.getAllClientRatingsAdmin);

// GET - Export client ratings as CSV or JSON (admin only)
router.get('/admin/export', protect, admin, ticketRatingController.exportClientRatingsAdmin);

/**
 * Public routes (no authentication required)
 * Note: Admin grading has been removed - only clients can rate and view their own ratings
 * MUST come last so specific routes above are matched first
 */

// GET - Get all ticket ratings for a client (public, email-based)
router.get('/', ticketRatingController.getClientRatings);

module.exports = router;
