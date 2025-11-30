const asyncHandler = require('express-async-handler');
const Attendance = require('../models/Attendance');
const Task = require('../models/Task');
const ReportExportService = require('../services/reportExportService');

// @desc    Export attendance records as PDF (Admin Only)
// @route   GET /api/export/attendance/pdf
// @access  Private/Admin
const exportAttendancePDF = asyncHandler(async (req, res) => {
  try {
    // Verify admin role
    if (req.user.role !== 'admin') {
      return res.status(403).json({ message: 'Only administrators can export PDF reports' });
    }

    const { startDate, endDate, employeeId, geofenceId } = req.query;

    // Validate dates
    if (startDate) {
      const start = new Date(startDate);
      if (isNaN(start.getTime())) {
        return res.status(400).json({ message: 'Invalid startDate format' });
      }
    }
    if (endDate) {
      const end = new Date(endDate);
      if (isNaN(end.getTime())) {
        return res.status(400).json({ message: 'Invalid endDate format' });
      }
    }

    // Build filter
    const filter = {};
    if (startDate || endDate) {
      filter.checkIn = {};
      if (startDate) filter.checkIn.$gte = new Date(startDate);
      if (endDate) filter.checkIn.$lte = new Date(endDate);
    }
    if (employeeId) filter.employee = employeeId;
    if (geofenceId) filter.geofence = geofenceId;

    // Fetch records
    const records = await Attendance.find(filter)
      .populate('employee', 'name email')
      .populate('geofence', 'name')
      .sort({ checkIn: -1 });

    // Fetch tasks for this geofence if geofenceId is provided
    let tasks = [];
    if (geofenceId) {
      try {
        console.log(`Fetching tasks for geofence: ${geofenceId}`);
        const taskFilter = { geofence: geofenceId };
        if (startDate || endDate) {
          taskFilter.dueDate = {};
          if (startDate) taskFilter.dueDate.$gte = new Date(startDate);
          if (endDate) taskFilter.dueDate.$lte = new Date(endDate);
        }
        console.log('Task filter:', JSON.stringify(taskFilter));
        tasks = await Task.find(taskFilter)
          .populate('assignedBy', 'name email')
          .sort({ dueDate: -1 });
        console.log(`✓ Found ${tasks.length} tasks for geofence ${geofenceId}`);
      } catch (e) {
        console.error('Error fetching tasks for geofence:', e.message);
        console.error('Stack:', e.stack);
        tasks = [];
      }
    }

    // Generate PDF
    const dateRange = startDate && endDate
      ? `${new Date(startDate).toLocaleDateString()} - ${new Date(endDate).toLocaleDateString()}`
      : 'All Dates';

    console.log(`Generating PDF with ${records.length} records and ${tasks.length} tasks`);
    
    try {
      const pdfStream = ReportExportService.generateAttendancePDF(records, { dateRange, tasks });

      // Set response headers
      res.setHeader('Content-Type', 'application/pdf');
      res.setHeader('Content-Disposition', `attachment; filename="attendance_${Date.now()}.pdf"`);

      // Pipe PDF to response
      pdfStream.pipe(res);

      // Handle errors
      pdfStream.on('error', (err) => {
        console.error('PDF generation error:', err);
        if (!res.headersSent) {
          res.status(500).json({ message: 'Failed to generate PDF' });
        }
      });
    } catch (pdfError) {
      console.error('PDF generation exception:', pdfError.message);
      console.error('Stack:', pdfError.stack);
      if (!res.headersSent) {
        res.status(500).json({ message: 'PDF generation failed: ' + pdfError.message });
      }
    }
  } catch (error) {
    console.error('Export PDF error:', error);
    res.status(500).json({ message: 'Failed to export PDF: ' + error.message });
  }
});

// @desc    Export attendance records as Excel
// @route   GET /api/export/attendance/excel
// @access  Private/Admin
const exportAttendanceExcel = asyncHandler(async (req, res) => {
  try {
    // Verify admin role
    if (req.user.role !== 'admin') {
      return res.status(403).json({ message: 'Only administrators can export CSV reports' });
    }

    const { startDate, endDate, employeeId, geofenceId } = req.query;

    // Validate dates
    if (startDate) {
      const start = new Date(startDate);
      if (isNaN(start.getTime())) {
        return res.status(400).json({ message: 'Invalid startDate format' });
      }
    }
    if (endDate) {
      const end = new Date(endDate);
      if (isNaN(end.getTime())) {
        return res.status(400).json({ message: 'Invalid endDate format' });
      }
    }

    // Build filter
    const filter = {};
    if (startDate || endDate) {
      filter.checkIn = {};
      if (startDate) filter.checkIn.$gte = new Date(startDate);
      if (endDate) filter.checkIn.$lte = new Date(endDate);
    }
    if (employeeId) filter.employee = employeeId;
    if (geofenceId) filter.geofence = geofenceId;

    // Fetch records
    const records = await Attendance.find(filter)
      .populate('employee', 'name email')
      .populate('geofence', 'name')
      .sort({ checkIn: -1 });

    // Fetch tasks for this geofence if geofenceId is provided
    let tasks = [];
    if (geofenceId) {
      try {
        console.log(`Fetching tasks for geofence: ${geofenceId}`);
        const taskFilter = { geofence: geofenceId };
        if (startDate || endDate) {
          taskFilter.dueDate = {};
          if (startDate) taskFilter.dueDate.$gte = new Date(startDate);
          if (endDate) taskFilter.dueDate.$lte = new Date(endDate);
        }
        console.log('Task filter:', JSON.stringify(taskFilter));
        tasks = await Task.find(taskFilter)
          .populate('assignedBy', 'name email')
          .sort({ dueDate: -1 });
        console.log(`✓ Found ${tasks.length} tasks for geofence ${geofenceId}`);
      } catch (e) {
        console.error('Error fetching tasks for geofence:', e.message);
        console.error('Stack:', e.stack);
        tasks = [];
      }
    }

    // Generate CSV
    console.log(`Generating CSV with ${records.length} records and ${tasks.length} tasks`);
    
    try {
      const csv = ReportExportService.generateAttendanceCSV(records, tasks);

      // Set response headers
      res.setHeader('Content-Type', 'text/csv; charset=utf-8');
      res.setHeader('Content-Disposition', `attachment; filename="attendance_${Date.now()}.csv"`);

      // Send CSV
      res.send(csv);
    } catch (csvError) {
      console.error('CSV generation exception:', csvError.message);
      console.error('Stack:', csvError.stack);
      if (!res.headersSent) {
        res.status(500).json({ message: 'CSV generation failed: ' + csvError.message });
      }
    }
  } catch (error) {
    console.error('Export CSV error:', error);
    res.status(500).json({ message: 'Failed to export CSV: ' + error.message });
  }
});

