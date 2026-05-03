const User = require('../models/User');
const mongoose = require('mongoose');

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

  const Counter =
    mongoose.models.IdCounter ||
    mongoose.model(
      'IdCounter',
      new mongoose.Schema(
        {
          key: { type: String, required: true, unique: true },
          seq: { type: Number, required: true, default: 0 },
        },
        { timestamps: true },
      ),
    );

  const key = `employeeId:${prefix}`;

  // Concurrency-safe allocation:
  // - Atomically increments a counter
  // - Then checks for collisions (e.g., when enabling this on an existing DB)
  // - Loops until an unused code is found
  for (let attempt = 0; attempt < 2500; attempt++) {
    const counterDoc = await Counter.findOneAndUpdate(
      { key },
      { $inc: { seq: 1 } },
      { upsert: true, new: true, setDefaultsOnInsert: true },
    ).lean();

    const nextNumber = counterDoc && typeof counterDoc.seq === 'number' ? counterDoc.seq : 1;
    const paddedNumber = String(nextNumber).padStart(3, '0');
    const candidate = `${prefix}${paddedNumber}`;

    const exists = await User.exists({ role, employeeId: { $regex: `^${candidate}$`, $options: 'i' } });
    if (!exists) {
      return candidate;
    }
  }

  throw new Error('Unable to allocate a unique employeeId');
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
