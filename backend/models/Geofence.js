const mongoose = require('mongoose');

const geofenceSchema = mongoose.Schema(
  {
    name: {
      type: String,
      required: true,
      unique: true,
    },
    address: {
      type: String,
      default: '',
    },
    latitude: {
      type: Number,
      required: true,
    },
    longitude: {
      type: Number,
      required: true,
    },
    radius: {
      type: Number,
      required: true,
    },
    shape: {
      type: String,
      enum: ['circle', 'polygon'],
      default: 'circle',
    },
    isActive: {
      type: Boolean,
      default: true,
    },
    createdBy: {
      type: String,
    },
    assignedEmployees: [
      {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'User',
      },
    ],
    // New fields for TEAM/SOLO and A–Z labeling
    type: {
      type: String,
      enum: ['TEAM', 'SOLO'],
      default: 'TEAM',
    },
    labelLetter: {
      type: String,
      // Optional to maintain backward compatibility; UI will require on new geofences
    },
  },
  { timestamps: true }
);

// Enforce unique TEAM/SOLO letter per active geofence
geofenceSchema.index(
  { type: 1, labelLetter: 1 },
  { unique: true, partialFilterExpression: { isActive: true, labelLetter: { $exists: true } } }
);

module.exports = mongoose.model('Geofence', geofenceSchema);