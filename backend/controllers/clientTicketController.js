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
const ticketAssignedClientEmail = require('../utils/templates/ticketAssignedClientEmail');
const ticketCompletedEmail = require('../utils/templates/ticketCompletedEmail');
const { generateTicketNumber } = require('../utils/ticketNumberGenerator');
const { generateEmailToken, verifyEmailToken } = require('../utils/emailTokenGenerator');

// #region agent log
const DEBUG_ENDPOINT = 'http://127.0.0.1:7594/ingest/1c924b68-154a-46b7-8559-78da3d47b03c';
const DEBUG_SESSION_ID = '1d6461';
function debugLog(runId, hypothesisId, location, message, data = {}) {
  try {
    if (typeof fetch !== 'function') {
      return;
    }
    fetch(DEBUG_ENDPOINT, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Debug-Session-Id': DEBUG_SESSION_ID,
      },
      body: JSON.stringify({
        sessionId: DEBUG_SESSION_ID,
        runId,
        hypothesisId,
        location,
        message,
        data,
        timestamp: Date.now(),
      }),
    }).catch(() => {});
  } catch (_) {
    // Never allow debug instrumentation to affect ticket flow
  }
}
// #endregion

function normalizeObjectIdStrings(values) {
  const seen = new Set();
  const normalized = [];
  for (const value of values || []) {
    const raw =
      value && typeof value === 'object' && value._id
        ? value._id.toString()
        : value
        ? value.toString()
        : '';
    if (!raw || seen.has(raw)) continue;
    seen.add(raw);
    normalized.push(raw);
  }
  return normalized;
}

function getAssignedEmployeeIds(ticket) {
  const fromArray = Array.isArray(ticket?.assignedEmployeeIds) ? ticket.assignedEmployeeIds : [];
  if (fromArray.length > 0) {
    return normalizeObjectIdStrings(fromArray);
  }
  if (ticket?.assignedEmployeeId) {
    return normalizeObjectIdStrings([ticket.assignedEmployeeId]);
  }
  return [];
}

function applyAssignedEmployeeIds(ticket, employeeIds) {
  const normalized = normalizeObjectIdStrings(employeeIds);
  ticket.assignedEmployeeIds = normalized;
  ticket.assignedEmployeeId = normalized.length > 0 ? normalized[0] : null;
  return normalized;
}

function toEmployeeSummary(employee) {
  if (!employee) return null;
  const id = employee._id ? employee._id.toString() : employee.id ? employee.id.toString() : '';
  if (!id) return null;
  return {
    id,
    name: employee.name || 'Unknown',
    email: employee.email || '',
    phone: employee.phone || '',
  };
}

function mapEmployeeRatings(ticketObj) {
  const ratings = Array.isArray(ticketObj?.employeeRatings) ? ticketObj.employeeRatings : [];
  return ratings
    .map((entry) => {
      const employee = toEmployeeSummary(entry.employeeId);
      const employeeId = employee?.id || (entry.employeeId ? entry.employeeId.toString() : '');
      if (!employeeId) return null;
      return {
        employeeId,
        employee,
        reportId: entry.reportId ? entry.reportId.toString() : null,
        stars: entry.stars,
        comment: entry.comment || '',
        submittedAt: entry.submittedAt,
        submittedBy: entry.submittedBy || '',
      };
    })
    .filter(Boolean);
}

function getStatusRank(status) {
  switch (status) {
    case 'open':
      return 0;
    case 'in_progress':
      return 1;
    case 'pending_review':
      return 2;
    case 'completed':
      return 3;
    case 'closed':
      return 4;
    case 'expired':
      return 5;
    default:
      return -1;
  }
}

function mergeClientVisibleStatus(rawStatus, derivedStatus) {
  if (['closed', 'expired'].includes(rawStatus)) {
    return rawStatus;
  }
  return getStatusRank(derivedStatus) > getStatusRank(rawStatus) ? derivedStatus : rawStatus;
}

