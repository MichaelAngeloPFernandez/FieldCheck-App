const express = require('express');
const router = express.Router();
const { protect } = require('../middleware/authMiddleware');
const auditService = require('../services/auditService');

router.get('/:resourceType/:resourceId', protect, async (req, res) => {
  try {
    const { resourceType, resourceId } = req.params;
    const limit = Math.min(Math.max(Number(req.query.limit) || 50, 1), 200);
    const skip = Math.max(Number(req.query.skip) || 0, 0);
    const trail = await auditService.getTrail(resourceType, resourceId, { limit, skip });
    res.json(trail);
  } catch (err) {
    console.error('GET /api/audit error:', err);
    res.status(500).json({ message: 'Failed to fetch audit trail' });
  }
});

module.exports = router;
