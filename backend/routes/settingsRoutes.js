const express = require('express');
const router = express.Router();
const { getSettings, getSetting, updateSetting, updateSettings, deleteSetting } = require('../controllers/settingsController');
const { protect, admin } = require('../middleware/authMiddleware');

router.route('/').get(protect, admin, getSettings).put(protect, admin, updateSettings);
router.route('/:key').get(protect, admin, getSetting).put(protect, admin, updateSetting).delete(protect, admin, deleteSetting);

module.exports = router;
