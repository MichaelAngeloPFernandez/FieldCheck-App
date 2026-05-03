const express = require('express');
const router = express.Router();
const {
  checkIn,
  checkOut,
  logAttendance,
  getAttendanceRecords,
  archiveAttendanceRecord,
  restoreAttendanceRecord,
  getAttendanceById,
  updateAttendance,
  deleteAttendance,
  getAttendanceStatus,
  getAttendanceHistory,
  deleteMyAttendanceRecord,
  deleteMyAttendanceHistoryByMonth,
  getAllEmployeesAttendanceStatus,
} = require('../controllers/attendanceController');

const { protect, admin } = require('../middleware/authMiddleware');

// Order matters: more specific routes before generic ones
router.get('/status', protect, getAttendanceStatus);
router.get('/admin/all-status', protect, admin, getAllEmployeesAttendanceStatus);
router.get('/history', protect, getAttendanceHistory);
router.delete('/history', protect, deleteMyAttendanceHistoryByMonth);
router.delete('/history/:id', protect, deleteMyAttendanceRecord);
router.post('/checkin', protect, checkIn);
router.post('/checkout', protect, checkOut);
router.route('/').post(protect, logAttendance).get(protect, admin, getAttendanceRecords);
router.put('/:id/archive', protect, admin, archiveAttendanceRecord);
router.put('/:id/restore', protect, admin, restoreAttendanceRecord);
router
  .route('/:id')
  .get(protect, admin, getAttendanceById)
  .put(protect, admin, updateAttendance)
  .delete(protect, admin, deleteAttendance);

module.exports = router;