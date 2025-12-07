const mongoose = require('mongoose');

const employeeLocationSchema = new mongoose.Schema(
  {
    user: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
    latitude: { type: Number, required: true },
    longitude: { type: Number, required: true },
    accuracy: { type: Number },
    timestamp: { type: Date, default: Date.now },
  },
  { timestamps: true }
);

employeeLocationSchema.index({ user: 1, timestamp: -1 });

module.exports = mongoose.model('EmployeeLocation', employeeLocationSchema);
