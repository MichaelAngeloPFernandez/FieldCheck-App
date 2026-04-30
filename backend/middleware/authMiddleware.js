const jwt = require('jsonwebtoken');
const asyncHandler = require('express-async-handler');
const User = require('../models/User');

const protect = asyncHandler(async (req, res, next) => {
  let token;

  if (req.headers.authorization && req.headers.authorization.startsWith('Bearer')) {
    try {
      token = req.headers.authorization.split(' ')[1];

      const decoded = jwt.verify(token, process.env.JWT_SECRET);

      req.user = await User.findById(decoded.id).select('-password');

      next();
    } catch (error) {
      console.error(error);
      res.status(401);
      throw new Error('Not authorized, token failed');
    }
  }

  if (!token) {
    res.status(401);
    throw new Error('Not authorized, no token');
  }
});

const admin = (req, res, next) => {
  if (req.user && req.user.role === 'admin') {
    next();
  } else {
    res.status(401);
    throw new Error('Not authorized as an admin');
  }
};

/**
 * requireRole(...roles) — middleware factory for RBAC.
 * Usage: router.post('/templates', protect, requireRole('admin'), handler);
 *        router.get('/tickets', protect, requireRole('admin', 'employee'), handler);
 */
const requireRole = (...roles) => {
  return (req, res, next) => {
    if (!req.user) {
      res.status(401);
      throw new Error('Not authorized');
    }
    if (!roles.includes(req.user.role)) {
      res.status(403);
      throw new Error(`Requires one of: ${roles.join(', ')}`);
    }
    next();
  };
};

/**
 * requireCompany — middleware that ensures req.user has a company set.
 * Injects req.companyId for convenience.
 */
const requireCompany = (req, res, next) => {
  if (!req.user) {
    res.status(401);
    throw new Error('Not authorized');
  }
  const companyId = req.user.company
    ? String(req.user.company._id || req.user.company)
    : null;
  if (!companyId) {
    res.status(403);
    throw new Error('User is not assigned to a company');
  }
  req.companyId = companyId;
  next();
};

module.exports = { protect, admin, requireRole, requireCompany };