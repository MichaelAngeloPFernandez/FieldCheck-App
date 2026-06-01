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

/**
 * GET /api/ticket-ratings/admin/all
 * Get all ticket ratings (admin only)
 * Query params: page, limit, sort, stars, clientEmail, startDate, endDate
 */
exports.getAllClientRatingsAdmin = asyncHandler(async (req, res) => {
  const { page = 1, limit = 20, sort = 'recent', stars, clientEmail, startDate, endDate } = req.query;

  // Validate star filter
  if (stars && (typeof stars !== 'string' || !/^[1-5]$/.test(stars))) {
    return res.status(400).json({ error: 'Stars filter must be between 1 and 5.' });
  }

  // Validate sort parameter
  const validSorts = ['recent', 'oldest', 'rating_high', 'rating_low'];
  const sortBy = validSorts.includes(sort) ? sort : 'recent';

  try {
    // Build query
    const query = {};

    if (stars) {
      query.stars = parseInt(stars, 10);
    }

    if (clientEmail && typeof clientEmail === 'string' && clientEmail.trim()) {
      query.clientEmail = { $regex: clientEmail.trim(), $options: 'i' };
    }

    // Date range filter
    if (startDate || endDate) {
      query.submittedAt = {};
      if (startDate) {
        query.submittedAt.$gte = new Date(startDate);
      }
      if (endDate) {
        const end = new Date(endDate);
        end.setHours(23, 59, 59, 999);
        query.submittedAt.$lte = end;
      }
    }

    const skip = (parseInt(page, 10) - 1) * parseInt(limit, 10);

    // Determine sort order
    let sortOrder = { submittedAt: -1 }; // recent (default)
    if (sortBy === 'oldest') {
      sortOrder = { submittedAt: 1 };
    } else if (sortBy === 'rating_high') {
      sortOrder = { stars: -1, submittedAt: -1 };
    } else if (sortBy === 'rating_low') {
      sortOrder = { stars: 1, submittedAt: -1 };
    }

    // Fetch ratings
    const ratings = await TicketRating.find(query)
      .populate('ticketId', 'ticketNumber description serviceType')
      .sort(sortOrder)
      .skip(skip)
      .limit(parseInt(limit, 10));

    const total = await TicketRating.countDocuments(query);

    // Calculate statistics for all ratings
    const allRatings = await TicketRating.find(query);
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
      clientEmail: rating.clientEmail,
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
    console.error('Error fetching admin client ratings:', error);
    res.status(500).json({
      error: 'Failed to fetch ratings',
      message: process.env.NODE_ENV === 'development' ? error.message : 'Internal error',
    });
  }
});

/**
 * GET /api/ticket-ratings/admin/export
 * Export all ticket ratings as CSV (admin only)
 * Query params: format (csv|json), stars, clientEmail, startDate, endDate
 */
exports.exportClientRatingsAdmin = asyncHandler(async (req, res) => {
  const { format = 'csv', stars, clientEmail, startDate, endDate } = req.query;

  // Validate format
  if (!['csv', 'json'].includes(format)) {
    return res.status(400).json({ error: 'Format must be csv or json.' });
  }

  try {
    // Build query (same as getAllClientRatingsAdmin)
    const query = {};

    if (stars && /^[1-5]$/.test(stars)) {
      query.stars = parseInt(stars, 10);
    }

    if (clientEmail && typeof clientEmail === 'string' && clientEmail.trim()) {
      query.clientEmail = { $regex: clientEmail.trim(), $options: 'i' };
    }

    if (startDate || endDate) {
      query.submittedAt = {};
      if (startDate) {
        query.submittedAt.$gte = new Date(startDate);
      }
      if (endDate) {
        const end = new Date(endDate);
        end.setHours(23, 59, 59, 999);
        query.submittedAt.$lte = end;
      }
    }

    // Fetch all ratings for export
    const ratings = await TicketRating.find(query)
      .populate('ticketId', 'ticketNumber description serviceType')
      .sort({ submittedAt: -1 });

    const formattedRatings = ratings.map(rating => ({
      ticketNumber: rating.ticketId?.ticketNumber || 'N/A',
      clientEmail: rating.clientEmail,
      serviceType: rating.ticketId?.serviceType || '',
      stars: rating.stars,
      comment: rating.comment || '',
      submittedAt: new Date(rating.submittedAt).toLocaleString(),
    }));

    if (format === 'json') {
      res.json({
        success: true,
        total: formattedRatings.length,
        data: formattedRatings,
      });
      return;
    }

    // CSV format
    if (formattedRatings.length === 0) {
      res.json({
        success: true,
        total: 0,
        data: [],
      });
      return;
    }

    const csv = [
      ['Ticket #', 'Client Email', 'Service Type', 'Rating (Stars)', 'Comment', 'Submitted At'].join(','),
      ...formattedRatings.map(r =>
        [
          `"${r.ticketNumber}"`,
          `"${r.clientEmail}"`,
          `"${r.serviceType}"`,
          r.stars,
          `"${r.comment.replace(/"/g, '""')}"`,
          `"${r.submittedAt}"`,
        ].join(',')
      ),
    ].join('\n');

    res.setHeader('Content-Type', 'text/csv');
    res.setHeader('Content-Disposition', `attachment; filename="client-grades-${Date.now()}.csv"`);
    res.send(csv);
  } catch (error) {
    console.error('Error exporting client ratings:', error);
    res.status(500).json({
      error: 'Failed to export ratings',
      message: process.env.NODE_ENV === 'development' ? error.message : 'Internal error',
    });
  }
});

