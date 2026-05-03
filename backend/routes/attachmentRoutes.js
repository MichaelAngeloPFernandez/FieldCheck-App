/**
 * Attachment Routes
 * 
 * POST   /api/attachments/upload - Upload file
 * GET    /api/attachments/:attachmentId - Retrieve metadata
 * GET    /api/resources/:resourceType/:resourceId/attachments - List for resource
 * DELETE /api/attachments/:attachmentId - Delete file
 * GET    /api/attachments/:storageName/file - Download file content
 */

const express = require('express');
const router = express.Router();
const Attachment = require('../models/Attachment');
const storageService = require('../services/storageService');
const { protect } = require('../middleware/authMiddleware');
const multer = require('multer');

// Configure multer for file uploads
const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 50 * 1024 * 1024 }, // 50MB max
  fileFilter: (req, file, cb) => {
    // Allowed file types: images, docs, PDFs
    const allowedMimes = [
      'image/jpeg',
      'image/png',
      'image/gif',
      'application/pdf',
      'application/msword',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'application/vnd.ms-excel',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    ];

    if (allowedMimes.includes(file.mimetype)) {
      cb(null, true);
    } else {
      cb(new Error(`File type ${file.mimetype} not allowed`));
    }
  },
});

/**
 * POST /api/attachments/upload
 * Upload a file and create attachment record
 */
router.post('/upload', protect, upload.single('file'), async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ error: 'No file provided' });
    }

    const { resourceType, resourceId } = req.body;

    // Validate input
    if (!resourceType || !resourceId) {
      return res.status(400).json({
        error: 'resourceType and resourceId required',
      });
    }

    if (!['report', 'task', 'ticket'].includes(resourceType)) {
      return res.status(400).json({
        error: 'Invalid resourceType (must be report, task, or ticket)',
      });
    }

    // Save attachment
    const attachment = await storageService.saveAttachment({
      resourceType,
      resourceId,
      fileName: req.file.originalname,
      fileData: req.file.buffer,
      fileType: req.file.mimetype,
      uploadedBy: req.user._id,
    });

    res.status(201).json({
      _id: attachment._id,
      fileName: attachment.fileName,
      fileSize: attachment.fileSize,
      url: attachment.url,
      uploadedAt: attachment.uploadedAt,
    });
  } catch (error) {
    console.error('Upload error:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * GET /api/attachments/:attachmentId
 * Get attachment metadata
 */
router.get('/:attachmentId', protect, async (req, res) => {
  try {
    const attachment = await Attachment.findById(req.params.attachmentId);

    if (!attachment) {
      return res.status(404).json({ error: 'Attachment not found' });
    }

    if (attachment.isDeleted) {
      return res.status(404).json({ error: 'Attachment deleted' });
    }

    res.json({
      _id: attachment._id,
      fileName: attachment.fileName,
      fileSize: attachment.fileSize,
      fileType: attachment.fileType,
      url: attachment.url,
      uploadedAt: attachment.uploadedAt,
      uploadedBy: attachment.uploadedBy,
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

/**
 * GET /api/resources/:resourceType/:resourceId/attachments
 * List all attachments for a resource
 */
router.get('/resources/:resourceType/:resourceId/attachments', protect, async (req, res) => {
  try {
    const { resourceType, resourceId } = req.params;

    // Validate
    if (!['report', 'task', 'ticket'].includes(resourceType)) {
      return res.status(400).json({
        error: 'Invalid resourceType',
      });
    }

    const attachments = await storageService.getAttachmentsForResource(
      resourceType,
      resourceId
    );

    res.json({
      count: attachments.length,
      attachments,
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

/**
 * GET /api/attachments/:storageName/file
 * Download actual file content
 * Authorization: Any authenticated user (assumes resourceId ownership checked elsewhere)
 */
router.get('/:storageName/file', protect, async (req, res) => {
  try {
    const { storageName } = req.params;

    // Security: validate storageName format (prevent directory traversal)
    if (!/^[\d-a-zA-Z_.]+$/.test(storageName)) {
      return res.status(400).json({ error: 'Invalid file name' });
    }

    const fileData = await storageService.getFile(storageName);

    // Guess content type from extension
    const ext = storageName.split('.').pop().toLowerCase();
    const mimeTypes = {
      jpg: 'image/jpeg',
      jpeg: 'image/jpeg',
      png: 'image/png',
      gif: 'image/gif',
      pdf: 'application/pdf',
      doc: 'application/msword',
      docx: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      xls: 'application/vnd.ms-excel',
      xlsx: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    };

    const contentType = mimeTypes[ext] || 'application/octet-stream';
    res.setHeader('Content-Type', contentType);
    res.setHeader('Cache-Control', 'public, max-age=31536000'); // Cache for 1 year
    res.send(fileData);
  } catch (error) {
    if (error.message === 'File not found') {
      return res.status(404).json({ error: 'File not found' });
    }
    res.status(500).json({ error: error.message });
  }
});

/**
 * DELETE /api/attachments/:attachmentId
 * Soft delete an attachment
 */
router.delete('/:attachmentId', protect, async (req, res) => {
  try {
    const attachment = await Attachment.findById(req.params.attachmentId);

    if (!attachment) {
      return res.status(404).json({ error: 'Attachment not found' });
    }

    // Authorization: can only delete own uploads or if admin
    if (attachment.uploadedBy.toString() !== req.user._id.toString() &&
        req.user.role !== 'admin') {
      return res.status(403).json({ error: 'Not authorized' });
    }

    await storageService.deleteAttachment(req.params.attachmentId, req.user._id);

    res.json({ message: 'Attachment deleted' });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

module.exports = router;
