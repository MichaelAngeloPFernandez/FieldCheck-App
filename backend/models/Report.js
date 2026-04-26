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
    // NEW: Reference to Attachment documents (instead of raw URLs)
    attachmentIds: [{
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Attachment'
    }],
    // DEPRECATED: Keep for backward compatibility, but use attachmentIds instead
    attachments: [{ type: String }],
    status: {
      type: String,
      enum: ['submitted', 'reviewed'],
      default: 'submitted',
    },
    grade: {
      type: String,
      enum: ['poor', 'good', 'excellent'],
    },
    gradeComment: {
      type: String,
      default: '',
    },
    submittedAt: { type: Date, default: Date.now },
    resubmitUntil: { type: Date },
    // Soft-archive flag for separating current vs archived reports
    isArchived: { type: Boolean, default: false },
  },
  { timestamps: true }
);

module.exports = mongoose.model('Report', reportSchema);