const mongoose = require('mongoose');

/**
 * Counter — atomic per-company sequence for generating human-readable
 * ticket numbers like "AC-0001".
 *
 * Usage:
 *   const Counter = require('./Counter');
 *   const next = await Counter.getNextSequence(companyId);
 *   // next === 1, 2, 3, ...
 */
const counterSchema = new mongoose.Schema({
  // The company this counter belongs to.
  company: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Company',
    required: true,
    unique: true,
  },
  seq: { type: Number, default: 0 },
});

/**
 * Atomically increment and return the next sequence number for the company.
 * Uses findOneAndUpdate with $inc for concurrency safety.
 */
counterSchema.statics.getNextSequence = async function (companyId) {
  const doc = await this.findOneAndUpdate(
    { company: companyId },
    { $inc: { seq: 1 } },
    { upsert: true, returnDocument: 'after', new: true }
  );
  return doc.seq;
};
module.exports = mongoose.model('Counter', counterSchema);
