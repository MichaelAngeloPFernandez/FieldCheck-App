const asyncHandler = require('express-async-handler');
const Attendance = require('../models/Attendance');
const Task = require('../models/Task');
const Report = require('../models/Report');
const ReportExportService = require('../services/reportExportService');
const sendEmail = require('../utils/emailService');

const toAbsoluteUrl = (req, value) => {
  const raw = String(value || '').trim();
  if (!raw) return '';
  if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
  if (raw.startsWith('/')) {
    const host = req.get('host');
    if (!host) return raw;
    return `${req.protocol}://${host}${raw}`;
  }
  return raw;
};

const streamToBuffer = (stream) =>
  new Promise((resolve, reject) => {
    const chunks = [];
    stream.on('data', (chunk) => chunks.push(chunk));
    stream.on('end', () => resolve(Buffer.concat(chunks)));
    stream.on('error', reject);
  });

const parseRecipients = (value) => {
  if (!value) return [];
  if (Array.isArray(value)) {
    return value.map((entry) => String(entry).trim()).filter(Boolean);
  }
  if (typeof value === 'string') {
    return value
      .split(/[,;]+/)
      .map((entry) => entry.trim())
      .filter(Boolean);
  }
  return [];
};

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
      return res.status(403).json({ message: 'Only administrators can export Excel reports' });
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

    // Generate Excel
    console.log(`Generating Excel with ${records.length} records and ${tasks.length} tasks`);
    
    try {
      const buffer = await ReportExportService.generateAttendanceExcel(records, { tasks });

      // Set response headers
      res.setHeader(
        'Content-Type',
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
      res.setHeader('Content-Disposition', `attachment; filename="attendance_${Date.now()}.xlsx"`);

      // Send Excel buffer
      res.send(buffer);
    } catch (excelError) {
      console.error('Excel generation exception:', excelError.message);
      console.error('Stack:', excelError.stack);
      if (!res.headersSent) {
        res.status(500).json({ message: 'Excel generation failed: ' + excelError.message });
      }
    }
  } catch (error) {
    console.error('Export Excel error:', error);
    res.status(500).json({ message: 'Failed to export Excel: ' + error.message });
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

  const { startDate, endDate, status, employeeId, taskId, archived } = req.query;

  // Build report filter
  const filter = { type: 'task' };
  if (employeeId) filter.employee = employeeId;
  if (taskId) filter.task = taskId;

  if (startDate || endDate) {
    filter.submittedAt = {};
    if (startDate) filter.submittedAt.$gte = new Date(startDate);
    if (endDate) filter.submittedAt.$lte = new Date(endDate);
  }

  if (archived === 'true') {
    filter.isArchived = true;
  } else if (archived === 'false') {
    filter.isArchived = { $ne: true };
  }

  if (status) {
    filter.status = String(status).trim();
  }

  const reports = await Report.find(filter)
    .populate('employee', 'name email employeeId')
    .populate('task', 'title difficulty dueDate status isArchived')
    .sort({ submittedAt: -1 });

  const now = new Date();
  const rows = reports.map((rep) => {
    const obj = rep.toObject({ virtuals: true });
    let taskIsOverdue = false;
    if (obj.task && obj.task.dueDate) {
      try {
        const due = new Date(obj.task.dueDate);
        const tStatus = obj.task.status || 'pending';
        const isCompleted = String(tStatus).toLowerCase() === 'completed';
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

    const attachments = Array.isArray(obj.attachments) ? obj.attachments : [];
    const attachmentUrls = attachments.map((u) => toAbsoluteUrl(req, u));

    return {
      reportId: String(obj._id),
      employeeName: obj.employee?.name || '',
      employeeEmail: obj.employee?.email || '',
      employeeCode: obj.employee?.employeeId || '',
      taskTitle: obj.task?.title || '',
      taskDifficulty: obj.task?.difficulty || '',
      reportStatus: obj.status || '',
      grade: obj.grade || '',
      submittedAt: obj.submittedAt || obj.createdAt,
      taskDueDate: obj.task?.dueDate || null,
      taskIsOverdue,
      attachmentCount: attachmentUrls.filter(Boolean).length,
      attachments: attachmentUrls.filter(Boolean).join('\n'),
    };
  });

  const dateRange = startDate && endDate
    ? `${new Date(startDate).toLocaleDateString()} - ${new Date(endDate).toLocaleDateString()}`
    : 'All Dates';

  const pdfStream = ReportExportService.generateTaskReportPDF(rows, { dateRange });

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
  const { startDate, endDate, status, employeeId, taskId, archived } = req.query;

  const filter = { type: 'task' };
  if (employeeId) filter.employee = employeeId;
  if (taskId) filter.task = taskId;

  if (startDate || endDate) {
    filter.submittedAt = {};
    if (startDate) filter.submittedAt.$gte = new Date(startDate);
    if (endDate) filter.submittedAt.$lte = new Date(endDate);
  }

  if (archived === 'true') {
    filter.isArchived = true;
  } else if (archived === 'false') {
    filter.isArchived = { $ne: true };
  }

  if (status) {
    filter.status = String(status).trim();
  }

  const reports = await Report.find(filter)
    .populate('employee', 'name email employeeId')
    .populate('task', 'title difficulty dueDate status isArchived')
    .sort({ submittedAt: -1 });

  const now = new Date();
  const rows = reports.map((rep) => {
    const obj = rep.toObject({ virtuals: true });
    let taskIsOverdue = false;
    if (obj.task && obj.task.dueDate) {
      try {
        const due = new Date(obj.task.dueDate);
        const tStatus = obj.task.status || 'pending';
        const isCompleted = String(tStatus).toLowerCase() === 'completed';
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

    const attachments = Array.isArray(obj.attachments) ? obj.attachments : [];
    const attachmentUrls = attachments.map((u) => toAbsoluteUrl(req, u));

    return {
      reportId: String(obj._id),
      employeeName: obj.employee?.name || '',
      employeeEmail: obj.employee?.email || '',
      employeeCode: obj.employee?.employeeId || '',
      taskTitle: obj.task?.title || '',
      taskDifficulty: obj.task?.difficulty || '',
      reportStatus: obj.status || '',
      grade: obj.grade || '',
      submittedAt: obj.submittedAt || obj.createdAt,
      taskDueDate: obj.task?.dueDate || null,
      taskIsOverdue,
      attachmentCount: attachmentUrls.filter(Boolean).length,
      attachments: attachmentUrls.filter(Boolean),
    };
  });

  const buffer = await ReportExportService.generateTaskReportExcel(rows);

  // Set response headers
  res.setHeader('Content-Type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
  res.setHeader('Content-Disposition', `attachment; filename="tasks_${Date.now()}.xlsx"`);

  // Send buffer
  res.send(buffer);
});

// @desc    Email report export (Admin Only)
// @route   POST /api/export/email-report
// @access  Private/Admin
const emailReport = asyncHandler(async (req, res) => {
  try {
    if (req.user.role !== 'admin') {
      return res.status(403).json({ message: 'Only administrators can email reports' });
    }

    const {
      reportType: rawType,
      type,
      format: rawFormat,
      recipients,
      emails,
      email,
      startDate,
      endDate,
      employeeId,
      geofenceId,
      status,
      assignedTo,
    } = req.body || {};

    const reportType = (rawType || type || '').toString().trim().toLowerCase();
    const normalizedType = reportType;
    const format = (rawFormat || 'pdf').toString().trim().toLowerCase();
    const recipientList = parseRecipients(recipients || emails || email);

    if (!normalizedType || !['attendance', 'task', 'tasks'].includes(normalizedType)) {
      return res.status(400).json({ message: 'Invalid report type' });
    }
    if (!recipientList.length) {
      return res.status(400).json({ message: 'Recipients are required' });
    }
    if (!['pdf', 'xlsx', 'csv'].includes(format)) {
      return res.status(400).json({ message: 'Invalid report format' });
    }

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

    let attachmentBuffer;
    let filename;
    let mimeType;
    const dateRange = startDate && endDate
      ? `${new Date(startDate).toLocaleDateString()} - ${new Date(endDate).toLocaleDateString()}`
      : 'All Dates';

    if (normalizedType === 'attendance') {
      const filter = {};
      if (startDate || endDate) {
        filter.checkIn = {};
        if (startDate) filter.checkIn.$gte = new Date(startDate);
        if (endDate) filter.checkIn.$lte = new Date(endDate);
      }
      if (employeeId) filter.employee = employeeId;
      if (geofenceId) filter.geofence = geofenceId;

      const records = await Attendance.find(filter)
        .populate('employee', 'name email')
        .populate('geofence', 'name')
        .sort({ checkIn: -1 });

      let tasks = [];
      if (geofenceId) {
        const taskFilter = { geofence: geofenceId };
        if (startDate || endDate) {
          taskFilter.dueDate = {};
          if (startDate) taskFilter.dueDate.$gte = new Date(startDate);
          if (endDate) taskFilter.dueDate.$lte = new Date(endDate);
        }
        tasks = await Task.find(taskFilter)
          .populate('assignedBy', 'name email')
          .sort({ dueDate: -1 });
      }

      if (format === 'pdf') {
        const pdfStream = ReportExportService.generateAttendancePDF(records, { dateRange, tasks });
        attachmentBuffer = await streamToBuffer(pdfStream);
        filename = `attendance_${Date.now()}.pdf`;
        mimeType = 'application/pdf';
      } else if (format === 'xlsx') {
        attachmentBuffer = await ReportExportService.generateAttendanceExcel(records, { tasks });
        filename = `attendance_${Date.now()}.xlsx`;
        mimeType = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      } else {
        const csv = ReportExportService.generateAttendanceCSV(records, tasks);
        attachmentBuffer = Buffer.from(csv, 'utf8');
        filename = `attendance_${Date.now()}.csv`;
        mimeType = 'text/csv; charset=utf-8';
      }
    } else if (normalizedType === 'tasks') {
      if (format === 'csv') {
        return res.status(400).json({ message: 'CSV export is only available for attendance reports' });
      }

      const filter = {};
      if (startDate || endDate) {
        filter.dueDate = {};
        if (startDate) filter.dueDate.$gte = new Date(startDate);
        if (endDate) filter.dueDate.$lte = new Date(endDate);
      }
      if (status) filter.status = status;
      if (assignedTo) filter.assignedTo = assignedTo;

      const tasks = await Task.find(filter)
        .populate('assignedBy', 'name')
        .sort({ dueDate: -1 });

      if (format === 'pdf') {
        const pdfStream = ReportExportService.generateTaskPDF(tasks, { dateRange });
        attachmentBuffer = await streamToBuffer(pdfStream);
        filename = `tasks_${Date.now()}.pdf`;
        mimeType = 'application/pdf';
      } else {
        attachmentBuffer = await ReportExportService.generateTaskExcel(tasks);
        filename = `tasks_${Date.now()}.xlsx`;
        mimeType = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      }
    } else {
      // Task reports
      const filter = { type: 'task' };
      if (startDate || endDate) {
        filter.submittedAt = {};
        if (startDate) filter.submittedAt.$gte = new Date(startDate);
        if (endDate) filter.submittedAt.$lte = new Date(endDate);
      }
      if (employeeId) filter.employee = employeeId;
      if (status) filter.status = status;
      if (archived === 'true') {
        filter.isArchived = true;
      } else if (archived === 'false') {
        filter.isArchived = { $ne: true };
      }

      const reports = await Report.find(filter)
        .populate('employee', 'name email employeeId')
        .populate('task', 'title difficulty dueDate status isArchived')
        .sort({ submittedAt: -1 });

      const now = new Date();
      const rows = reports.map((rep) => {
        const obj = rep.toObject({ virtuals: true });
        let taskIsOverdue = false;
        if (obj.task && obj.task.dueDate) {
          try {
            const due = new Date(obj.task.dueDate);
            const tStatus = obj.task.status || 'pending';
            const isCompleted = String(tStatus).toLowerCase() === 'completed';
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

        const attachments = Array.isArray(obj.attachments) ? obj.attachments : [];
        const attachmentUrls = attachments.map((u) => toAbsoluteUrl(req, u));

        return {
          reportId: String(obj._id),
          employeeName: obj.employee?.name || '',
          employeeEmail: obj.employee?.email || '',
          employeeCode: obj.employee?.employeeId || '',
          taskTitle: obj.task?.title || '',
          taskDifficulty: obj.task?.difficulty || '',
          reportStatus: obj.status || '',
          grade: obj.grade || '',
          submittedAt: obj.submittedAt || obj.createdAt,
          taskDueDate: obj.task?.dueDate || null,
          taskIsOverdue,
          attachmentCount: attachmentUrls.filter(Boolean).length,
          attachments: attachmentUrls.filter(Boolean).join('\n'),
        };
      });

      if (format === 'pdf') {
        const pdfStream = ReportExportService.generateTaskReportPDF(rows, { dateRange });
        attachmentBuffer = await streamToBuffer(pdfStream);
        filename = `task_reports_${Date.now()}.pdf`;
        mimeType = 'application/pdf';
      } else if (format === 'xlsx') {
        attachmentBuffer = await ReportExportService.generateTaskReportExcel(rows);
        filename = `task_reports_${Date.now()}.xlsx`;
        mimeType = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      } else {
        return res.status(400).json({ message: 'CSV export is only available for attendance reports' });
      }
    }

    await sendEmail({
      email: recipientList,
      subject: `FieldCheck ${normalizedType} report`,
      message: `<p>Attached is your ${normalizedType} report (${format.toUpperCase()}).</p>`,
      attachments: [
        {
          filename,
          content: attachmentBuffer,
          contentType: mimeType,
        },
      ],
    });

    res.json({ message: 'Report emailed successfully' });
  } catch (error) {
    console.error('Email report error:', error);
    res.status(500).json({ message: 'Failed to email report: ' + error.message });
  }
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
  emailReport,
};
