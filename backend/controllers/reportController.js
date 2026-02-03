const asyncHandler = require('express-async-handler');
const Report = require('../models/Report');
const Attendance = require('../models/Attendance');
const Task = require('../models/Task');

const getIo = () => {
  const candidate = global.io;
  if (candidate && typeof candidate.emit === 'function') {
    return candidate;
  }
  return { emit: () => {} };
};

async function populateReportById(reportId) {
  return await Report.findById(reportId)
    .populate('employee', 'name email employeeId avatarUrl')
    .populate('task', 'title description difficulty dueDate status isArchived')
    .populate('attendance')
    .populate('geofence', 'name');
}

// @desc Create a new report (task or attendance)
// @route POST /api/reports
// @access Private
const createReport = asyncHandler(async (req, res) => {
  const { type, taskId, attendanceId, employeeId, geofenceId, content, attachments } = req.body;
  if (!type || !['task', 'attendance'].includes(type)) {
    res.status(400);
    throw new Error('Invalid report type');
  }

  if (content && typeof content === 'string' && content.length > 10000) {
    res.status(400);
    throw new Error('Report content is too long (max 10000 characters)');
  }

  // Validate user is authenticated
  if (!req.user || !req.user._id) {
    res.status(401);
    throw new Error('User not authenticated');
  }

  const isAdmin = req.user && req.user.role === 'admin';
  const reportData = {
    type,
    employee: isAdmin ? (employeeId || req.user._id) : req.user._id,
    content: content || '',
    attachments: Array.isArray(attachments) ? attachments : [],
  };

  if (type === 'task') {
    if (!taskId) {
      res.status(400);
      throw new Error('taskId is required for task reports');
    }
    const task = await Task.findById(taskId);
    if (!task) {
      res.status(404);
      throw new Error('Task not found');
    }

    const now = new Date();
    const isOverdue =
      !!task.dueDate &&
      task.dueDate instanceof Date &&
      !Number.isNaN(task.dueDate.getTime()) &&
      task.dueDate < now &&
      (task.status || '').toLowerCase() !== 'completed' &&
      !task.isArchived;

    if (isOverdue && !isAdmin) {
      const existing = await Report.findOne({
        type: 'task',
        task: task._id,
        employee: reportData.employee,
      }).sort({ submittedAt: -1 });

      const canResubmit =
        existing &&
        existing.resubmitUntil &&
        existing.resubmitUntil instanceof Date &&
        existing.resubmitUntil > now;

      if (!canResubmit) {
        res.status(403);
        throw new Error('Task overdue. Admin must reopen submission to resubmit.');
      }

      existing.content = content || '';
      existing.attachments = Array.isArray(attachments) ? attachments : [];
      existing.status = 'submitted';
      existing.submittedAt = now;
      existing.resubmitUntil = undefined;
      const updated = await existing.save();

      setImmediate(async () => {
        try {
          const populated = await populateReportById(updated._id);
          getIo().emit('updatedReport', populated || updated);
        } catch (_) {
          getIo().emit('updatedReport', updated);
        }
      });
      return res.status(200).json(updated);
    }

    reportData.task = task._id;
  } else if (type === 'attendance') {
    if (!attendanceId) {
      res.status(400);
      throw new Error('attendanceId is required for attendance reports');
    }
    const attendance = await Attendance.findById(attendanceId);
    if (!attendance) {
      res.status(404);
      throw new Error('Attendance record not found');
    }
    reportData.attendance = attendance._id;
    reportData.geofence = geofenceId || attendance.geofence;
  }

  const created = await Report.create(reportData);
  setImmediate(async () => {
    try {
      const populated = await populateReportById(created._id);
      getIo().emit('newReport', populated || created);
    } catch (_) {
      getIo().emit('newReport', created);
    }
  });
  res.status(201).json(created);
});

// @desc List reports
// @route GET /api/reports
// @access Private
// Optional query: archived=true|false (default false)
const listReports = asyncHandler(async (req, res) => {
  const { type, employeeId, taskId, geofenceId, startDate, endDate, archived } = req.query;
  const filter = {};
  if (type) filter.type = type;

  // Role-based scoping:
  // - Admin: may list all reports and can filter by employeeId
  // - Employee: can only list their own reports; ignore/deny employeeId overrides
  if (req.user && req.user.role !== 'admin') {
    filter.employee = req.user._id;
  } else if (employeeId) {
    filter.employee = employeeId;
  }
  if (taskId) filter.task = taskId;
  if (geofenceId) filter.geofence = geofenceId;
  if (startDate || endDate) {
    filter.submittedAt = {};
    if (startDate) filter.submittedAt.$gte = new Date(startDate);
    if (endDate) filter.submittedAt.$lte = new Date(endDate);
  }

  if (archived === 'true') {
    filter.isArchived = true;
  } else if (archived === 'false' || archived === undefined) {
    filter.isArchived = { $ne: true };
  }

  const reports = await Report.find(filter)
    .populate('employee', 'name email')
    .populate('task', 'title description difficulty dueDate status isArchived')
    .populate('attendance')
    .populate('geofence', 'name')
    .sort({ submittedAt: -1 });

  const now = new Date();
  const payload = reports.map((rep) => {
    const obj = rep.toObject({ virtuals: true });
    let taskIsOverdue = false;
    if (obj.type === 'task' && obj.task && obj.task.dueDate) {
      try {
        const due = new Date(obj.task.dueDate);
        const status = obj.task.status || 'pending';
        const isCompleted = status === 'completed';
        const isTaskArchived = !!obj.task.isArchived;
        taskIsOverdue =
          due instanceof Date &&
          !Number.isNaN(due.getTime()) &&
          due < now &&
          !isCompleted &&
          !isTaskArchived;
      } catch (_) {
        taskIsOverdue = false;
      }
    }
    obj.taskIsOverdue = taskIsOverdue;
    return obj;
  });

  res.json(payload);
});

