const asyncHandler = require('express-async-handler');
const ClientTicket = require('../models/ClientTicket');
const ClientAccount = require('../models/ClientAccount');
const TicketRating = require('../models/TicketRating');
const Task = require('../models/Task');
const UserTask = require('../models/UserTask');
const User = require('../models/User');
const appNotificationService = require('../services/appNotificationService');
const sendEmail = require('../utils/emailService');
const ticketConfirmationEmail = require('../utils/templates/ticketConfirmationEmail');
const ticketAssignedEmail = require('../utils/templates/ticketAssignedEmail');
const ticketCompletedEmail = require('../utils/templates/ticketCompletedEmail');
const { generateTicketNumber } = require('../utils/ticketNumberGenerator');
const { generateEmailToken, verifyEmailToken } = require('../utils/emailTokenGenerator');

/**
 * POST /api/client-tickets
 * Create a new client support ticket (public endpoint, no auth required)
 */
exports.createClientTicket = asyncHandler(async (req, res) => {
  const { clientName, clientEmail, serviceType, description, otherServiceDetails, attachments, signupForTracking } = req.body;

  // Input validation
  if (!clientName || typeof clientName !== 'string' || clientName.trim().length < 2) {
    return res.status(400).json({ error: 'Invalid client name. Must be at least 2 characters.' });
  }

  if (!clientEmail || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(clientEmail)) {
    return res.status(400).json({ error: 'Invalid email address.' });
  }

  if (!serviceType || !['facility_inspection', 'maintenance', 'equipment_check', 'cleaning', 'security_audit', 'aircon_cleaning', 'other'].includes(serviceType)) {
    return res.status(400).json({ error: 'Invalid service type.' });
  }

  if (!description || typeof description !== 'string' || description.trim().length < 10) {
    return res.status(400).json({ error: 'Description must be at least 10 characters long.' });
  }

  if (serviceType === 'other' && (!otherServiceDetails || otherServiceDetails.trim().length < 5)) {
    return res.status(400).json({ error: 'Please provide service details for "Other" service type.' });
  }

  // Validate attachments if provided
  if (attachments && Array.isArray(attachments)) {
    if (attachments.length > 5) {
      return res.status(400).json({ error: 'Maximum 5 file attachments allowed.' });
    }
    for (const attachment of attachments) {
      if (!attachment.fileUrl || !attachment.fileName) {
        return res.status(400).json({ error: 'Invalid attachment format.' });
      }
    }
  }

  try {
    // Generate unique ticket number
    const ticketNumber = await generateTicketNumber();

    // Generate secure email tracking token
    const { token, tokenHash } = generateEmailToken();

    // Create ticket
    const ticket = new ClientTicket({
      ticketNumber,
      clientEmail: clientEmail.toLowerCase(),
      clientName: clientName.trim(),
      serviceType,
      description: description.trim(),
      otherServiceDetails: serviceType === 'other' ? otherServiceDetails.trim() : null,
      attachments: attachments || [],
      trackingToken: tokenHash,
    });

    await ticket.save();

    // Optional: Create client account if opted in
    if (signupForTracking) {
      const existing = await ClientAccount.findOne({ email: clientEmail.toLowerCase() });
      if (!existing) {
        const clientAccount = new ClientAccount({
          email: clientEmail.toLowerCase(),
          clientName: clientName.trim(),
          emailVerified: true, // Auto-verify for now
          submittedTicketIds: [ticket._id],
        });
        await clientAccount.save();
      } else {
        // Add ticket to existing account
        existing.submittedTicketIds.push(ticket._id);
        await existing.save();
      }
    }

    // Send confirmation email to client
    // Include tracking token in the email link for secure tracking
    const trackingLink = `${process.env.FRONTEND_URL || 'http://localhost:3000'}/client-ticket/${ticketNumber}?token=${token}`;
    const confirmationEmailHtml = ticketConfirmationEmail(ticketNumber, clientName, serviceType, description, trackingLink);
    
    await sendEmail({
      email: clientEmail,
      subject: `Support Ticket Confirmed - ${ticketNumber}`,
      html: confirmationEmailHtml,
    });

    // Create notification for all admins
    await appNotificationService.createForAdmins({
      scope: 'clientTickets',
      type: 'new_ticket',
      title: `New Client Ticket: ${ticketNumber}`,
      message: `${clientName} submitted a ${serviceType} support ticket.`,
      action: 'view_ticket',
      payload: {
        ticketId: ticket._id.toString(),
        ticketNumber,
      },
    });

    // Emit real-time notification via socket.io
    if (global.io) {
      global.io.emit('client_ticket_created', {
        ticketId: ticket._id,
        ticketNumber,
        clientName,
        serviceType,
      });
    }

    res.status(201).json({
      success: true,
      ticketNumber: ticket.ticketNumber,
      message: 'Support ticket submitted successfully. Check your email for confirmation.',
      trackingLink: signupForTracking ? trackingLink : null,
    });
  } catch (error) {
    console.error('Error creating client ticket:', error);
    res.status(500).json({
      error: 'Failed to create support ticket',
      message: process.env.NODE_ENV === 'development' ? error.message : 'Internal error',
    });
  }
});

