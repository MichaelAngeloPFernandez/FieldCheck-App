const mongoose = require('mongoose');

const taskSchema = new mongoose.Schema(
  {
    title: { type: String, required: true },

    description: { type: String, default: '' },
    dueDate: { type: Date, required: false },
    assignedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
    status: {
      type: String,
      enum: [
        'pending',
        'in_progress',
        'completed',
        'created',
        'assigned',
        'accepted',
        'blocked',
        'reviewed',
        'closed',
      ],
      // Keep legacy default "pending" to avoid breaking existing flows,
      // while still allowing richer lifecycle values when explicitly set.
      default: 'pending',
    },
    type: {
      type: String,
      enum: ['general', 'inspection', 'maintenance', 'delivery', 'other'],
      default: 'general',
    },
    difficulty: {
      type: String,
      enum: ['easy', 'medium', 'hard'],
      default: 'medium',
    },
    // Auto-populated from assigned geofence
    geofenceId: { type: mongoose.Schema.Types.ObjectId, ref: 'Geofence', required: false },
    // Soft-archive flag for separating current vs archived tasks
    isArchived: { type: Boolean, default: false },
    // One-time flag used to prevent repeat overdue notifications
    overdueNotified: { type: Boolean, default: false },
    progressPercent: {
      type: Number,
      min: 0,
      max: 100,
      default: 0,
    },
    checklist: [
      {
        label: { type: String, required: true },
        isCompleted: { type: Boolean, default: false },
        completedAt: { type: Date },
      },
    ],
    attachments: {
      images: [{ type: String }],
      documents: [{ type: String }],
      others: [{ type: String }],
    },
    blockReason: { type: String },
  },

  { timestamps: true }
);

module.exports = mongoose.model('Task', taskSchema);