const express = require('express');
const router = express.Router();
const multer = require('multer');
const mongoose = require('mongoose');
const { GridFSBucket, ObjectId } = require('mongodb');

const {
  authUser,
  registerUser,
  verifyEmail,
  forgotPassword,
  resetPassword,
  getUserProfile,
  updateUserProfile,
  deactivateUser,
  reactivateUser,
  deleteUser,
  getUsers,
  updateUserByAdmin,
  resetUserPasswordByAdmin,
  importUsers,
} = require('../controllers/userController');
const { protect, admin } = require('../middleware/authMiddleware');
const { refreshAccessToken, logout, googleSignIn } = require('../controllers/userController');

const avatarUpload = multer({
  storage: multer.memoryStorage(),
  limits: {
    fileSize: 5 * 1024 * 1024, // 5 MB max avatar
  },
});

// Public routes
router.post('/login', authUser);
router.post('/', registerUser);
router.get('/verify/:token', verifyEmail);
router.post('/forgot-password', forgotPassword);
router.post('/reset-password/:token', resetPassword);
router.post('/refresh-token', refreshAccessToken);
router.post('/logout', protect, logout);
router.post('/google-signin', googleSignIn);

// Upload avatar (employee/admin)
// POST /api/users/upload/avatar (preferred)
router.post('/upload/avatar', protect, avatarUpload.single('avatar'), async (req, res) => {
  if (!req.file) {
    return res.status(400).json({ message: 'No file uploaded' });
  }

  if (!mongoose.connection || !mongoose.connection.db) {
    return res.status(503).json({ message: 'Database not ready' });
  }

  const originalName = req.file.originalname || 'avatar';
  const safeName = originalName.replace(/[^a-zA-Z0-9._-]/g, '_');
  const ts = Date.now();
  const storedName = `${ts}-${safeName}`;

  const bucket = new GridFSBucket(mongoose.connection.db, {
    bucketName: 'userAvatars',
  });

  const uploadStream = bucket.openUploadStream(storedName, {
    contentType: req.file.mimetype,
    metadata: {
      originalName,
      uploadedBy: req.user ? String(req.user._id) : undefined,
    },
  });

  uploadStream.on('error', (err) => {
    console.error('Avatar GridFS upload error:', err);
    return res.status(500).json({ message: 'Failed to upload avatar' });
  });

  uploadStream.on('finish', (file) => {
    const rawId = (file && file._id) || uploadStream.id;
    const fileId = rawId ? String(rawId) : null;
    if (!fileId) {
      return res.status(500).json({ message: 'Upload succeeded but no file id returned' });
    }

    const qp = new URLSearchParams({ filename: originalName }).toString();
    const relPath = `/api/users/avatar/${fileId}?${qp}`;
    return res.status(200).json({
      avatarUrl: relPath,
      path: relPath,
      originalName,
      size: req.file.size,
      mimeType: req.file.mimetype,
    });
  });

  uploadStream.end(req.file.buffer);
});

// Public avatar stream (no auth header available for NetworkImage)
router.get('/avatar/:id', async (req, res) => {
  const id = String(req.params.id || '').trim();
  if (!id) {
    return res.status(400).json({ message: 'Missing avatar id' });
  }

  let fileId;
  try {
    fileId = new ObjectId(id);
  } catch (_) {
    return res.status(400).json({ message: 'Invalid avatar id' });
  }

  try {
    if (!mongoose.connection || !mongoose.connection.db) {
      return res.status(503).json({ message: 'Database not ready' });
    }

    const bucket = new GridFSBucket(mongoose.connection.db, {
      bucketName: 'userAvatars',
    });

    const files = await bucket.find({ _id: fileId }).limit(1).toArray();
    if (!files || files.length === 0) {
      return res.status(404).json({ message: 'Avatar not found' });
    }

    const file = files[0];
    const contentType =
      (file && file.contentType) ||
      (file && file.metadata && file.metadata.mimeType) ||
      'application/octet-stream';

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
      `inline; filename="${filename.replace(/\"/g, '')}"`,
    );

    const stream = bucket.openDownloadStream(fileId);
    stream.on('error', (err) => {
      console.error('Avatar GridFS download error:', err);
      if (!res.headersSent) {
        res.status(500).json({ message: 'Failed to read avatar' });
      } else {
        res.end();
      }
    });

    return stream.pipe(res);
  } catch (e) {
    console.error('Avatar streaming failed:', e);
    return res.status(500).json({ message: 'Failed to read avatar' });
  }
});

// Private user profile routes
router.get('/profile', protect, getUserProfile);
router.put('/profile', protect, updateUserProfile);

// Admin routes
router.get('/', protect, admin, getUsers); // GET /api/users?role=employee|admin
router.put('/:id', protect, admin, updateUserByAdmin); // Update fields including role and isActive
router.put('/:id/reset-password-admin', protect, admin, resetUserPasswordByAdmin);
router.put('/:id/deactivate', protect, admin, deactivateUser);
router.put('/:id/reactivate', protect, admin, reactivateUser);
router.delete('/:id', protect, admin, deleteUser);
router.post('/import', protect, admin, importUsers);

module.exports = router;