/**
 * Ticket Rating Controller
 * Handles listing and managing ticket ratings
 */

const asyncHandler = require('express-async-handler');
const TicketRating = require('../models/TicketRating');
const ClientTicket = require('../models/ClientTicket');

/**
 * GET /api/ticket-ratings
 * List all ticket ratings with filters (admin only)
 */
exports.listTicketRatings = asyncHandler(async (req, res) => {
  const { stars, search, sort = 'recent', page = 1, limit = 15 } = req.query;

  // Build query
  const query = {};

  if (stars) {
    const starsInt = parseInt(stars);
    if (starsInt >= 1 && starsInt <= 5) {
      query.stars = starsInt;
    }
  }

  if (search) {
    query.$or = [
      { clientEmail: { $regex: search, $options: 'i' } },
      { 'ticket.ticketNumber': { $regex: search, $options: 'i' } },
    ];
  }

  try {
    const skip = (parseInt(page) - 1) * parseInt(limit);

    // Build sort object
    let sortObj = { createdAt: -1 }; // Default: newest first
    if (sort === 'oldest') {
      sortObj = { createdAt: 1 };
    } else if (sort === 'highest') {
      sortObj = { stars: -1, createdAt: -1 };
    } else if (sort === 'lowest') {
      sortObj = { stars: 1, createdAt: -1 };
    }

    // Fetch ratings with pagination
    const ratings = await TicketRating.find(query)
      .populate('ticketId', 'ticketNumber clientName clientEmail')
      .sort(sortObj)
      .skip(skip)
      .limit(parseInt(limit));

    // Format response to include ticket details
    const formattedRatings = ratings.map(rating => ({
      _id: rating._id,
      ticketNumber: rating.ticketId?.ticketNumber || 'N/A',
      clientEmail: rating.clientEmail,
      stars: rating.stars,
      comment: rating.comment,
      submittedAt: rating.createdAt,
    }));

    // Get total count
    const total = await TicketRating.countDocuments(query);

    res.json({
      success: true,
      data: formattedRatings,
      ratings: formattedRatings, // Frontend expects 'ratings' key
      total,
      page: parseInt(page),
      limit: parseInt(limit),
      pages: Math.ceil(total / parseInt(limit)),
    });
  } catch (error) {
    console.error('Error listing ticket ratings:', error);
    res.status(500).json({
      error: 'Failed to fetch ratings',
      message: process.env.NODE_ENV === 'development' ? error.message : 'Internal error',
    });
  }
});
