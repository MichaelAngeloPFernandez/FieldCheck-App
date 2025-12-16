const express = require('express');
const router = express.Router();
const {
  checkIn,
  checkOut,
  logAttendance,
  getAttendanceRecords,
  getAttendanceById,
  updateAttendance,
  deleteAttendance,
  getAttendanceStatus,
  getAttendanceHistory,
  deleteMyAttendanceRecord,
  deleteMyAttendanceHistoryByMonth,
} = require('../controllers/attendanceController');

const { protect } = require('../middleware/authMiddleware');

// Order matters: more specific routes before generic ones
router.get('/status', protect, getAttendanceStatus);
router.get('/history', protect, getAttendanceHistory);
router.delete('/history', protect, deleteMyAttendanceHistoryByMonth);
router.delete('/history/:id', protect, deleteMyAttendanceRecord);
router.post('/checkin', protect, checkIn);
router.post('/checkout', protect, checkOut);
router.route('/').post(protect, logAttendance).get(protect, getAttendanceRecords);
router.route('/:id').get(protect, getAttendanceById).put(protect, updateAttendance).delete(protect, deleteAttendance);

module.exports = router;