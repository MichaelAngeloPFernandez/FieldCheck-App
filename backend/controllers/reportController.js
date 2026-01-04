const asyncHandler = require('express-async-handler');
const Report = require('../models/Report');
const Attendance = require('../models/Attendance');
const Task = require('../models/Task');
const { io } = require('../server');

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

  const reportData = {
    type,
    employee: employeeId || req.user._id,
    content: content || '',
    attachments: attachments || [],
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
  io.emit('newReport', created);
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
    .populate('task', 'title description difficulty')
    .populate('attendance')
    .populate('geofence', 'name')
    .sort({ submittedAt: -1 });

  res.json(reports);
});

// @desc Get report by id
// @route GET /api/reports/:id
// @access Private/Admin
const getReportById = asyncHandler(async (req, res) => {
  const rep = await Report.findById(req.params.id)
    .populate('employee', 'name email')
    .populate('task', 'title description difficulty')
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
  io.emit('updatedReport', updated);
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
  io.emit('deletedReport', req.params.id);
  res.status(204).send();
});

// @desc Get current (non-archived) reports
// @route GET /api/reports/current
// @access Private/Admin
const getCurrentReports = asyncHandler(async (req, res) => {
  const reports = await Report.find({ isArchived: { $ne: true } })
    .populate('employee', 'name email')
    .populate('task', 'title description difficulty')
    .populate('attendance')
    .populate('geofence', 'name')
    .sort({ submittedAt: -1 });
  res.json(reports);
});

// @desc Get archived reports
// @route GET /api/reports/archived
// @access Private/Admin
const getArchivedReports = asyncHandler(async (req, res) => {
  const reports = await Report.find({ isArchived: true })
    .populate('employee', 'name email')
    .populate('task', 'title description difficulty')
    .populate('attendance')
    .populate('geofence', 'name')
    .sort({ submittedAt: -1 });
  res.json(reports);
});

// @desc Archive a report
// @route PUT /api/reports/:id/archive
// @access Private/Admin
const archiveReport = asyncHandler(async (req, res) => {
  const rep = await Report.findById(req.params.id);
  if (!rep) {
    res.status(404);
    throw new Error('Report not found');
  }
  rep.isArchived = true;
  const updated = await rep.save();
  io.emit('reportArchived', updated);
  res.json(updated);
});

// @desc Restore an archived report
// @route PUT /api/reports/:id/restore
// @access Private/Admin
const restoreReport = asyncHandler(async (req, res) => {
  const rep = await Report.findById(req.params.id);
  if (!rep) {
    res.status(404);
    throw new Error('Report not found');
  }
  rep.isArchived = false;
  const updated = await rep.save();
  io.emit('reportRestored', updated);
  res.json(updated);
});

module.exports = {
  createReport,
  listReports,
  getReportById,
  updateReportStatus,
  deleteReport,
  getCurrentReports,
  getArchivedReports,
  archiveReport,
  restoreReport,
};