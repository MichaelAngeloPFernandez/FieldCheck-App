const express = require('express');
const router = express.Router();
const { protect, admin } = require('../middleware/authMiddleware');
const {
  sendUrgentNotification,
  sendTaskAssignmentSms,
  sendOverdueTaskSms,
  sendAttendanceSms,
  sendWorkloadWarningSms,
  sendEscalationSms,
  sendLocationWarningSms,
  sendBatchSms,
} = require('../controllers/notificationController');

// Admin endpoints
router.post('/urgent', protect, admin, sendUrgentNotification);
router.post('/task-assignment', protect, admin, sendTaskAssignmentSms);
router.post('/overdue-task', protect, admin, sendOverdueTaskSms);
router.post('/attendance', protect, sendAttendanceSms);
router.post('/workload-warning', protect, admin, sendWorkloadWarningSms);
router.post('/escalation', protect, admin, sendEscalationSms);
router.post('/location-warning', protect, sendLocationWarningSms);
router.post('/batch', protect, admin, sendBatchSms);

module.exports = router;
