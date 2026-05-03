const mongoose = require('mongoose');

const geofenceSchema = mongoose.Schema(
  {
    name: {
      type: String,
      required: true,
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
    // A–Z labeling for geofences
    labelLetter: {
      type: String,
      // Optional to maintain backward compatibility; UI will require on new geofences
    },
  },
  { timestamps: true }
);

// Enforce unique label letter per active geofence
geofenceSchema.index(
  { labelLetter: 1 },
  { unique: true, partialFilterExpression: { isActive: true, labelLetter: { $exists: true } } }
);

module.exports = mongoose.model('Geofence', geofenceSchema);