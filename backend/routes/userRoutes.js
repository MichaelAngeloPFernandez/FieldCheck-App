const express = require('express');
const router = express.Router();
const path = require('path');
const fs = require('fs');
const multer = require('multer');
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

const avatarStorage = multer.diskStorage({
  destination: (req, file, cb) => {
    const baseDir = path.join(__dirname, '..', 'uploads', 'avatars');
    fs.mkdirSync(baseDir, { recursive: true });
    cb(null, baseDir);
  },
  filename: (req, file, cb) => {
    const safeName = file.originalname.replace(/[^a-zA-Z0-9._-]/g, '_');
    const ts = Date.now();
    cb(null, `${ts}-${safeName}`);
  },
});

const avatarUpload = multer({
  storage: avatarStorage,
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
router.post('/upload/avatar', protect, avatarUpload.single('avatar'), (req, res) => {
  if (!req.file) {
    return res.status(400).json({ message: 'No file uploaded' });
  }
  const relPath = `/uploads/avatars/${req.file.filename}`;
  return res.status(200).json({
    avatarUrl: relPath,
    path: relPath,
    originalName: req.file.originalname,
    size: req.file.size,
    mimeType: req.file.mimetype,
  });
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