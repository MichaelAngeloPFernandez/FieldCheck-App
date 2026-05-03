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
    isArchived: {
      type: Boolean,
      default: false,
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

    // Idempotency keys for offline sync (client-generated UUIDs)
    syncCheckInEventId: {
      type: String,
      default: null,
      index: true,
    },
    syncCheckOutEventId: {
      type: String,
      default: null,
      index: true,
    },
  },
  { timestamps: true }
);

attendanceSchema.index(
  { employee: 1, syncCheckInEventId: 1 },
  { unique: true, sparse: true },
);

attendanceSchema.index(
  { employee: 1, syncCheckOutEventId: 1 },
  { unique: true, sparse: true },
);

module.exports = mongoose.model('Attendance', attendanceSchema);