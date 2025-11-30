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
// @access Private/Admin
const listReports = asyncHandler(async (req, res) => {
  const { type, employeeId, taskId, geofenceId, startDate, endDate } = req.query;
  const filter = {};
  if (type) filter.type = type;
  if (employeeId) filter.employee = employeeId;
  if (taskId) filter.task = taskId;
  if (geofenceId) filter.geofence = geofenceId;
  if (startDate || endDate) {
    filter.submittedAt = {};
    if (startDate) filter.submittedAt.$gte = new Date(startDate);
    if (endDate) filter.submittedAt.$lte = new Date(endDate);
  }

  const reports = await Report.find(filter)
    .populate('employee', 'name email')
    .populate('task', 'title description')
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
    .populate('task', 'title description')
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

module.exports = {
  createReport,
  listReports,
  getReportById,
  updateReportStatus,
  deleteReport,
};