// @desc Get report by id
// @route GET /api/reports/:id
// @access Private/Admin
const getReportById = asyncHandler(async (req, res) => {
  const rep = await Report.findById(req.params.id)
    .populate('employee', 'name email')
    .populate('task', 'title description difficulty dueDate status isArchived')
    .populate('attendance')
    .populate('geofence', 'name');
  if (!rep) {
    res.status(404);
    throw new Error('Report not found');
  }
  res.json(rep);
});

// @desc Update report status
// @route PATCH /api/reports/:id/status
// @access Private/Admin
const updateReportStatus = asyncHandler(async (req, res) => {
  const { status } = req.body;
  const rep = await Report.findById(req.params.id);
  if (!rep) {
    res.status(404);
    throw new Error('Report not found');
  }
  rep.status = status || rep.status;
  const updated = await rep.save();
  setImmediate(async () => {
    try {
      const populated = await populateReportById(updated._id);
      getIo().emit('updatedReport', populated || updated);
    } catch (_) {
      getIo().emit('updatedReport', updated);
    }
  });
  res.json(updated);
});

const replaceReportAttachments = asyncHandler(async (req, res) => {
  const { oldUrl, newUrl, index } = req.body || {};

  if (!newUrl || typeof newUrl !== 'string') {
    res.status(400);
    throw new Error('newUrl is required');
  }

  if (!newUrl.includes('/api/reports/attachments/')) {
    res.status(400);
    throw new Error('newUrl must be a GridFS attachment URL');
  }

  const rep = await Report.findById(req.params.id);
  if (!rep) {
    res.status(404);
    throw new Error('Report not found');
  }

  if (!Array.isArray(rep.attachments)) {
    rep.attachments = [];
  }

  let idx = -1;
  if (index !== undefined && index !== null && String(index).trim() !== '') {
    idx = Number(index);
    if (!Number.isInteger(idx) || idx < 0 || idx >= rep.attachments.length) {
      res.status(400);
      throw new Error('Invalid attachment index');
    }
    if (oldUrl && typeof oldUrl === 'string' && rep.attachments[idx] !== oldUrl) {
      res.status(409);
      throw new Error('Attachment mismatch');
    }
  } else {
    if (!oldUrl || typeof oldUrl !== 'string') {
      res.status(400);
      throw new Error('oldUrl is required');
    }
    idx = rep.attachments.indexOf(oldUrl);
    if (idx === -1) {
      res.status(404);
      throw new Error('Attachment not found in report');
    }
  }

  rep.attachments[idx] = newUrl;
  const updated = await rep.save();
  setImmediate(async () => {
    try {
      const populated = await populateReportById(updated._id);
      getIo().emit('updatedReport', populated || updated);
    } catch (_) {
      getIo().emit('updatedReport', updated);
    }
  });
  res.json(updated);
});

// @desc Delete a report
// @route DELETE /api/reports/:id
// @access Private/Admin
const deleteReport = asyncHandler(async (req, res) => {
  const rep = await Report.findById(req.params.id);
  if (!rep) {
    res.status(404);
    throw new Error('Report not found');
  }
  await rep.deleteOne();
  getIo().emit('deletedReport', req.params.id);
  res.status(204).send();
});

// @desc Get current (non-archived) reports
// @route GET /api/reports/current
// @access Private/Admin
const getCurrentReports = asyncHandler(async (req, res) => {
  const reports = await Report.find({ isArchived: { $ne: true } })
    .populate('employee', 'name email')
    .populate('task', 'title description difficulty dueDate status isArchived')
    .populate('attendance')
    .populate('geofence', 'name')
    .sort({ submittedAt: -1 });

  const now = new Date();
  const payload = reports.map((rep) => {
    const obj = rep.toObject({ virtuals: true });
    let taskIsOverdue = false;
    if (obj.type === 'task' && obj.task && obj.task.dueDate) {
      try {
        const due = new Date(obj.task.dueDate);
        const status = obj.task.status || 'pending';
        const isCompleted = status === 'completed';
        const isTaskArchived = !!obj.task.isArchived;
        taskIsOverdue =
          due instanceof Date &&
          !Number.isNaN(due.getTime()) &&
          due < now &&
          !isCompleted &&
          !isTaskArchived;
      } catch (_) {
        taskIsOverdue = false;
      }
    }
    obj.taskIsOverdue = taskIsOverdue;
    return obj;
  });

  res.json(payload);
});

