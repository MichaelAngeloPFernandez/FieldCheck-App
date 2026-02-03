const express = require('express');
const router = express.Router();
const mongoose = require('mongoose');
const { GridFSBucket, ObjectId } = require('mongodb');
const multer = require('multer');
const { protect, admin } = require('../middleware/authMiddleware');

const Report = require('../models/Report');

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

const upload = multer({
  storage: multer.memoryStorage(),
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
  async (req, res) => {
    if (!req.file) {
      return res.status(400).json({ message: 'No file uploaded' });
    }

    try {
      if (!mongoose.connection || !mongoose.connection.db) {
        return res.status(503).json({ message: 'Database not ready' });
      }

      const originalName = req.file.originalname || 'attachment';
      const safeName = originalName.replace(/[^a-zA-Z0-9._-]/g, '_');
      const ts = Date.now();
      const storedName = `${ts}-${safeName}`;

      const bucket = new GridFSBucket(mongoose.connection.db, {
        bucketName: 'reportAttachments',
      });

      const uploadStream = bucket.openUploadStream(storedName, {
        contentType: req.file.mimetype,
        metadata: {
          originalName,
          uploadedBy: req.user ? String(req.user._id) : undefined,
        },
      });

      uploadStream.on('error', (err) => {
        console.error('GridFS upload error:', err);
        return res.status(500).json({ message: 'Failed to upload attachment' });
      });

      uploadStream.on('finish', (file) => {
        const fileId = file && file._id ? String(file._id) : null;
        if (!fileId) {
          return res.status(500).json({ message: 'Upload succeeded but no file id returned' });
        }

        const qp = new URLSearchParams({ filename: originalName }).toString();
        const relPath = `/api/reports/attachments/${fileId}?${qp}`;
        return res.status(201).json({
          path: relPath,
          originalName,
          size: req.file.size,
          mimeType: req.file.mimetype,
        });
      });

      uploadStream.end(req.file.buffer);
    } catch (e) {
      console.error('Report attachment upload failed:', e);
      return res.status(500).json({ message: 'Failed to upload attachment' });
    }
  }
);

router.get('/attachments/:id', protect, async (req, res) => {
  const id = String(req.params.id || '').trim();
  if (!id) {
    return res.status(400).json({ message: 'Missing attachment id' });
  }

  let fileId;
  try {
    fileId = new ObjectId(id);
  } catch (_) {
    return res.status(400).json({ message: 'Invalid attachment id' });
  }

  try {
    if (!mongoose.connection || !mongoose.connection.db) {
      return res.status(503).json({ message: 'Database not ready' });
    }

    if (!req.user || !req.user._id) {
      return res.status(401).json({ message: 'User not authenticated' });
    }

    const isAdmin = req.user && req.user.role === 'admin';
    if (!isAdmin) {
      const escapedId = id.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
      const idRegex = new RegExp(escapedId);
      const report = await Report.findOne({
        employee: req.user._id,
        attachments: { $elemMatch: { $regex: idRegex } },
      })
        .select('_id')
        .lean();

      if (!report) {
        return res.status(404).json({ message: 'Attachment not found' });
      }
    }

    const bucket = new GridFSBucket(mongoose.connection.db, {
      bucketName: 'reportAttachments',
    });

    const files = await bucket
      .find({ _id: fileId })
      .limit(1)
      .toArray();

    if (!files || files.length === 0) {
      return res.status(404).json({ message: 'Attachment not found' });
    }

    const file = files[0];
    const contentType =
      (file && file.contentType) ||
      (file && file.metadata && file.metadata.mimeType) ||
      'application/octet-stream';

    const qDownload = String(req.query.download || '').trim();
    const download = qDownload === '1' || qDownload.toLowerCase() === 'true';
    const requestedName = String(req.query.filename || '').trim();
    const fallbackName =
      (file && file.metadata && file.metadata.originalName) || file.filename || id;
    const filename = requestedName || fallbackName;

    res.setHeader('Content-Type', contentType);
    if (typeof file.length === 'number') {
      res.setHeader('Content-Length', String(file.length));
    }
    res.setHeader(
      'Content-Disposition',
      `${download ? 'attachment' : 'inline'}; filename="${filename.replace(/\"/g, '')}"`
    );

    const stream = bucket.openDownloadStream(fileId);
    stream.on('error', (err) => {
      console.error('GridFS download error:', err);
      if (!res.headersSent) {
        res.status(500).json({ message: 'Failed to read attachment' });
      } else {
        res.end();
      }
    });

    return stream.pipe(res);
  } catch (e) {
    console.error('Attachment streaming failed:', e);
    return res.status(500).json({ message: 'Failed to read attachment' });
  }
});

// Report management
// NOTE: listing reports is allowed for any authenticated user.
// The controller should enforce role-based filtering (employees should only see their own).
router.get('/', protect, listReports);

// Admin-only report management
router.get('/current', protect, admin, getCurrentReports);
router.get('/archived', protect, admin, getArchivedReports);
router.put('/:id/archive', protect, admin, archiveReport);
router.put('/:id/restore', protect, admin, restoreReport);

// Generic /:id routes (must be LAST)
router.get('/:id', protect, admin, getReportById);
router.patch('/:id/status', protect, admin, updateReportStatus);
router.delete('/:id', protect, admin, deleteReport);

module.exports = router;