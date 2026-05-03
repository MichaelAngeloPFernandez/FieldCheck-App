const mongoose = require('mongoose');

const companySchema = new mongoose.Schema(
  {
    name: { type: String, required: true, trim: true },
    code: {
      type: String,
      required: true,
      unique: true,
      uppercase: true,
      trim: true,
      maxlength: 10,
    },
    settings: {
      timezone: { type: String, default: 'Asia/Manila' },
      slaDefaults: {
        urgentSeconds: { type: Number, default: 3600 },      // 1 hour
        normalSeconds: { type: Number, default: 28800 },      // 8 hours
        lowSeconds: { type: Number, default: 86400 },         // 24 hours
      },
      geofenceEnforcement: { type: Boolean, default: true },
    },
    isActive: { type: Boolean, default: true },
  },
  { timestamps: true }
);

module.exports = mongoose.model('Company', companySchema);
