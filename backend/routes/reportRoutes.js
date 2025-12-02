const express = require('express');
const router = express.Router();
const { protect, admin } = require('../middleware/authMiddleware');
const {
  createReport,
  listReports,
  getReportById,
  updateReportStatus,
  deleteReport,
  getCurrentReports,
  getArchivedReports,
  archiveReport,
  restoreReport,
} = require('../controllers/reportController');

// Create report (employee or admin)
router.post('/', protect, createReport);

// Admin-only report management
router.get('/', protect, admin, listReports);

// Specific routes (must be BEFORE /:id to avoid conflicts)
router.get('/current', protect, admin, getCurrentReports);
router.get('/archived', protect, admin, getArchivedReports);
router.put('/:id/archive', protect, admin, archiveReport);
router.put('/:id/restore', protect, admin, restoreReport);

// Generic /:id routes (must be LAST)
router.get('/:id', protect, admin, getReportById);
router.patch('/:id/status', protect, admin, updateReportStatus);
router.delete('/:id', protect, admin, deleteReport);

module.exports = router;