/**
 * GET /api/client-tickets
 * List client tickets with advanced filtering (admin only)
 */
exports.listClientTickets = asyncHandler(async (req, res) => {
  const { status, serviceType, clientEmail, assignedTo, ticketNumber, startDate, endDate, page = 1, limit = 10 } = req.query;

  // Build query
  const query = {};

  if (status) {
    if (!['open', 'in_progress', 'pending_review', 'completed', 'closed'].includes(status)) {
      return res.status(400).json({ error: 'Invalid status value.' });
    }
    query.status = status;
  }

  if (serviceType) {
    if (!['facility_inspection', 'maintenance', 'equipment_check', 'cleaning', 'security_audit', 'aircon_cleaning', 'other'].includes(serviceType)) {
      return res.status(400).json({ error: 'Invalid service type.' });
    }
    query.serviceType = serviceType;
  }

  if (clientEmail) {
    query.clientEmail = { $regex: clientEmail, $options: 'i' };
  }

  if (ticketNumber) {
    query.ticketNumber = { $regex: ticketNumber, $options: 'i' };
  }

  if (assignedTo) {
    query.assignedEmployeeId = assignedTo;
  }

  if (startDate || endDate) {
    query.createdAt = {};
    if (startDate) {
      query.createdAt.$gte = new Date(startDate);
    }
    if (endDate) {
      query.createdAt.$lte = new Date(endDate);
    }
  }

  try {
    const skip = (page - 1) * limit;
    const tickets = await ClientTicket.find(query)
      .populate('assignedEmployeeId', 'name email')
      .populate('linkedTaskId', '_id title status')
      .sort({ createdAt: -1 })
      .skip(skip)
      .limit(parseInt(limit));

    const total = await ClientTicket.countDocuments(query);

    res.json({
      success: true,
      data: tickets,
      pagination: {
        total,
        page: parseInt(page),
        limit: parseInt(limit),
        pages: Math.ceil(total / limit),
      },
    });
  } catch (error) {
    console.error('Error listing client tickets:', error);
    res.status(500).json({
      error: 'Failed to fetch tickets',
      message: process.env.NODE_ENV === 'development' ? error.message : 'Internal error',
    });
  }
});

/**
 * GET /api/client-tickets/:ticketNumber
 * Get ticket details (public if tracking, admin/employee if assigned)
 */
/**
 * GET /api/client-tickets/:ticketNumber
 * Public endpoint to fetch a ticket (requires email token from URL)
 * Token passed via X-Ticket-Token header (from email link)
 */
exports.getClientTicket = asyncHandler(async (req, res) => {
  const { ticketNumber } = req.params;
  const emailToken = req.headers['x-ticket-token'];

  if (!ticketNumber || !/^RNG-\d{8}-[A-Z0-9]{4}$/.test(ticketNumber)) {
    return res.status(400).json({ error: 'Invalid ticket number format.' });
  }

  try {
    // Fetch ticket with tracking token (select: false means it's hidden by default)
    const ticket = await ClientTicket.findOne({ ticketNumber })
      .select('+trackingToken')
      .populate('assignedEmployeeId', 'name email phone')
      .populate('linkedTaskId', '_id title status progress dueDate')
      .populate('comments.authorId', 'name email');

    if (!ticket) {
      return res.status(404).json({ error: 'Ticket not found.' });
    }

    // Verify email token if provided
    if (emailToken) {
      if (!ticket.trackingToken || !verifyEmailToken(emailToken, ticket.trackingToken)) {
        return res.status(401).json({ error: 'Invalid or expired ticket link.' });
      }
    }

    // Remove sensitive field from response
    const ticketData = ticket.toObject();
    delete ticketData.trackingToken;

    res.json({
      success: true,
      data: ticketData,
    });
  } catch (error) {
    console.error('Error fetching client ticket:', error);
    res.status(500).json({
      error: 'Failed to fetch ticket',
      message: process.env.NODE_ENV === 'development' ? error.message : 'Internal error',
    });
  }
});