// @desc    Export tasks as PDF (Admin Only)
// @route   GET /api/export/tasks/pdf
// @access  Private/Admin
const exportTasksPDF = asyncHandler(async (req, res) => {
  // Verify admin role
  if (req.user.role !== 'admin') {
    return res.status(403).json({ message: 'Only administrators can export PDF reports' });
  }

  const { startDate, endDate, status, assignedTo } = req.query;

  // Build filter
  const filter = {};
  if (startDate || endDate) {
    filter.dueDate = {};
    if (startDate) filter.dueDate.$gte = new Date(startDate);
    if (endDate) filter.dueDate.$lte = new Date(endDate);
  }
  if (status) filter.status = status;
  if (assignedTo) filter.assignedTo = assignedTo;

  // Fetch tasks
  const tasks = await Task.find(filter)
    .populate('assignedBy', 'name')
    .sort({ dueDate: -1 });

  // Generate PDF
  const dateRange = startDate && endDate
    ? `${new Date(startDate).toLocaleDateString()} - ${new Date(endDate).toLocaleDateString()}`
    : 'All Dates';

  const pdfStream = ReportExportService.generateTaskPDF(tasks, { dateRange });

  // Set response headers
  res.setHeader('Content-Type', 'application/pdf');
  res.setHeader('Content-Disposition', `attachment; filename="tasks_${Date.now()}.pdf"`);

  // Pipe PDF to response
  pdfStream.pipe(res);

  // Handle errors
  pdfStream.on('error', (err) => {
    console.error('PDF generation error:', err);
    if (!res.headersSent) {
      res.status(500).json({ message: 'Failed to generate PDF' });
    }
  });
});

// @desc    Export tasks as Excel
// @route   GET /api/export/tasks/excel
// @access  Private/Admin
const exportTasksExcel = asyncHandler(async (req, res) => {
  const { startDate, endDate, status, assignedTo } = req.query;

  // Build filter
  const filter = {};
  if (startDate || endDate) {
    filter.dueDate = {};
    if (startDate) filter.dueDate.$gte = new Date(startDate);
    if (endDate) filter.dueDate.$lte = new Date(endDate);
  }
  if (status) filter.status = status;
  if (assignedTo) filter.assignedTo = assignedTo;

  // Fetch tasks
  const tasks = await Task.find(filter)
    .populate('assignedBy', 'name')
    .sort({ dueDate: -1 });

  // Generate Excel
  const buffer = await ReportExportService.generateTaskExcel(tasks);

  // Set response headers
  res.setHeader('Content-Type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
  res.setHeader('Content-Disposition', `attachment; filename="tasks_${Date.now()}.xlsx"`);

  // Send buffer
  res.send(buffer);
});

// @desc    Export combined report (attendance + tasks) as Excel
// @route   GET /api/export/combined/excel
// @access  Private/Admin
const exportCombinedExcel = asyncHandler(async (req, res) => {
  const { startDate, endDate, employeeId, geofenceId } = req.query;

  // Build attendance filter
  const attendanceFilter = {};
  if (startDate || endDate) {
    attendanceFilter.checkIn = {};
    if (startDate) attendanceFilter.checkIn.$gte = new Date(startDate);
    if (endDate) attendanceFilter.checkIn.$lte = new Date(endDate);
  }
  if (employeeId) attendanceFilter.employee = employeeId;
  if (geofenceId) attendanceFilter.geofence = geofenceId;

  // Build task filter
  const taskFilter = {};
  if (startDate || endDate) {
    taskFilter.dueDate = {};
    if (startDate) taskFilter.dueDate.$gte = new Date(startDate);
    if (endDate) taskFilter.dueDate.$lte = new Date(endDate);
  }

  // Fetch data
  const [attendance, tasks] = await Promise.all([
    Attendance.find(attendanceFilter)
      .populate('employee', 'name email')
      .populate('geofence', 'name')
      .sort({ checkIn: -1 }),
    Task.find(taskFilter)
      .populate('assignedBy', 'name')
      .sort({ dueDate: -1 }),
  ]);

  // Generate Excel
  const buffer = await ReportExportService.generateCombinedExcel({
    attendance,
    tasks,
  });

  // Set response headers
  res.setHeader('Content-Type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
  res.setHeader('Content-Disposition', `attachment; filename="combined_report_${Date.now()}.xlsx"`);

  // Send buffer
  res.send(buffer);
});

module.exports = {
  exportAttendancePDF,
  exportAttendanceExcel,
  exportTasksPDF,
  exportTasksExcel,
  exportCombinedExcel,
};
