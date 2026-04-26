const mongoose = require('mongoose');

/**
 * Counter
 * 
 * Atomic counter for generating sequential ticket numbers.
 * Uses MongoDB's findByIdAndUpdate to ensure thread-safe increments.
 * 
 * Example: { _id: 'ac', seq: 42 } → next ticket number is AC-0042
 */
const counterSchema = new mongoose.Schema({
  _id: {
    type: String,
    required: true,
    description: 'Counter ID (e.g., "ac" for Aircon)',
  },
  seq: {
    type: Number,
    default: 0,
    description: 'Current sequence number',
  },
  prefix: {
    type: String,
    required: true,
    description: 'Human-readable prefix (e.g., "AC")',
  },
  digits: {
    type: Number,
    default: 4,
    description: 'Number of digits to pad with zeros',
  },
});

module.exports = mongoose.model('Counter', counterSchema);
