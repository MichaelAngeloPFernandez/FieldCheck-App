const express = require('express');
const router = express.Router();
const { checkIn, checkOut, logAttendance, getAttendanceRecords, getAttendanceById, updateAttendance, deleteAttendance, getAttendanceStatus, getAttendanceHistory } = require('../controllers/attendanceController');
const { protect } = require('../middleware/authMiddleware');

router.post('/checkin', protect, checkIn);
router.post('/checkout', protect, checkOut);
router.get('/status', protect, getAttendanceStatus);
router.get('/history', protect, getAttendanceHistory);
router.route('/').post(protect, logAttendance).get(protect, getAttendanceRecords);
router.route('/:id').get(protect, getAttendanceById).put(protect, updateAttendance).delete(protect, deleteAttendance);

module.exports = router;