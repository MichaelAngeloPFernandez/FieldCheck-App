const express = require('express');
const router = express.Router();
const {
  createTemplate,
  getTemplatesByService,
  getTemplateById,
  updateTemplate,
  deleteTemplate,
} = require('../controllers/templateController');

const { protect, admin, requireCompany } = require('../middleware/authMiddleware');

// All template endpoints require authentication, admin role, and company scoping
router.use(protect, admin, requireCompany);

// Get templates for a specific service
router.get('/service/:serviceId', getTemplatesByService);

// Create template for a service
router.post('/service/:serviceId', createTemplate);

// Get, update, delete specific template
router.get('/:id', getTemplateById);
router.put('/:id', updateTemplate);
router.delete('/:id', deleteTemplate);

module.exports = router;
