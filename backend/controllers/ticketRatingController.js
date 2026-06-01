const asyncHandler = require('express-async-handler');
const ClientTicket = require('../models/ClientTicket');

function ensureStarsFilter(stars) {
  if (stars && (typeof stars !== 'string' || !/^[1-5]$/.test(stars))) {
    throw new Error('Stars filter must be between 1 and 5.');
  }
}

function normalizeTicketAssignees(ticket) {
  const assignedEmployees = Array.isArray(ticket.assignedEmployeeIds) ? ticket.assignedEmployeeIds : [];
  if (assignedEmployees.length > 0) {
    return assignedEmployees.map((employee) => ({
      id: String(employee._id || employee.id || ''),
      name: employee.name || 'Unknown',
      email: employee.email || '',
    }));
  }
  if (ticket.assignedEmployeeId) {
    return [
      {
        id: String(ticket.assignedEmployeeId._id || ticket.assignedEmployeeId.id || ticket.assignedEmployeeId),
        name: ticket.assignedEmployeeId.name || 'Unknown',
        email: ticket.assignedEmployeeId.email || '',
      },
    ];
  }
  return [];
}

function expandTicketRatings(ticketDoc) {
  const ticket = ticketDoc.toObject ? ticketDoc.toObject() : ticketDoc;
  const assignedEmployees = normalizeTicketAssignees(ticket);
  const results = [];

  if (Array.isArray(ticket.employeeRatings) && ticket.employeeRatings.length > 0) {
    for (const entry of ticket.employeeRatings) {
      const employeeId =
        entry.employeeId && typeof entry.employeeId === 'object'
          ? String(entry.employeeId._id || entry.employeeId.id || '')
          : String(entry.employeeId || '');
      if (!employeeId) continue;
      const employee =
        assignedEmployees.find((item) => item.id === employeeId) ||
        (entry.employeeId && typeof entry.employeeId === 'object'
          ? {
              id: employeeId,
              name: entry.employeeId.name || 'Unknown',
              email: entry.employeeId.email || '',
            }
          : null);
      results.push({
        id: `${ticket._id}:${employeeId}`,
        ticketId: String(ticket._id),
        ticketNumber: ticket.ticketNumber || 'N/A',
        ticketDescription: ticket.description || '',
        ticketServiceType: ticket.serviceType || '',
        clientEmail: ticket.clientEmail || '',
        employeeId,
        employeeName: employee?.name || '',
        employeeEmail: employee?.email || '',
        stars: entry.stars,
        comment: entry.comment || '',
        submittedAt: entry.submittedAt || ticket.updatedAt || ticket.createdAt,
      });
    }
    return results;
  }

  if (ticket.rating && ticket.rating.stars) {
    const employee = assignedEmployees[0] || { id: '', name: '', email: '' };
    results.push({
      id: `${ticket._id}:${employee.id || 'legacy'}`,
      ticketId: String(ticket._id),
      ticketNumber: ticket.ticketNumber || 'N/A',
      ticketDescription: ticket.description || '',
      ticketServiceType: ticket.serviceType || '',
      clientEmail: ticket.clientEmail || '',
      employeeId: employee.id || '',
      employeeName: employee.name || '',
      employeeEmail: employee.email || '',
      stars: ticket.rating.stars,
      comment: ticket.rating.comment || '',
      submittedAt: ticket.rating.submittedAt || ticket.updatedAt || ticket.createdAt,
    });
  }

  return results;
}

function sortRatingEntries(entries, sortBy) {
  const sorted = [...entries];
  sorted.sort((left, right) => {
    const leftSubmitted = new Date(left.submittedAt || 0).getTime();
    const rightSubmitted = new Date(right.submittedAt || 0).getTime();

    if (sortBy === 'oldest') return leftSubmitted - rightSubmitted;
    if (sortBy === 'rating_high') {
      if (right.stars !== left.stars) return right.stars - left.stars;
      return rightSubmitted - leftSubmitted;
    }
    if (sortBy === 'rating_low') {
      if (left.stars !== right.stars) return left.stars - right.stars;
      return rightSubmitted - leftSubmitted;
    }
    return rightSubmitted - leftSubmitted;
  });
  return sorted;
}

function buildStats(entries) {
  const total = entries.length;
  const totalStars = entries.reduce((sum, entry) => sum + entry.stars, 0);
  return {
    total,
    averageRating: total > 0 ? parseFloat((totalStars / total).toFixed(2)) : 0,
    fiveStarCount: entries.filter((entry) => entry.stars === 5).length,
    fourStarCount: entries.filter((entry) => entry.stars === 4).length,
    threeStarCount: entries.filter((entry) => entry.stars === 3).length,
    twoStarCount: entries.filter((entry) => entry.stars === 2).length,
    oneStarCount: entries.filter((entry) => entry.stars === 1).length,
  };
}

