const express = require('express');
const router = express.Router();
const path = require('path');
const fs = require('fs');
const multer = require('multer');
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

const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    const baseDir = path.join(__dirname, '..', 'uploads', 'reports');
    fs.mkdirSync(baseDir, { recursive: true });
    cb(null, baseDir);
  },
  filename: (req, file, cb) => {
    const safeName = file.originalname.replace(/[^a-zA-Z0-9._-]/g, '_');
    const ts = Date.now();
    cb(null, `${ts}-${safeName}`);
  },
});

const upload = multer({
  storage,
  limits: {
    fileSize: 10 * 1024 * 1024, // 10 MB max per attachment
  },
});

// Create report (employee or admin)
router.post('/', protect, createReport);

// Upload a single attachment for a report (returns relative URL path)
router.post(
  '/upload',
  protect,
  upload.single('file'),
  (req, res) => {
    if (!req.file) {
      return res.status(400).json({ message: 'No file uploaded' });
    }

    const relPath = `/uploads/reports/${req.file.filename}`;
    res.status(201).json({
      path: relPath,
      originalName: req.file.originalname,
      size: req.file.size,
      mimeType: req.file.mimetype,
    });
  }
);

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