/**
 * POST /api/client-tickets/:ticketNumber/assign/:employeeId
 * Assign ticket to an employee (admin only)
 * Auto-creates a UserTask in employee's task list
 */
exports.assignTicketToEmployee = asyncHandler(async (req, res) => {
  const { ticketNumber, employeeId } = req.params;
  const { dueDate } = req.body;

  // Validate ticket number format
  if (!ticketNumber || !/^RNG-\d{8}-[A-Z0-9]{4}$/.test(ticketNumber)) {
    return res.status(400).json({ error: 'Invalid ticket number format.' });
  }

  // Validate employee ID
  if (!employeeId || employeeId.length !== 24) {
    return res.status(400).json({ error: 'Invalid employee ID.' });
  }

  try {
    // Find ticket
    const ticket = await ClientTicket.findOne({ ticketNumber });
    if (!ticket) {
      return res.status(404).json({ error: 'Ticket not found.' });
    }

    // Verify employee exists
    const employee = await User.findById(employeeId);
    if (!employee || employee.role !== 'employee') {
      return res.status(404).json({ error: 'Employee not found or invalid role.' });
    }

    // Check if already assigned
    if (ticket.assignedEmployeeId) {
      return res.status(400).json({ error: 'Ticket is already assigned to an employee.' });
    }

    // Update ticket
    ticket.assignedEmployeeId = employeeId;
    ticket.assignedBy = req.user._id;
    ticket.assignedAt = new Date();
    ticket.status = 'in_progress';
    await ticket.save();

    // Create linked task in employee task list
    const task = new Task({
      title: `Client Ticket: ${ticketNumber}`,
      description: `⚠️ CLIENT SUPPORT TICKET\n\nTicket #: ${ticketNumber}\nClient Email: ${ticket.clientEmail}\nService Type: ${ticket.serviceType}\n\nClient's Message:\n"${ticket.description}"\n\nFollow standard task workflow: Accept → Work → Submit for Review\nUpdates will be sent to client via email.\nRating by: CLIENT (not admin)`,
      type: 'client_support',
      difficulty: 'medium',
      dueDate: dueDate ? new Date(dueDate) : new Date(Date.now() + 7 * 24 * 60 * 60 * 1000), // Default 7 days
      assignedBy: req.user._id,
      assignedTo: employeeId,
      status: 'pending_acceptance',
      attachments: {
        documents: ticket.attachments.map(a => a.fileUrl),
      },
    });

    await task.save();

    // Link task to ticket
    ticket.linkedTaskId = task._id;
    await ticket.save();

    // Create UserTask assignment
    const userTask = new UserTask({
      userId: employeeId,
      taskId: task._id,
      status: 'pending_acceptance',
    });

    await userTask.save();

    // Send email to employee
    const assignedEmployeeEmailHtml = ticketAssignedEmail(
      employee.name,
      ticketNumber,
      ticket.clientName,
      ticket.clientEmail,
      ticket.serviceType,
      ticket.description
    );

    await sendEmail({
      email: employee.email,
      subject: `New Client Support Ticket Assigned: ${ticketNumber}`,
      html: assignedEmployeeEmailHtml,
    });

    // Create notification for employee
    await appNotificationService.createForUser(employeeId, {
      scope: 'clientTickets',
      type: 'ticket_assigned',
      title: `Client Ticket Assigned: ${ticketNumber}`,
      message: `Client ${ticket.clientName} needs assistance with ${ticket.serviceType}.`,
      action: 'view_task',
      payload: {
        taskId: task._id.toString(),
        ticketNumber,
      },
    });

    res.json({
      success: true,
      message: 'Ticket assigned successfully',
      data: {
        ticket,
        task: task._id,
      },
    });
  } catch (error) {
    console.error('Error assigning client ticket:', error);
    res.status(500).json({
      error: 'Failed to assign ticket',
      message: process.env.NODE_ENV === 'development' ? error.message : 'Internal error',
    });
  }
});

/**
 * PUT /api/client-tickets/:ticketNumber/status
 * Update ticket status (admin only)
 */
