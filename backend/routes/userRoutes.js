const express = require('express');
const router = express.Router();
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
  importUsers,
} = require('../controllers/userController');
const { protect, admin } = require('../middleware/authMiddleware');

// Public routes
router.post('/login', authUser);
router.post('/', registerUser);
router.get('/verify/:token', verifyEmail);
router.post('/forgot-password', forgotPassword);
router.post('/reset-password/:token', resetPassword);

// Private user profile routes
router.get('/profile', protect, getUserProfile);
router.put('/profile', protect, updateUserProfile);

// Admin routes
router.get('/', protect, admin, getUsers); // GET /api/users?role=employee|admin
router.put('/:id', protect, admin, updateUserByAdmin); // Update fields including role and isActive
router.put('/:id/deactivate', protect, admin, deactivateUser);
router.put('/:id/reactivate', protect, admin, reactivateUser);
router.delete('/:id', protect, admin, deleteUser);
router.post('/import', protect, admin, importUsers);

module.exports = router;