function paginate(entries, page, limit) {
  const pageNumber = parseInt(page, 10);
  const pageSize = parseInt(limit, 10);
  const skip = (pageNumber - 1) * pageSize;
  return {
    pageNumber,
    pageSize,
    total: entries.length,
    pages: Math.max(1, Math.ceil(entries.length / pageSize)),
    items: entries.slice(skip, skip + pageSize),
  };
}

function formatRatingEntry(entry) {
  return {
    id: entry.id,
    ticketNumber: entry.ticketNumber,
    ticketDescription: entry.ticketDescription,
    ticketServiceType: entry.ticketServiceType,
    clientEmail: entry.clientEmail,
    employeeId: entry.employeeId || null,
    employeeName: entry.employeeName || '',
    employeeEmail: entry.employeeEmail || '',
    stars: entry.stars,
    rating: entry.stars,
    comment: entry.comment || '',
    submittedAt: new Date(entry.submittedAt).toISOString(),
    createdAt: new Date(entry.submittedAt).toISOString(),
  };
}

async function loadExpandedRatings(ticketQuery = {}) {
  const tickets = await ClientTicket.find(ticketQuery)
    .populate('assignedEmployeeId', 'name email')
    .populate('assignedEmployeeIds', 'name email')
    .populate('employeeRatings.employeeId', 'name email')
    .sort({ updatedAt: -1, createdAt: -1 });
  return tickets.flatMap(expandTicketRatings);
}

exports.getClientRatings = asyncHandler(async (req, res) => {
  const { clientEmail, page = 1, limit = 10, sort = 'recent', stars } = req.query;

  if (!clientEmail || typeof clientEmail !== 'string' || clientEmail.trim().length === 0) {
    return res.status(400).json({ error: 'Client email is required.' });
  }

  try {
    ensureStarsFilter(stars);
    const sortBy = ['recent', 'rating_high', 'rating_low'].includes(sort) ? sort : 'recent';
    let ratings = await loadExpandedRatings({
      clientEmail: clientEmail.toLowerCase().trim(),
    });

    if (stars) {
      ratings = ratings.filter((entry) => entry.stars === parseInt(stars, 10));
    }

    ratings = sortRatingEntries(ratings, sortBy);
    const stats = buildStats(ratings);
    const paged = paginate(ratings, page, limit);

    res.json({
      success: true,
      ratings: paged.items.map(formatRatingEntry),
      total: paged.total,
      pages: paged.pages,
      page: paged.pageNumber,
      limit: paged.pageSize,
      ...stats,
    });
  } catch (error) {
    const statusCode = error.message === 'Stars filter must be between 1 and 5.' ? 400 : 500;
    console.error('Error fetching client ratings:', error);
    res.status(statusCode).json({
      error: statusCode === 400 ? error.message : 'Failed to fetch ratings',
      message: process.env.NODE_ENV === 'development' ? error.message : 'Internal error',
    });
  }
});

exports.getAllClientRatingsAdmin = asyncHandler(async (req, res) => {
  const { page = 1, limit = 20, sort = 'recent', stars, clientEmail, startDate, endDate } = req.query;

  try {
    ensureStarsFilter(stars);
    const sortBy = ['recent', 'oldest', 'rating_high', 'rating_low'].includes(sort)
      ? sort
      : 'recent';
    const ticketQuery = {};
    if (clientEmail && typeof clientEmail === 'string' && clientEmail.trim()) {
      ticketQuery.clientEmail = { $regex: clientEmail.trim(), $options: 'i' };
    }

    let ratings = await loadExpandedRatings(ticketQuery);

    if (stars) {
      ratings = ratings.filter((entry) => entry.stars === parseInt(stars, 10));
    }
    if (startDate) {
      const start = new Date(startDate);
      ratings = ratings.filter((entry) => new Date(entry.submittedAt) >= start);
    }
    if (endDate) {
      const end = new Date(endDate);
      end.setHours(23, 59, 59, 999);
      ratings = ratings.filter((entry) => new Date(entry.submittedAt) <= end);
    }

    ratings = sortRatingEntries(ratings, sortBy);
    const stats = buildStats(ratings);
    const paged = paginate(ratings, page, limit);

    res.json({
      success: true,
      ratings: paged.items.map(formatRatingEntry),
      total: paged.total,
      pages: paged.pages,
      page: paged.pageNumber,
      limit: paged.pageSize,
      ...stats,
    });
  } catch (error) {
    const statusCode = error.message === 'Stars filter must be between 1 and 5.' ? 400 : 500;
    console.error('Error fetching admin client ratings:', error);
    res.status(statusCode).json({
      error: statusCode === 400 ? error.message : 'Failed to fetch ratings',
      message: process.env.NODE_ENV === 'development' ? error.message : 'Internal error',
    });
  }
});

