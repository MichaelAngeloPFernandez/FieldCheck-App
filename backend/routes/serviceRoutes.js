const express = require('express');
const router = express.Router();
const {
  createService,
  getServices,
  getServiceById,
  updateService,
  deleteService,
} = require('../controllers/serviceController');

const { protect, admin, requireCompany } = require('../middleware/authMiddleware');

// All service endpoints require authentication, admin role, and company scoping
router.use(protect, admin, requireCompany);

// List and create services
router.get('/', getServices);
router.post('/', createService);

// Get, update, delete specific service
router.get('/:id', getServiceById);
router.put('/:id', updateService);
router.delete('/:id', deleteService);

module.exports = router;
