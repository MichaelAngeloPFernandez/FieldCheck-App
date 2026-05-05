const crypto = require('crypto');

/**
 * Generates a secure, URL-safe email token for public ticket tracking
 * Token is hashed for storage in the database for security
 * Format: 32-byte random hex string
 * 
 * @returns {Object} { token, tokenHash }
 * @example
 * const { token, tokenHash } = generateEmailToken();
 * // token: 'a1b2c3d4e5f6...' (send to client in email)
 * // tokenHash: 'hashed_value' (store in database)
 */
function generateEmailToken() {
  // Generate 32 bytes of random data (256-bit security)
  const token = crypto.randomBytes(32).toString('hex');
  
  // Hash the token for secure storage
  const tokenHash = crypto
    .createHash('sha256')
    .update(token)
    .digest('hex');
  
  return { token, tokenHash };
}

/**
 * Verifies an email token against a stored hash
 * 
 * @param {string} providedToken - Token provided by client (from URL)
 * @param {string} storedHash - Hashed token stored in database
 * @returns {boolean} Whether the token is valid
 */
function verifyEmailToken(providedToken, storedHash) {
  if (!providedToken || !storedHash) {
    return false;
  }
  
  try {
    const providedHash = crypto
      .createHash('sha256')
      .update(providedToken)
      .digest('hex');
    
    // Use timing-safe comparison to prevent timing attacks
    return crypto.timingSafeEqual(
      Buffer.from(providedHash),
      Buffer.from(storedHash)
    );
  } catch (error) {
    return false;
  }
}

module.exports = {
  generateEmailToken,
  verifyEmailToken,
};