async function buildTicketResponseData(ticket) {
  const ticketData = ticket.toObject();
  delete ticketData.trackingToken;
  ticketData.workflowStatus = ticketData.status;
  let assignedEmployees =
    Array.isArray(ticketData.assignedEmployeeIds) && ticketData.assignedEmployeeIds.length > 0
      ? ticketData.assignedEmployeeIds.map(toEmployeeSummary).filter(Boolean)
      : [toEmployeeSummary(ticketData.assignedEmployeeId)].filter(Boolean);

  if (ticketData.linkedTaskId && assignedEmployees.length === 0) {
    const taskId = ticketData.linkedTaskId._id || ticketData.linkedTaskId;
    const linkedAssignments = await UserTask.find({ taskId })
      .select('userId status')
      .populate('userId', 'name email phone')
      .lean();

    assignedEmployees = linkedAssignments
      .map((entry) => toEmployeeSummary(entry.userId))
      .filter(Boolean);

    if (assignedEmployees.length > 0) {
      ticketData.assignedEmployeeIds = assignedEmployees.map((employee) => employee.id);
      ticketData.assignedEmployeeId = assignedEmployees[0].id;
    }
  }
  ticketData.assignedEmployees = assignedEmployees;

  const employeeRatings = mapEmployeeRatings(ticketData);
  ticketData.employeeRatings = employeeRatings;

  if (!ticketData.rating && employeeRatings.length === 1) {
    ticketData.rating = {
      stars: employeeRatings[0].stars,
      comment: employeeRatings[0].comment,
      submittedAt: employeeRatings[0].submittedAt,
      submittedBy: employeeRatings[0].submittedBy,
    };
  }

  if (ticketData.linkedTaskId && assignedEmployees.length > 0) {
    const Report = require('../models/Report');
    const taskId = ticketData.linkedTaskId._id || ticketData.linkedTaskId;
    const assignedIds = assignedEmployees.map((employee) => employee.id);
    const [reviewedReports, submittedReports, userTasks] = await Promise.all([
      Report.find({
        task: taskId,
        employee: { $in: assignedIds },
        status: 'reviewed',
      })
        .select('_id employee status submittedAt updatedAt')
        .populate('employee', 'name email')
        .lean(),
      Report.find({
        task: taskId,
        employee: { $in: assignedIds },
        status: 'submitted',
      })
        .select('_id employee status submittedAt updatedAt')
        .lean(),
      UserTask.find({
        taskId,
        userId: { $in: assignedIds },
      })
        .select('userId status')
        .lean(),
    ]);

    const ratingsByEmployeeId = new Map(
      employeeRatings.map((rating) => [rating.employeeId, rating])
    );

    ticketData.rateableEmployees = assignedEmployees.map((employee) => {
      const report = reviewedReports.find(
        (entry) => String(entry.employee?._id || entry.employee) === employee.id
      );
      const rating = ratingsByEmployeeId.get(employee.id) || null;
      return {
        employeeId: employee.id,
        employee,
        reportId: report ? String(report._id) : null,
        reportStatus: report?.status || null,
        reportReviewed: Boolean(report),
        existingRating: rating,
      };
    });

    const hasReviewedWork =
      reviewedReports.length > 0 ||
      userTasks.some((entry) => ['completed', 'reviewed'].includes(String(entry.status || '').toLowerCase()));
    const hasPendingReview =
      submittedReports.length > 0 ||
      userTasks.some((entry) => String(entry.status || '').toLowerCase() === 'pending_review');
    const hasAssignedWork = assignedEmployees.length > 0;

    const derivedStatus = hasReviewedWork
      ? 'completed'
      : hasPendingReview
      ? 'pending_review'
      : hasAssignedWork
      ? 'in_progress'
      : 'open';

    ticketData.status = mergeClientVisibleStatus(ticketData.status, derivedStatus);
    ticketData.hasRateableEmployee = ticketData.rateableEmployees.some(
      (employee) => employee.reportReviewed
    );
  } else {
    ticketData.rateableEmployees = assignedEmployees.map((employee) => ({
      employeeId: employee.id,
      employee,
      reportId: null,
      reportStatus: null,
      reportReviewed: false,
      existingRating:
        employeeRatings.find((rating) => rating.employeeId === employee.id) || null,
    }));
    ticketData.hasRateableEmployee = false;
  }

  return ticketData;
}

/**
 * POST /api/client-tickets
 * Create a new client support ticket (public endpoint, no auth required)
 */
