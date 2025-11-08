const express = require('express');
const router = express.Router();
const { protect, admin } = require('../middleware/authMiddleware');
const {
  createReport,
  listReports,
  getReportById,
  updateReportStatus,
  deleteReport,
} = require('../controllers/reportController');

// Create report (employee or admin)
router.post('/', protect, createReport);

// Admin-only report management
router.get('/', protect, admin, listReports);
router.get('/:id', protect, admin, getReportById);
router.patch('/:id/status', protect, admin, updateReportStatus);
router.delete('/:id', protect, admin, deleteReport);

module.exports = router;