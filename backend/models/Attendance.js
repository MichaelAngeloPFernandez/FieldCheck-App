const mongoose = require('mongoose');

const attendanceSchema = mongoose.Schema(
  {
    employee: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
    },
    geofence: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Geofence',
      required: true,
    },
    checkIn: {
      type: Date,
      required: true,
    },
    checkOut: {
      type: Date,
    },
    status: {
      type: String,
      enum: ['in', 'out', 'pending_sync'],
      default: 'in',
    },
    location: {
      lat: { type: Number, required: true },
      lng: { type: Number, required: true },
    },
    // Auto-checkout & void tracking
    isVoid: {
      type: Boolean,
      default: false,
    },
    voidReason: {
      type: String,
    },
    autoCheckout: {
      type: Boolean,
      default: false,
    },
    checkoutWarningSent: {
      type: Boolean,
      default: false,
    },
  },
  { timestamps: true }
);

module.exports = mongoose.model('Attendance', attendanceSchema);