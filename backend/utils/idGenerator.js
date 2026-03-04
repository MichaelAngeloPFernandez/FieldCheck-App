const User = require('../models/User');

/**
 * Generate a sequential employee or admin ID with gap filling.
 * Employee IDs: EN001, EN002, ...
 * Admin IDs: AD001, AD002, ...
 * 
 * @param {string} role - 'employee' or 'admin'
 * @returns {Promise<string>} - The generated ID
 */
async function generateSequentialId(role = 'employee') {
  const prefix = role === 'admin' ? 'AD' : 'EN';
  
  // Find all users with IDs matching the pattern (prefix + digits)
  const regex = new RegExp(`^${prefix}\\d+$`, 'i');
  const users = await User.find({
    employeeId: { $regex: regex },
    role: role
  }).select('employeeId').lean();

  // Extract numeric parts and find gaps
  const usedNumbers = new Set();
  let maxNumber = 0;

  for (const user of users) {
    const id = (user.employeeId || '').toUpperCase();
    const numStr = id.replace(prefix.toUpperCase(), '');
    const num = parseInt(numStr, 10);
    if (!isNaN(num) && num > 0) {
      usedNumbers.add(num);
      if (num > maxNumber) maxNumber = num;
    }
  }

  // Find the first gap, or use next number after max
  let nextNumber = 1;
  for (let i = 1; i <= maxNumber + 1; i++) {
    if (!usedNumbers.has(i)) {
      nextNumber = i;
      break;
    }
  }

  // Format with leading zeros (3 digits minimum)
  const paddedNumber = String(nextNumber).padStart(3, '0');
  return `${prefix}${paddedNumber}`;
}

/**
 * Reorder all employee/admin IDs sequentially, filling gaps.
 * This should be used carefully as it modifies existing IDs.
 * 
 * @param {string} role - 'employee' or 'admin'
 * @returns {Promise<Object>} - Mapping of old IDs to new IDs
 */
async function reorderAllIds(role = 'employee') {
  const prefix = role === 'admin' ? 'AD' : 'EN';
  const regex = new RegExp(`^${prefix}\\d+$`, 'i');
  
  // Find all users with matching ID pattern
  const users = await User.find({
    employeeId: { $regex: regex },
    role: role
  }).sort({ createdAt: 1 }); // Sort by creation date for consistent ordering

  const mapping = {};
  let counter = 1;

  for (const user of users) {
    const oldId = user.employeeId;
    const paddedNumber = String(counter).padStart(3, '0');
    const newId = `${prefix}${paddedNumber}`;
    
    if (oldId.toUpperCase() !== newId.toUpperCase()) {
      user.employeeId = newId;
      await user.save();
      mapping[oldId] = newId;
    }
    counter++;
  }

  return mapping;
}

module.exports = {
  generateSequentialId,
  reorderAllIds,
};