/**
 * GET /api/employees/me/grades
 * Get all grades/ratings that an employee RECEIVED from clients (employee auth required)
 * Query params: page, limit, sort, stars
 */
exports.getEmployeeReceivedGrades = asyncHandler(async (req, res) => {
  const employeeId = req.user?.id;
  if (!employeeId) {
    return res.status(401).json({ error: 'Authentication required' });
  }

  const { page = 1, limit = 10, sort = 'recent', stars } = req.query;

  // Optional star filter validation
  if (stars && (typeof stars !== 'string' || !/^[1-5]$/.test(stars))) {
    return res.status(400).json({ error: 'Stars filter must be between 1 and 5.' });
  }

  // Validate sort parameter
  const validSorts = ['recent', 'oldest', 'rating_high', 'rating_low'];
  const sortBy = validSorts.includes(sort) ? sort : 'recent';

  try {
    // First, find all tickets assigned to this employee
    const assignedTickets = await ClientTicket.find({
      assignedEmployeeId: employeeId,
    }).select('_id');

    const ticketIds = assignedTickets.map(t => t._id);

    if (ticketIds.length === 0) {
      return res.json({
        success: true,
        grades: [],
        total: 0,
        pages: 1,
        page: parseInt(page, 10),
        limit: parseInt(limit, 10),
        averageRating: 0.0,
        fiveStarCount: 0,
        fourStarCount: 0,
        threeStarCount: 0,
        twoStarCount: 0,
        oneStarCount: 0,
      });
    }

    // Build query for ratings on tickets assigned to this employee
    const query = {
      ticketId: { $in: ticketIds },
    };

    if (stars) {
      query.stars = parseInt(stars, 10);
    }

    const skip = (parseInt(page, 10) - 1) * parseInt(limit, 10);

    // Determine sort order
    let sortOrder = { submittedAt: -1 }; // recent (default)
    if (sortBy === 'oldest') {
      sortOrder = { submittedAt: 1 };
    } else if (sortBy === 'rating_high') {
      sortOrder = { stars: -1, submittedAt: -1 };
    } else if (sortBy === 'rating_low') {
      sortOrder = { stars: 1, submittedAt: -1 };
    }

    // Fetch ratings
    const grades = await TicketRating.find(query)
      .populate('ticketId', 'ticketNumber description serviceType')
      .sort(sortOrder)
      .skip(skip)
      .limit(parseInt(limit, 10));

    const total = await TicketRating.countDocuments(query);

    // Calculate statistics
    const allGrades = await TicketRating.find(query);
    const fiveStarCount = allGrades.filter(r => r.stars === 5).length;
    const fourStarCount = allGrades.filter(r => r.stars === 4).length;
    const threeStarCount = allGrades.filter(r => r.stars === 3).length;
    const twoStarCount = allGrades.filter(r => r.stars === 2).length;
    const oneStarCount = allGrades.filter(r => r.stars === 1).length;

    const totalStars = allGrades.reduce((sum, r) => sum + r.stars, 0);
    const averageRating = allGrades.length > 0 ? (totalStars / allGrades.length).toFixed(2) : 0.0;

    // Format response
    const formattedGrades = grades.map(grade => ({
      id: grade._id.toString(),
      ticketNumber: grade.ticketId?.ticketNumber || 'N/A',
      ticketDescription: grade.ticketId?.description || '',
      ticketServiceType: grade.ticketId?.serviceType || '',
      clientEmail: grade.clientEmail,
      rating: grade.stars,
      comment: grade.comment || '',
      createdAt: grade.submittedAt.toISOString(),
    }));

    res.json({
      success: true,
      grades: formattedGrades,
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
    console.error('Error fetching employee received grades:', error);
    res.status(500).json({
      error: 'Failed to load grades',
      message: process.env.NODE_ENV === 'development' ? error.message : 'Internal error',
    });
  }
});
