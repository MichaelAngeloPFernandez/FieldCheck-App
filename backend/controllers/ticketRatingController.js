/**
 * Ticket Rating Controller
 * Handles client-side ticket rating retrieval (public, client-only access)
 * Note: Admin grading has been removed - only clients can rate tickets
 */

const asyncHandler = require('express-async-handler');
const TicketRating = require('../models/TicketRating');
const ClientTicket = require('../models/ClientTicket');

/**
 * GET /api/ticket-ratings
 * Get all ticket ratings for a specific client (public - email-based, no auth required)
 * Query params: clientEmail (required), page, limit, sort, stars
 */
exports.getClientRatings = asyncHandler(async (req, res) => {
  const { clientEmail, page = 1, limit = 10, sort = 'recent', stars } = req.query;

  if (!clientEmail || typeof clientEmail !== 'string' || clientEmail.trim().length === 0) {
    return res.status(400).json({ error: 'Client email is required.' });
  }

  // Optional star filter validation
  if (stars && (typeof stars !== 'string' || !/^[1-5]$/.test(stars))) {
    return res.status(400).json({ error: 'Stars filter must be between 1 and 5.' });
  }

  // Validate sort parameter
  const validSorts = ['recent', 'rating_high', 'rating_low'];
  const sortBy = validSorts.includes(sort) ? sort : 'recent';

  try {
    // Build query
    const query = {
      clientEmail: clientEmail.toLowerCase().trim(),
    };

    if (stars) {
      query.stars = parseInt(stars, 10);
    }

    const skip = (parseInt(page, 10) - 1) * parseInt(limit, 10);

    // Determine sort order
    let sortOrder = { submittedAt: -1 }; // recent (default)
    if (sortBy === 'rating_high') {
      sortOrder = { stars: -1, submittedAt: -1 };
    } else if (sortBy === 'rating_low') {
      sortOrder = { stars: 1, submittedAt: -1 };
    }

    // Fetch ratings with ticket details
    const ratings = await TicketRating.find(query)
      .populate('ticketId', 'ticketNumber description serviceType')
      .sort(sortOrder)
      .skip(skip)
      .limit(parseInt(limit, 10));

    const total = await TicketRating.countDocuments(query);

    // Calculate statistics
    const allRatings = await TicketRating.find({
      clientEmail: clientEmail.toLowerCase().trim(),
    });

    const fiveStarCount = allRatings.filter(r => r.stars === 5).length;
    const fourStarCount = allRatings.filter(r => r.stars === 4).length;
    const threeStarCount = allRatings.filter(r => r.stars === 3).length;
    const twoStarCount = allRatings.filter(r => r.stars === 2).length;
    const oneStarCount = allRatings.filter(r => r.stars === 1).length;

    const totalStars = allRatings.reduce((sum, r) => sum + r.stars, 0);
    const averageRating = allRatings.length > 0 ? (totalStars / allRatings.length).toFixed(2) : 0;

    // Format response
    const formattedRatings = ratings.map(rating => ({
      id: rating._id.toString(),
      ticketNumber: rating.ticketId?.ticketNumber || 'N/A',
      ticketDescription: rating.ticketId?.description || '',
      ticketServiceType: rating.ticketId?.serviceType || '',
      stars: rating.stars,
      comment: rating.comment,
      submittedAt: rating.submittedAt.toISOString(),
    }));

    res.json({
      success: true,
      ratings: formattedRatings,
      total,
      pages: Math.ceil(total / parseInt(limit, 10)),
      page: parseInt(page, 10),
      limit: parseInt(limit, 10),
      averageRating: parseFloat(averageRating),
      fiveStarCount,
      fourStarCount,
      threeStarCount,
      twoStarCount,
      oneStarCount,
    });
  } catch (error) {
    console.error('Error fetching client ratings:', error);
    res.status(500).json({
      error: 'Failed to fetch ratings',
      message: process.env.NODE_ENV === 'development' ? error.message : 'Internal error',
    });
  }
});