// @desc Get archived reports
// @route GET /api/reports/archived
// @access Private/Admin
const getArchivedReports = asyncHandler(async (req, res) => {
  const reports = await Report.find({ isArchived: true })
    .populate('employee', 'name email')
    .populate('task', 'title description difficulty dueDate status isArchived')
    .populate('attendance')
    .populate('geofence', 'name')
    .sort({ submittedAt: -1 });

  const now = new Date();
  const payload = reports.map((rep) => {
    const obj = rep.toObject({ virtuals: true });
    let taskIsOverdue = false;
    if (obj.type === 'task' && obj.task && obj.task.dueDate) {
      try {
        const due = new Date(obj.task.dueDate);
        const status = obj.task.status || 'pending';
        const isCompleted = status === 'completed';
        const isTaskArchived = !!obj.task.isArchived;
        taskIsOverdue =
          due instanceof Date &&
          !Number.isNaN(due.getTime()) &&
          due < now &&
          !isCompleted &&
          !isTaskArchived;
      } catch (_) {
        taskIsOverdue = false;
      }
    }
    obj.taskIsOverdue = taskIsOverdue;
    return obj;
  });

  res.json(payload);
});

// @desc Archive a report
// @route PUT /api/reports/:id/archive
// @access Private/Admin
const archiveReport = asyncHandler(async (req, res) => {
  console.log('Archiving report', req.params.id);
  const rep = await Report.findById(req.params.id);
  if (!rep) {
    res.status(404);
    throw new Error('Report not found');
  }

  rep.isArchived = true;
  const updated = await rep.save();
  getIo().emit('reportArchived', updated);
  res.json(updated);
});

// @desc Restore an archived report
// @route PUT /api/reports/:id/restore
// @access Private/Admin
const restoreReport = asyncHandler(async (req, res) => {
  console.log('Restoring report', req.params.id);
  const rep = await Report.findById(req.params.id);
  if (!rep) {
    res.status(404);
    throw new Error('Report not found');
  }

  rep.isArchived = false;
  const updated = await rep.save();
  getIo().emit('reportRestored', updated);
  res.json(updated);
});

const reopenReportForResubmission = asyncHandler(async (req, res) => {
  const rep = await Report.findById(req.params.id);
  if (!rep) {
    res.status(404);
    throw new Error('Report not found');
  }

  const rawHours = req.body && req.body.hours !== undefined ? req.body.hours : 24;
  const hours = Number(rawHours);
  if (!Number.isFinite(hours) || hours <= 0 || hours > 168) {
    res.status(400);
    throw new Error('Invalid reopen window');
  }

  rep.resubmitUntil = new Date(Date.now() + hours * 60 * 60 * 1000);
  const updated = await rep.save();
  setImmediate(async () => {
    try {
      const populated = await populateReportById(updated._id);
      getIo().emit('updatedReport', populated || updated);
    } catch (_) {
      getIo().emit('updatedReport', updated);
    }
  });
  res.json(updated);
});

const resubmitReport = asyncHandler(async (req, res) => {
  const rep = await Report.findById(req.params.id);
  if (!rep) {
    res.status(404);
    throw new Error('Report not found');
  }

  if (String(rep.type || '').toLowerCase() !== 'task') {
    res.status(400);
    throw new Error('Only task reports can be resubmitted');
  }

  const isAdmin = req.user && req.user.role === 'admin';
  const isOwner = req.user && rep.employee && rep.employee.toString() === req.user._id.toString();
  if (!isAdmin && !isOwner) {
    res.status(403);
    throw new Error('Not authorized to resubmit this report');
  }

  const now = new Date();
  const allowUntil = rep.resubmitUntil;
  const canResubmit =
    allowUntil &&
    allowUntil instanceof Date &&
    !Number.isNaN(allowUntil.getTime()) &&
    allowUntil > now;
  if (!canResubmit && !isAdmin) {
    res.status(403);
    throw new Error('Resubmission window closed');
  }

  const { content, attachments } = req.body || {};
  if (content && typeof content === 'string' && content.length > 10000) {
    res.status(400);
    throw new Error('Report content is too long (max 10000 characters)');
  }

  rep.content = typeof content === 'string' ? content : '';
  rep.attachments = Array.isArray(attachments) ? attachments : [];
  rep.status = 'submitted';
  rep.submittedAt = now;
  rep.resubmitUntil = undefined;
  const updated = await rep.save();
  setImmediate(async () => {
    try {
      const populated = await populateReportById(updated._id);
      getIo().emit('updatedReport', populated || updated);
    } catch (_) {
      getIo().emit('updatedReport', updated);
    }
  });
  res.json(updated);
});

module.exports = {
  createReport,
  listReports,
  getReportById,
  replaceReportAttachments,
  updateReportStatus,
  reopenReportForResubmission,
  resubmitReport,
  deleteReport,
  getCurrentReports,
  getArchivedReports,
  archiveReport,
  restoreReport,
};