exports.updateTicketStatus = asyncHandler(async (req, res) => {
  const { ticketNumber } = req.params;
  const { status } = req.body;

  if (!ticketNumber || !/^RNG-\d{8}-[A-Z0-9]{4}$/.test(ticketNumber)) {
    return res.status(400).json({ error: 'Invalid ticket number format.' });
  }

  if (!status || !['open', 'in_progress', 'pending_review', 'completed', 'closed'].includes(status)) {
    return res.status(400).json({ error: 'Invalid status value.' });
  }

  try {
    const ticket = await ClientTicket.findOne({ ticketNumber });
    if (!ticket) {
      return res.status(404).json({ error: 'Ticket not found.' });
    }

    const oldStatus = ticket.status;
    ticket.status = status;

    if (status === 'completed') {
      ticket.completedAt = new Date();
      ticket.completedBy = req.user._id;

      // Send completion email to client with rating link
      if (ticket.assignedEmployeeId) {
        const employee = await User.findById(ticket.assignedEmployeeId);
        const ratingLink = `${process.env.FRONTEND_URL || 'http://localhost:3000'}/client-ticket/${ticketNumber}/rate`;
        const completedEmailHtml = ticketCompletedEmail(
          ticket.clientName,
          ticketNumber,
          employee?.name || 'Our Team',
          ratingLink
        );

        await sendEmail({
          email: ticket.clientEmail,
          subject: `Your Support Ticket is Complete - ${ticketNumber}`,
          html: completedEmailHtml,
        });
      }
    }

    await ticket.save();

    // Create notification
    if (ticket.assignedEmployeeId) {
      await appNotificationService.createForUser(ticket.assignedEmployeeId, {
        scope: 'clientTickets',
        type: 'ticket_status_updated',
        title: `Ticket Status Updated: ${ticketNumber}`,
        message: `Status changed from ${oldStatus} to ${status}`,
        action: 'view_ticket',
        payload: {
          ticketId: ticket._id.toString(),
          ticketNumber,
        },
      });
    }

    res.json({
      success: true,
      message: 'Ticket status updated',
      data: ticket,
    });
  } catch (error) {
    console.error('Error updating ticket status:', error);
    res.status(500).json({
      error: 'Failed to update ticket status',
      message: process.env.NODE_ENV === 'development' ? error.message : 'Internal error',
    });
  }
});

/**
 * POST /api/client-tickets/:ticketNumber/comment
 * Add comment to ticket (admin, employee, or client)
 */
exports.addTicketComment = asyncHandler(async (req, res) => {
  const { ticketNumber } = req.params;
  const { text, authorType, authorEmail } = req.body;
  const emailToken = req.headers['x-ticket-token'];

  if (!ticketNumber || !/^RNG-\d{8}-[A-Z0-9]{4}$/.test(ticketNumber)) {
    return res.status(400).json({ error: 'Invalid ticket number format.' });
  }

  if (!text || typeof text !== 'string' || text.trim().length < 1) {
    return res.status(400).json({ error: 'Comment text is required.' });
  }

  if (!authorType || !['admin', 'employee', 'client'].includes(authorType)) {
    return res.status(400).json({ error: 'Invalid author type.' });
  }

  try {
    // Fetch ticket with tracking token (select: false means it's hidden by default)
    const ticket = await ClientTicket.findOne({ ticketNumber })
      .select('+trackingToken');
    
    if (!ticket) {
      return res.status(404).json({ error: 'Ticket not found.' });
    }

    // Validate client email and token for client comments
    if (authorType === 'client') {
      if (!authorEmail || authorEmail.toLowerCase() !== ticket.clientEmail) {
        return res.status(403).json({ error: 'Unauthorized: Invalid client email.' });
      }

      // Verify email token if provided
      if (emailToken) {
        if (!ticket.trackingToken || !verifyEmailToken(emailToken, ticket.trackingToken)) {
          return res.status(401).json({ error: 'Invalid or expired ticket link.' });
        }
      } else {
        // Client comment requires token
        return res.status(401).json({ error: 'Ticket token required.' });
      }
    }

    ticket.comments.push({
      authorType,
      authorId: req.user?._id || null,
      authorEmail: authorType === 'client' ? authorEmail : null,
      text: text.trim(),
    });

    await ticket.save();

    // Notify relevant parties
    if (authorType === 'client') {
      // Notify admin and employee
      await appNotificationService.createForAdmins({
        scope: 'clientTickets',
        type: 'ticket_comment_added',
        title: `New Comment on ${ticketNumber}`,
        message: `Client left a comment on their ticket.`,
        action: 'view_ticket',
        payload: {
          ticketId: ticket._id.toString(),
          ticketNumber,
        },
      });
    } else if (authorType === 'employee') {
      // Notify client
      const ratingLink = `${process.env.FRONTEND_URL || 'http://localhost:3000'}/client-ticket/${ticketNumber}`;
      await sendEmail({
        email: ticket.clientEmail,
        subject: `Update on Your Support Ticket - ${ticketNumber}`,
        html: `<p>Hello ${ticket.clientName},</p>
               <p>Our team has posted an update on your ticket:</p>
               <p>${text}</p>
               <p><a href="${ratingLink}">View Full Ticket Details</a></p>`,
      });
    }

    res.json({
      success: true,
      message: 'Comment added successfully',
      data: ticket,
    });
  } catch (error) {
    console.error('Error adding ticket comment:', error);
    res.status(500).json({
      error: 'Failed to add comment',
      message: process.env.NODE_ENV === 'development' ? error.message : 'Internal error',
    });
  }
});

