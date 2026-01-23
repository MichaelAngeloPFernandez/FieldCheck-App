const express = require('express');
const router = express.Router();
const {
  exportAttendancePDF,
  exportAttendanceExcel,
  exportTasksPDF,
  exportTasksExcel,
  exportCombinedExcel,
  emailReport,
} = require('../controllers/exportController');
const { protect, admin } = require('../middleware/authMiddleware');

// All export routes require authentication and admin role
router.use(protect, admin);

// Attendance export routes
router.get('/attendance/pdf', exportAttendancePDF);
router.get('/attendance/excel', exportAttendanceExcel);

// Task export routes
router.get('/tasks/pdf', exportTasksPDF);
router.get('/tasks/excel', exportTasksExcel);

// Combined export route
router.get('/combined/excel', exportCombinedExcel);

// Email report export
router.post('/email-report', emailReport);

module.exports = router;
