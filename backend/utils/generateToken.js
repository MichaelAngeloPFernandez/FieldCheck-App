const jwt = require('jsonwebtoken');

const generateToken = (id) => {
  const secret = (process.env.JWT_SECRET || '').trim();
  if (!secret) {
    throw new Error('JWT_SECRET is not set');
  }
  return jwt.sign({ id }, secret, {
    expiresIn: process.env.JWT_EXPIRES_IN || '1h',
  });
};

const generateRefreshToken = (id, tokenVersion) => {
  const refreshSecret = (process.env.JWT_REFRESH_SECRET || '').trim();
  const secret = (process.env.JWT_SECRET || '').trim();
  const chosen = refreshSecret || secret;
  if (!chosen) {
    throw new Error('JWT_REFRESH_SECRET/JWT_SECRET is not set');
  }
  return jwt.sign({ id, tv: tokenVersion }, chosen, {
    expiresIn: process.env.JWT_REFRESH_EXPIRES_IN || '7d',
  });
};

const verifyRefreshToken = (token) => {
  const refreshSecret = (process.env.JWT_REFRESH_SECRET || '').trim();
  const secret = (process.env.JWT_SECRET || '').trim();
  const chosen = refreshSecret || secret;
  if (!chosen) {
    throw new Error('JWT_REFRESH_SECRET/JWT_SECRET is not set');
  }
  return jwt.verify(token, chosen);
};

module.exports = { generateToken, generateRefreshToken, verifyRefreshToken };