exports.exportClientRatingsAdmin = asyncHandler(async (req, res) => {
  const { format = 'csv', stars, clientEmail, startDate, endDate } = req.query;

  if (!['csv', 'json'].includes(format)) {
    return res.status(400).json({ error: 'Format must be csv or json.' });
  }

  try {
    ensureStarsFilter(stars);
    const ticketQuery = {};
    if (clientEmail && typeof clientEmail === 'string' && clientEmail.trim()) {
      ticketQuery.clientEmail = { $regex: clientEmail.trim(), $options: 'i' };
    }

    let ratings = await loadExpandedRatings(ticketQuery);
    if (stars) {
      ratings = ratings.filter((entry) => entry.stars === parseInt(stars, 10));
    }
    if (startDate) {
      const start = new Date(startDate);
      ratings = ratings.filter((entry) => new Date(entry.submittedAt) >= start);
    }
    if (endDate) {
      const end = new Date(endDate);
      end.setHours(23, 59, 59, 999);
      ratings = ratings.filter((entry) => new Date(entry.submittedAt) <= end);
    }

    ratings = sortRatingEntries(ratings, 'recent');
    const formattedRatings = ratings.map((entry) => ({
      ticketNumber: entry.ticketNumber,
      clientEmail: entry.clientEmail,
      employeeName: entry.employeeName || '',
      serviceType: entry.ticketServiceType,
      stars: entry.stars,
      comment: entry.comment || '',
      submittedAt: new Date(entry.submittedAt).toLocaleString(),
    }));

    if (format === 'json') {
      return res.json({
        success: true,
        total: formattedRatings.length,
        data: formattedRatings,
      });
    }

    if (formattedRatings.length === 0) {
      return res.json({
        success: true,
        total: 0,
        data: [],
      });
    }

    const csv = [
      ['Ticket #', 'Client Email', 'Employee', 'Service Type', 'Rating (Stars)', 'Comment', 'Submitted At'].join(','),
      ...formattedRatings.map((entry) =>
        [
          `"${entry.ticketNumber}"`,
          `"${entry.clientEmail}"`,
          `"${entry.employeeName}"`,
          `"${entry.serviceType}"`,
          entry.stars,
          `"${entry.comment.replace(/"/g, '""')}"`,
          `"${entry.submittedAt}"`,
        ].join(',')
      ),
    ].join('\n');

    res.setHeader('Content-Type', 'text/csv');
    res.setHeader('Content-Disposition', `attachment; filename="client-grades-${Date.now()}.csv"`);
    res.send(csv);
  } catch (error) {
    const statusCode = error.message === 'Stars filter must be between 1 and 5.' ? 400 : 500;
    console.error('Error exporting client ratings:', error);
    res.status(statusCode).json({
      error: statusCode === 400 ? error.message : 'Failed to export ratings',
      message: process.env.NODE_ENV === 'development' ? error.message : 'Internal error',
    });
  }
});

exports.getEmployeeReceivedGrades = asyncHandler(async (req, res) => {
  const employeeId = req.user?.id;
  if (!employeeId) {
    return res.status(401).json({ error: 'Authentication required' });
  }

  const { page = 1, limit = 10, sort = 'recent', stars } = req.query;

  try {
    ensureStarsFilter(stars);
    const sortBy = ['recent', 'oldest', 'rating_high', 'rating_low'].includes(sort)
      ? sort
      : 'recent';
    let grades = await loadExpandedRatings({
      $or: [{ assignedEmployeeId: employeeId }, { assignedEmployeeIds: employeeId }],
    });

    grades = grades.filter((entry) => entry.employeeId === String(employeeId));
    if (stars) {
      grades = grades.filter((entry) => entry.stars === parseInt(stars, 10));
    }

    grades = sortRatingEntries(grades, sortBy);
    const stats = buildStats(grades);
    const paged = paginate(grades, page, limit);

    res.json({
      success: true,
      grades: paged.items.map(formatRatingEntry),
      total: paged.total,
      pages: paged.pages,
      page: paged.pageNumber,
      limit: paged.pageSize,
      ...stats,
    });
  } catch (error) {
    const statusCode = error.message === 'Stars filter must be between 1 and 5.' ? 400 : 500;
    console.error('Error fetching employee received grades:', error);
    res.status(statusCode).json({
      error: statusCode === 400 ? error.message : 'Failed to load grades',
      message: process.env.NODE_ENV === 'development' ? error.message : 'Internal error',
    });
  }
});
