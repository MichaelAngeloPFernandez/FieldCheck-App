const mongoose = require('mongoose');

const reportSchema = new mongoose.Schema(
  {
    type: {
      type: String,
      enum: ['task', 'attendance'],
      required: true,
    },
    task: { type: mongoose.Schema.Types.ObjectId, ref: 'Task' },
    attendance: { type: mongoose.Schema.Types.ObjectId, ref: 'Attendance' },
    employee: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
    geofence: { type: mongoose.Schema.Types.ObjectId, ref: 'Geofence' },
    content: { type: String, default: '' },
    attachments: [{ type: String }],
    status: {
      type: String,
      enum: ['submitted', 'reviewed'],
      default: 'submitted',
    },
    submittedAt: { type: Date, default: Date.now },
  },
  { timestamps: true }
);

module.exports = mongoose.model('Report', reportSchema);