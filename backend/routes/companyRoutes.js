/**
 * Company Routes — manage companies for multi-tenancy.
 */
const express = require('express');
const router = express.Router();
const { protect, requireRole } = require('../middleware/authMiddleware');
const Company = require('../models/Company');
const User = require('../models/User');

// GET /api/companies — list all companies (admin only)
router.get('/', protect, requireRole('admin'), async (req, res) => {
  try {
    const companies = await Company.find({ isActive: true }).sort({ name: 1 }).lean();
    res.json(companies);
  } catch (err) {
    res.status(500).json({ message: 'Failed to fetch companies' });
  }
});

// POST /api/companies — create a company (admin only)
router.post('/', protect, requireRole('admin'), async (req, res) => {
  try {
    const { name, code, settings } = req.body;
    if (!name || !code) {
      return res.status(400).json({ message: 'name and code are required' });
    }
    const existing = await Company.findOne({ code: code.toUpperCase() });
    if (existing) {
      return res.status(409).json({ message: 'Company code already exists' });
    }
    const company = await Company.create({
      name,
      code: code.toUpperCase(),
      settings: settings || {},
    });
    // Auto-assign the creating admin to this company if they don't have one
    if (!req.user.company) {
      await User.findByIdAndUpdate(req.user._id, { company: company._id });
    }
    res.status(201).json(company);
  } catch (err) {
    res.status(500).json({ message: 'Failed to create company' });
  }
});

// PATCH /api/companies/:id — update company
router.patch('/:id', protect, requireRole('admin'), async (req, res) => {
  try {
    const company = await Company.findById(req.params.id);
    if (!company) return res.status(404).json({ message: 'Company not found' });
    if (req.body.name) company.name = req.body.name;
    if (req.body.settings) company.settings = { ...company.settings, ...req.body.settings };
    await company.save();
    res.json(company);
  } catch (err) {
    res.status(500).json({ message: 'Failed to update company' });
  }
});

// POST /api/companies/:id/assign-user — assign a user to a company
router.post('/:id/assign-user', protect, requireRole('admin'), async (req, res) => {
  try {
    const { userId } = req.body;
    if (!userId) return res.status(400).json({ message: 'userId is required' });
    const company = await Company.findById(req.params.id);
    if (!company) return res.status(404).json({ message: 'Company not found' });
    await User.findByIdAndUpdate(userId, { company: company._id });
    res.json({ message: 'User assigned to company' });
  } catch (err) {
    res.status(500).json({ message: 'Failed to assign user' });
  }
});

module.exports = router;