/**
 * POST /api/client-tickets/:ticketNumber/rating
 * Submit rating for completed ticket (client only, requires email token)
 */
exports.submitTicketRating = asyncHandler(async (req, res) => {
  const { ticketNumber } = req.params;
  const { stars, comment, clientEmail } = req.body;
  const emailToken = req.headers['x-ticket-token'];

  if (!ticketNumber || !/^RNG-\d{8}-[A-Z0-9]{4}$/.test(ticketNumber)) {
    return res.status(400).json({ error: 'Invalid ticket number format.' });
  }

  if (!stars || typeof stars !== 'number' || stars < 1 || stars > 5) {
    return res.status(400).json({ error: 'Rating must be between 1 and 5 stars.' });
  }

  if (stars < 3 && (!comment || typeof comment !== 'string' || comment.trim().length < 5)) {
    return res.status(400).json({ error: 'Comment is required for ratings below 3 stars (minimum 5 characters).' });
  }

  if (!clientEmail) {
    return res.status(400).json({ error: 'Client email is required.' });
  }

  try {
    // Fetch ticket with tracking token (select: false means it's hidden by default)
    const ticket = await ClientTicket.findOne({ ticketNumber })
      .select('+trackingToken');
    
    if (!ticket) {
      return res.status(404).json({ error: 'Ticket not found.' });
    }

    // Verify client email matches ticket
    if (clientEmail.toLowerCase() !== ticket.clientEmail) {
      return res.status(403).json({ error: 'Unauthorized: Email does not match ticket.' });
    }

    // Verify email token
    if (emailToken) {
      if (!ticket.trackingToken || !verifyEmailToken(emailToken, ticket.trackingToken)) {
        return res.status(401).json({ error: 'Invalid or expired ticket link.' });
      }
    } else {
      // Rating requires token
      return res.status(401).json({ error: 'Ticket token required.' });
    }

    // Check if ticket is completed
    if (ticket.status !== 'completed') {
      return res.status(400).json({ error: 'Only completed tickets can be rated.' });
    }

    // Check if already rated
    if (ticket.rating && ticket.rating.stars) {
      return res.status(400).json({ error: 'This ticket has already been rated.' });
    }

    // Save rating
    ticket.rating = {
      stars,
      comment: comment ? comment.trim() : null,
      submittedAt: new Date(),
      submittedBy: clientEmail,
    };

    await ticket.save();

    // Create TicketRating record
    const rating = new TicketRating({
      ticketId: ticket._id,
      clientEmail,
      stars,
      comment: comment ? comment.trim() : null,
    });

    await rating.save();

    // Notify admin and employee of rating
    const notificationMsg = stars >= 4 ? '⭐ Positive feedback' : stars >= 3 ? '✓ Neutral feedback' : '⚠️ Negative feedback';
    await appNotificationService.createForAdmins({
      scope: 'clientTickets',
      type: 'ticket_rated',
      title: `Ticket Rated: ${ticketNumber}`,
      message: `${notificationMsg} (${stars}/5 stars) from ${ticket.clientName}`,
      action: 'view_ticket',
      payload: {
        ticketId: ticket._id.toString(),
        ticketNumber,
        rating: stars,
      },
    });

    if (ticket.assignedEmployeeId) {
      await appNotificationService.createForUser(ticket.assignedEmployeeId, {
        scope: 'clientTickets',
        type: 'ticket_rated',
        title: `Your Work Was Rated: ${ticketNumber}`,
        message: `${notificationMsg} (${stars}/5 stars)`,
        action: 'view_ticket',
        payload: {
          ticketId: ticket._id.toString(),
          ticketNumber,
          rating: stars,
        },
      });
    }

    res.json({
      success: true,
      message: 'Rating submitted successfully. Thank you for your feedback!',
      data: {
        ticket,
        rating,
      },
    });
  } catch (error) {
    console.error('Error submitting rating:', error);
    res.status(500).json({
      error: 'Failed to submit rating',
      message: process.env.NODE_ENV === 'development' ? error.message : 'Internal error',
    });
  }
});