exports.createClientTicket = asyncHandler(async (req, res) => {
  const runId = `backend-submit-${Date.now()}`;
  const { clientName, clientEmail, serviceType, description, otherServiceDetails, attachments, signupForTracking } = req.body;
  // #region agent log
  debugLog(runId, 'H6', 'clientTicketController.js:createClientTicket:entry', 'Request reached backend createClientTicket', {
    hasClientName: Boolean(clientName),
    hasClientEmail: Boolean(clientEmail),
    serviceType,
    descriptionLength: typeof description === 'string' ? description.trim().length : null,
  });
  // #endregion

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
    // Generate secure email tracking token
    const { token, tokenHash } = generateEmailToken();

    // Create/save ticket with lightweight retries for transient write issues
    let ticket = null;
    let ticketNumber = null;
    let lastCreateError = null;
    for (let attempt = 0; attempt < 3; attempt++) {
      try {
        ticketNumber = await generateTicketNumber();
        ticket = new ClientTicket({
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
        lastCreateError = null;
        break;
      } catch (createError) {
        lastCreateError = createError;
        console.warn('Client ticket create attempt failed', {
          attempt: attempt + 1,
          error: createError && createError.message ? createError.message : String(createError),
        });
      }
    }

    if (!ticket || !ticketNumber) {
      throw lastCreateError || new Error('Failed to create support ticket after retries');
    }
    // #region agent log
    debugLog(runId, 'H7', 'clientTicketController.js:createClientTicket:afterSave', 'Ticket persisted successfully', {
      ticketNumber,
      signupForTracking: Boolean(signupForTracking),
    });
    // #endregion

    // Respond immediately with success - don't wait for email or notifications
    const trackingLink = `${process.env.FRONTEND_URL || 'http://localhost:3000'}/client-ticket/${ticketNumber}?token=${token}`;
    
    res.status(201).json({
      success: true,
      ticketNumber: ticket.ticketNumber,
      message: 'Support ticket submitted successfully. Check your email for confirmation.',
      trackingLink: signupForTracking ? trackingLink : null,
    });
    // #region agent log
    debugLog(runId, 'H8', 'clientTicketController.js:createClientTicket:response', 'Success response sent to client', {
      ticketNumber: ticket.ticketNumber,
      statusCode: 201,
    });
    // #endregion

    // Send all notifications in background (don't block response)
    setImmediate(async () => {
      try {
        // Optional tracking enrollment should never fail ticket creation
        if (signupForTracking) {
          try {
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
              existing.submittedTicketIds.push(ticket._id);
              await existing.save();
            }
          } catch (trackingError) {
            console.warn('Failed to create/update client tracking account', {
              ticketNumber,
              clientEmail,
              error: trackingError && trackingError.message ? trackingError.message : String(trackingError),
            });
          }
        }

        // Send confirmation email to client
        const confirmationEmailHtml = ticketConfirmationEmail(ticketNumber, clientName, serviceType, description, trackingLink);
        
        try {
          await sendEmail({
            email: clientEmail,
            subject: `Support Ticket Confirmed - ${ticketNumber}`,
            html: confirmationEmailHtml,
          });
          console.log('Client ticket confirmation email sent', { ticketNumber, clientEmail });
        } catch (emailError) {
          console.warn('Client ticket confirmation email failed to send', {
            ticketNumber,
            clientEmail,
            error: emailError && emailError.message ? emailError.message : String(emailError),
          });
        }

        // Create notification for all admins
        try {
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
        } catch (notifError) {
          console.warn('Failed to create admin notification for ticket', {
            ticketNumber,
            error: notifError && notifError.message ? notifError.message : String(notifError),
          });
        }

        // Emit real-time notification via socket.io
        if (global.io) {
          try {
            global.io.emit('client_ticket_created', {
              ticketId: ticket._id,
              ticketNumber,
              clientName,
              serviceType,
            });
          } catch (socketError) {
            console.warn('Failed to emit socket.io notification', {
              ticketNumber,
              error: socketError && socketError.message ? socketError.message : String(socketError),
            });
          }
        }
      } catch (backgroundError) {
        console.error('Error in background ticket notification processing', {
          ticketNumber,
          error: backgroundError && backgroundError.message ? backgroundError.message : String(backgroundError),
        });
      }
    });
  } catch (error) {
    // #region agent log
    debugLog(runId, 'H9', 'clientTicketController.js:createClientTicket:catch', 'Backend error while creating ticket', {
      error: error && error.message ? error.message : String(error),
    });
    // #endregion
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
  const { status, serviceType, clientEmail, assignedTo, ticketNumber, startDate, endDate, includeArchived = false, page = 1, limit = 10 } = req.query;

  // Build query
  const query = {};

  // By default, exclude archived tickets unless specifically requested
  if (includeArchived === 'true' || includeArchived === true) {
    // Include both archived and non-archived
  } else {
    query.archived = { $ne: true };
  }

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
    query.$or = [{ assignedEmployeeId: assignedTo }, { assignedEmployeeIds: assignedTo }];
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
      .populate('assignedEmployeeIds', 'name email')
      .populate('linkedTaskId', '_id title status')
      .sort({ createdAt: -1 })
      .skip(skip)
      .limit(parseInt(limit));

    const total = await ClientTicket.countDocuments(query);

    const data = tickets.map((ticket) => {
      const obj = ticket.toObject();
      obj.assignedEmployees =
        Array.isArray(obj.assignedEmployeeIds) && obj.assignedEmployeeIds.length > 0
          ? obj.assignedEmployeeIds.map(toEmployeeSummary).filter(Boolean)
          : [toEmployeeSummary(obj.assignedEmployeeId)].filter(Boolean);
      return obj;
    });

    res.json({
      success: true,
      data,
      tickets: data,
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
 * POST /api/client-tickets/:ticketNumber/access
 * Issue a fresh secure tracking token after validating the client email.
 */
exports.requestTicketAccess = asyncHandler(async (req, res) => {
  const { ticketNumber } = req.params;
  const { clientEmail } = req.body || {};

  if (!ticketNumber || !/^RNG-\d{8}-[A-Z0-9]{4}$/.test(ticketNumber)) {
    return res.status(400).json({ error: 'Invalid ticket number format.' });
  }

  if (!clientEmail || typeof clientEmail !== 'string') {
    return res.status(400).json({ error: 'Client email is required.' });
  }

  const ticket = await ClientTicket.findOne({ ticketNumber }).select('+trackingToken');
  if (!ticket) {
    return res.status(404).json({ error: 'Ticket not found.' });
  }

  if (ticket.clientEmail !== clientEmail.toLowerCase().trim()) {
    return res.status(403).json({ error: 'Unauthorized: Email does not match ticket.' });
  }

  const { token, tokenHash } = generateEmailToken();
  ticket.trackingToken = tokenHash;
  await ticket.save();

  res.json({
    success: true,
    message: 'Secure ticket access granted.',
    data: {
      ticketNumber,
      accessToken: token,
    },
  });
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
      .populate('assignedEmployeeIds', 'name email phone')
      .populate('linkedTaskId', '_id title status progress dueDate')
      .populate('employeeRatings.employeeId', 'name email')
      .populate('employeeRatings.reportId', '_id status submittedAt')
      .populate('comments.authorId', 'name email');

    if (!ticket) {
      return res.status(404).json({ error: 'Ticket not found.' });
    }

    if (!emailToken || !ticket.trackingToken || !verifyEmailToken(emailToken, ticket.trackingToken)) {
      return res.status(401).json({ error: 'Invalid or expired ticket link.' });
    }

    const ticketData = await buildTicketResponseData(ticket);

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
 * GET /api/client-tickets/admin/:ticketNumber
 * Get ticket details for admins without requiring a public email token.
 */
exports.getClientTicketAdmin = asyncHandler(async (req, res) => {
  const { ticketNumber } = req.params;

  if (!ticketNumber || !/^RNG-\d{8}-[A-Z0-9]{4}$/.test(ticketNumber)) {
    return res.status(400).json({ error: 'Invalid ticket number format.' });
  }

  try {
    const ticket = await ClientTicket.findOne({ ticketNumber })
      .select('+trackingToken')
      .populate('assignedEmployeeId', 'name email phone')
      .populate('assignedEmployeeIds', 'name email phone')
      .populate('linkedTaskId', '_id title status progress dueDate')
      .populate('employeeRatings.employeeId', 'name email')
      .populate('employeeRatings.reportId', '_id status submittedAt')
      .populate('comments.authorId', 'name email');

    if (!ticket) {
      return res.status(404).json({ error: 'Ticket not found.' });
    }

    const ticketData = await buildTicketResponseData(ticket);

    res.json({
      success: true,
      data: ticketData,
    });
  } catch (error) {
    console.error('Error fetching client ticket for admin:', error);
    res.status(500).json({
      error: 'Failed to fetch ticket',
      message: process.env.NODE_ENV === 'development' ? error.message : 'Internal error',
    });
  }
});

/**
 * POST /api/client-tickets/:ticketNumber/assign/:employeeId
 * Assign ticket to one or more employees (admin only)
 * Uses one shared linked task with per-employee UserTask assignments.
 */
exports.assignTicketToEmployee = asyncHandler(async (req, res) => {
  const { ticketNumber, employeeId } = req.params;
  const { dueDate, employeeIds = [] } = req.body;

  // Validate ticket number format
  if (!ticketNumber || !/^RNG-\d{8}-[A-Z0-9]{4}$/.test(ticketNumber)) {
    return res.status(400).json({ error: 'Invalid ticket number format.' });
  }

  const requestedEmployeeIds = normalizeObjectIdStrings([
    ...(Array.isArray(employeeIds) ? employeeIds : []),
    employeeId,
  ]);

  if (requestedEmployeeIds.length === 0) {
    return res.status(400).json({ error: 'At least one employee ID is required.' });
  }

  try {
    const ticket = await ClientTicket.findOne({ ticketNumber });
    if (!ticket) {
      return res.status(404).json({ error: 'Ticket not found.' });
    }

    const employees = await User.find({
      _id: { $in: requestedEmployeeIds },
      role: 'employee',
    }).select('_id name email');

    if (employees.length !== requestedEmployeeIds.length) {
      return res.status(404).json({ error: 'One or more employees were not found or are not employees.' });
    }

    let task = ticket.linkedTaskId ? await Task.findById(ticket.linkedTaskId) : null;
    if (!task) {
      task = new Task({
        title: `Client Ticket: ${ticketNumber}`,
        description: `⚠️ CLIENT SUPPORT TICKET\n\nTicket #: ${ticketNumber}\nClient Email: ${ticket.clientEmail}\nService Type: ${ticket.serviceType}\n\nClient's Message:\n"${ticket.description}"\n\nFollow standard task workflow: Accept → Work → Submit for Review\nUpdates will be sent to client via email.\nRating by: CLIENT (not admin)`,
        type: 'client_support',
        difficulty: 'medium',
        dueDate: dueDate ? new Date(dueDate) : new Date(Date.now() + 7 * 24 * 60 * 60 * 1000),
        assignedBy: req.user._id,
        assignedTo: requestedEmployeeIds[0],
        status: 'assigned',
        attachments: {
          documents: ticket.attachments.map((attachment) => attachment.fileUrl),
        },
      });
      await task.save();
      ticket.linkedTaskId = task._id;
    }

    const existingAssignments = await UserTask.find({
      taskId: task._id,
      userId: { $in: requestedEmployeeIds },
    }).select('userId');
    const existingAssignedIds = new Set(
      existingAssignments.map((assignment) => assignment.userId.toString())
    );

    const createdAssignments = [];
    for (const requestedId of requestedEmployeeIds) {
      if (existingAssignedIds.has(requestedId)) {
        continue;
      }
      const userTask = new UserTask({
        userId: requestedId,
        taskId: task._id,
        status: 'pending_acceptance',
      });
      await userTask.save();
      createdAssignments.push(userTask);
    }

    const mergedAssignedIds = normalizeObjectIdStrings([
      ...getAssignedEmployeeIds(ticket),
      ...requestedEmployeeIds,
    ]);
    applyAssignedEmployeeIds(ticket, mergedAssignedIds);
    ticket.assignedBy = req.user._id;
    ticket.assignedAt = new Date();
    ticket.status = 'in_progress';
    await ticket.save();

    for (const employee of employees) {
      try {
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
      } catch (emailError) {
        console.warn('Failed to send ticket assignment email to employee', {
          ticketNumber,
          employeeId: employee._id.toString(),
          error: emailError && emailError.message ? emailError.message : String(emailError),
        });
      }
    }

    try {
      const employeeLabel = employees.map((employee) => employee.name).join(', ');
      const assignedClientEmailHtml = ticketAssignedClientEmail(
        ticket.clientName,
        ticketNumber,
        employeeLabel,
        ticket.serviceType
      );

      await sendEmail({
        email: ticket.clientEmail,
        subject: `Your Support Ticket is Being Worked On - ${ticketNumber}`,
        html: assignedClientEmailHtml,
      });
    } catch (emailError) {
      console.warn('Failed to send ticket assignment email to client', {
        ticketNumber,
        clientEmail: ticket.clientEmail,
        error: emailError && emailError.message ? emailError.message : String(emailError),
      });
    }

    for (const employee of employees) {
      try {
        await appNotificationService.createForUser(employee._id, {
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
      } catch (notifError) {
        console.warn('Failed to create notification for ticket assignment', {
          ticketNumber,
          employeeId: employee._id.toString(),
          error: notifError && notifError.message ? notifError.message : String(notifError),
        });
      }
    }

    res.json({
      success: true,
      message:
        createdAssignments.length > 0
          ? 'Ticket assigned successfully'
          : 'All requested employees were already assigned to this ticket',
      data: {
        ticket,
        task: task._id,
        assignedEmployeeIds: mergedAssignedIds,
        createdAssignments: createdAssignments.map((assignment) => assignment._id.toString()),
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
    const assignedEmployeeIds = getAssignedEmployeeIds(ticket);
    ticket.status = status;

    if (status === 'completed') {
      ticket.completedAt = new Date();
      ticket.completedBy = req.user._id;

      // Send completion email to client with rating link (don't fail if email fails)
      if (assignedEmployeeIds.length > 0) {
        try {
          const employees = await User.find({ _id: { $in: assignedEmployeeIds } }).select('name');
          const employeeLabel = employees.length
            ? employees.map((employee) => employee.name).join(', ')
            : 'Our Team';
          const ratingLink = `${process.env.FRONTEND_URL || 'http://localhost:3000'}/client-ticket/${ticketNumber}/rate`;
          const completedEmailHtml = ticketCompletedEmail(
            ticket.clientName,
            ticketNumber,
            employeeLabel,
            ratingLink,
            ticket.comments || []
          );

          await sendEmail({
            email: ticket.clientEmail,
            subject: `Your Support Ticket is Complete - ${ticketNumber}`,
            html: completedEmailHtml,
          });
        } catch (emailError) {
          console.warn('Failed to send ticket completion email to client', {
            ticketNumber,
            clientEmail: ticket.clientEmail,
            error: emailError && emailError.message ? emailError.message : String(emailError),
          });
        }
      }
    }

    await ticket.save();

    // Create notification
    for (const assignedEmployeeId of assignedEmployeeIds) {
      await appNotificationService.createForUser(assignedEmployeeId, {
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
      try {
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
      } catch (notifError) {
        console.warn('Failed to create notification for client comment', {
          ticketNumber,
          error: notifError && notifError.message ? notifError.message : String(notifError),
        });
      }
    } else if (authorType === 'employee') {
      // Notify client (don't fail if email fails)
      try {
        const ratingLink = `${process.env.FRONTEND_URL || 'http://localhost:3000'}/client-ticket/${ticketNumber}`;
        await sendEmail({
          email: ticket.clientEmail,
          subject: `Update on Your Support Ticket - ${ticketNumber}`,
          html: `<p>Hello ${ticket.clientName},</p>
                 <p>Our team has posted an update on your ticket:</p>
                 <p>${text}</p>
                 <p><a href="${ratingLink}">View Full Ticket Details</a></p>`,
        });
      } catch (emailError) {
        console.warn('Failed to send ticket update email to client', {
          ticketNumber,
          clientEmail: ticket.clientEmail,
          error: emailError && emailError.message ? emailError.message : String(emailError),
        });
      }
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
 * Only allowed after admin marks the employee report as \"reviewed\"
 */
exports.submitTicketRating = asyncHandler(async (req, res) => {
  const { ticketNumber } = req.params;
  const { stars, comment, clientEmail, employeeId } = req.body || {};
  const emailToken = req.headers['x-ticket-token'];

  if (!ticketNumber || !/^RNG-\d{8}-[A-Z0-9]{4}$/.test(ticketNumber)) {
    return res.status(400).json({ error: 'Invalid ticket number format.' });
  }

  // Stars and comment are now optional but at least one must be provided
  const hasStars = stars !== undefined && stars !== null;
  const hasComment = comment && typeof comment === 'string' && comment.trim().length > 0;

  if (!hasStars && !hasComment) {
    return res.status(400).json({ error: 'Please provide either a rating or a comment.' });
  }

  if (hasStars && (typeof stars !== 'number' || stars < 1 || stars > 5)) {
    return res.status(400).json({ error: 'Rating must be between 1 and 5 stars.' });
  }

  if (hasStars && stars < 3 && (!comment || typeof comment !== 'string' || comment.trim().length < 5)) {
    return res.status(400).json({ error: 'Comment is required for ratings below 3 stars (minimum 5 characters).' });
  }

  if (!clientEmail) {
    return res.status(400).json({ error: 'Client email is required.' });
  }

  if (employeeId && typeof employeeId !== 'string') {
    return res.status(400).json({ error: 'Invalid employee ID.' });
  }

  try {
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

    const assignedEmployeeIds = getAssignedEmployeeIds(ticket);
    const normalizedEmployeeId = employeeId ? employeeId.trim() : '';
    const targetEmployeeId =
      normalizedEmployeeId ||
      (assignedEmployeeIds.length === 1 ? assignedEmployeeIds[0] : '');

    if (assignedEmployeeIds.length > 1 && !targetEmployeeId) {
      return res.status(400).json({
        error: 'Please select which assigned employee you want to grade.',
      });
    }

    if (targetEmployeeId && !assignedEmployeeIds.includes(targetEmployeeId)) {
      return res.status(400).json({ error: 'Selected employee is not assigned to this ticket.' });
    }

    let targetReport = null;
    if (ticket.linkedTaskId) {
      const Report = require('../models/Report');
      const reportQuery = {
        task: ticket.linkedTaskId,
        status: 'reviewed',
      };
      if (targetEmployeeId) {
        reportQuery.employee = targetEmployeeId;
      }
      targetReport = await Report.findOne(reportQuery)
        .sort({ updatedAt: -1, submittedAt: -1 })
        .populate('employee', 'name email');

      if (!targetReport) {
        return res.status(400).json({
          error:
            'Report must be reviewed before you can grade it. Please wait for admin review.',
        });
      }
    } else if (ticket.status !== 'completed' && ticket.status !== 'pending_review') {
      return res.status(400).json({
        error: 'This ticket is not ready for grading yet. It must be in pending review or completed status.',
      });
    }

    const ratingComment = comment ? comment.trim() : '';
    const ratingStars = hasStars ? stars : null;  // Stars can be null for comment-only submissions
    const submittedAt = new Date();
    const employeeRatings = Array.isArray(ticket.employeeRatings)
      ? [...ticket.employeeRatings]
      : [];
    const existingRatingIndex = employeeRatings.findIndex((entry) => {
      const entryEmployeeId =
        entry.employeeId && typeof entry.employeeId === 'object' && entry.employeeId._id
          ? entry.employeeId._id.toString()
          : entry.employeeId
          ? entry.employeeId.toString()
          : '';
      return entryEmployeeId === targetEmployeeId;
    });
    const existingLegacyRating = targetEmployeeId
      ? employeeRatings.find((entry) => {
          const entryEmployeeId =
            entry.employeeId && typeof entry.employeeId === 'object' && entry.employeeId._id
              ? entry.employeeId._id.toString()
              : entry.employeeId
              ? entry.employeeId.toString()
              : '';
          return entryEmployeeId === targetEmployeeId;
        })
      : ticket.rating;
    const isResubmission = Boolean(existingLegacyRating && existingLegacyRating.stars);

    const nextRating = {
      employeeId: targetEmployeeId || null,
      reportId: targetReport?._id || null,
      stars: ratingStars,
      comment: ratingComment,
      submittedAt,
      submittedBy: clientEmail.toLowerCase().trim(),
    };

    if (targetEmployeeId) {
      if (existingRatingIndex >= 0) {
        employeeRatings[existingRatingIndex] = nextRating;
      } else {
        employeeRatings.push(nextRating);
      }
      ticket.employeeRatings = employeeRatings;
    }

    if (!targetEmployeeId || assignedEmployeeIds.length <= 1) {
      ticket.rating = {
        stars: ratingStars,
        comment: ratingComment || null,
        submittedAt,
        submittedBy: clientEmail.toLowerCase().trim(),
      };
    }

    await ticket.save();

    let rating = null;
    try {
      const ratingFilter = {
        ticketId: ticket._id,
        clientEmail: clientEmail.toLowerCase().trim(),
      };
      if (targetEmployeeId) {
        ratingFilter.employeeId = targetEmployeeId;
      }
      rating = await TicketRating.findOneAndUpdate(
        ratingFilter,
        {
          $set: {
            employeeId: targetEmployeeId || null,
            reportId: targetReport?._id || null,
            stars: ratingStars,
            comment: ratingComment || null,
            submittedAt,
          },
          $setOnInsert: {
            ticketId: ticket._id,
            clientEmail: clientEmail.toLowerCase().trim(),
          },
        },
        {
          new: true,
          upsert: true,
          runValidators: true,
          setDefaultsOnInsert: true,
        }
      );
    } catch (ratingError) {
      console.warn('Failed to persist TicketRating mirror record', {
        ticketNumber,
        employeeId: targetEmployeeId || null,
        error: ratingError && ratingError.message ? ratingError.message : String(ratingError),
      });
    }

    const targetEmployee =
      targetReport?.employee ||
      (targetEmployeeId ? await User.findById(targetEmployeeId).select('name email') : null);

    const notificationMsg = ratingStars ? (ratingStars >= 4 ? '⭐ Positive feedback' : ratingStars >= 3 ? '✓ Neutral feedback' : '⚠️ Negative feedback') : '💬 Comment received';
    const ratingDisplay = ratingStars ? `(${ratingStars}/5 stars)` : '(comment only)';
    await appNotificationService.createForAdmins({
      scope: 'clientTickets',
      type: 'ticket_rated',
      title: `Ticket Rated: ${ticketNumber}`,
      message: `${notificationMsg} ${ratingDisplay} from ${ticket.clientName}${targetEmployee ? ` for ${targetEmployee.name}` : ''}`,
      action: 'view_ticket',
      payload: {
        ticketId: ticket._id.toString(),
        ticketNumber,
        rating: ratingStars,
        employeeId: targetEmployeeId || null,
      },
    });

    if (targetEmployeeId) {
      await appNotificationService.createForUser(targetEmployeeId, {
        scope: 'clientTickets',
        type: 'ticket_rated',
        title: `Your Work Was Rated: ${ticketNumber}`,
        message: `${notificationMsg} ${ratingDisplay}`,
        action: 'view_ticket',
        payload: {
          ticketId: ticket._id.toString(),
          ticketNumber,
          rating: ratingStars,
          employeeId: targetEmployeeId,
        },
      });
    }

    // Emit real-time WebSocket notification to admin
    if (global.io) {
      try {
        global.io.emit('client_graded_ticket', {
          ticketNumber,
          clientName: ticket.clientName,
          clientEmail: ticket.clientEmail,
          employeeId: targetEmployeeId || null,
          employeeName: targetEmployee?.name || null,
          stars: ratingStars,
          comment: ratingComment || null,
          isResubmission: !!isResubmission,
          gradedAt: submittedAt.toISOString(),
        });
      } catch (socketError) {
        console.warn('Failed to emit client_graded_ticket socket event', {
          ticketNumber,
          error: socketError && socketError.message ? socketError.message : String(socketError),
        });
      }
    }

    res.json({
      success: true,
      message: 'Rating submitted successfully. Thank you for your feedback!',
      data: {
        ticket,
        rating:
          rating ||
          {
            employeeId: targetEmployeeId || null,
            reportId: targetReport?._id?.toString() || null,
            stars: ratingStars,
            comment: ratingComment,
            submittedAt,
          },
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

/**
 * PUT /api/client-tickets/:ticketNumber/archive
 * Archive (soft delete) a client ticket (admin only)
 * Archived tickets are hidden but remain searchable
 */
exports.archiveTicket = asyncHandler(async (req, res) => {
  const { ticketNumber } = req.params;
  const adminId = req.user._id;

  if (!ticketNumber || !/^RNG-\d{8}-[A-Z0-9]{4}$/.test(ticketNumber)) {
    return res.status(400).json({ error: 'Invalid ticket number format.' });
  }

  try {
    const ticket = await ClientTicket.findOne({ ticketNumber });
    
    if (!ticket) {
      return res.status(404).json({ error: 'Ticket not found.' });
    }

    if (ticket.archived) {
      return res.status(400).json({ error: 'Ticket is already archived.' });
    }

    // Archive the ticket
    ticket.archived = true;
    ticket.archivedAt = new Date();
    ticket.archivedBy = adminId;
    await ticket.save();

    // Notify admins about archive action
    await appNotificationService.emitEventToAdmins({
      event: 'ticketArchived',
      payload: {
        ticketId: ticket._id.toString(),
        ticketNumber,
      },
    });

    res.json({
      success: true,
      message: 'Ticket archived successfully',
      data: ticket,
    });
  } catch (error) {
    console.error('Error archiving ticket:', error);
    res.status(500).json({
      error: 'Failed to archive ticket',
      message: process.env.NODE_ENV === 'development' ? error.message : 'Internal error',
    });
  }
});

/**
 * DELETE /api/client-tickets/:ticketNumber
 * Permanently delete a client ticket (admin only)
 * This cannot be undone
 */
exports.deleteTicket = asyncHandler(async (req, res) => {
  const { ticketNumber } = req.params;

  if (!ticketNumber || !/^RNG-\d{8}-[A-Z0-9]{4}$/.test(ticketNumber)) {
    return res.status(400).json({ error: 'Invalid ticket number format.' });
  }

  try {
    const ticket = await ClientTicket.findOne({ ticketNumber });
    
    if (!ticket) {
      return res.status(404).json({ error: 'Ticket not found.' });
    }

    // Store ticket ID before deletion (for notification)
    const ticketId = ticket._id.toString();

    // Delete the ticket
    await ClientTicket.findByIdAndDelete(ticket._id);

    // Notify admins about deletion
    await appNotificationService.emitEventToAdmins({
      event: 'ticketDeleted',
      payload: {
        ticketId,
        ticketNumber,
      },
    });

    res.json({
      success: true,
      message: 'Ticket deleted permanently',
      data: {
        ticketNumber,
        deletedAt: new Date(),
      },
    });
  } catch (error) {
    console.error('Error deleting ticket:', error);
    res.status(500).json({
      error: 'Failed to delete ticket',
      message: process.env.NODE_ENV === 'development' ? error.message : 'Internal error',
    });
  }
});
