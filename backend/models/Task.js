const mongoose = require('mongoose');

const taskSchema = new mongoose.Schema(
  {
    title: { type: String, required: true },

    description: { type: String, default: '' },
    dueDate: { type: Date, required: false },
    assignedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
    companyId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Company',
      default: null,
    },
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
      enum: ['general', 'inspection', 'maintenance', 'delivery', 'client_support', 'other'],
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
    assignedTo: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      default: null,
    },
    completedBy: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      default: null,
    },
    completedAt: {
      type: Date,
      default: null,
    },
    taskDuration: {
      type: Number,
      default: null,
    },
    notes: {
      type: String,
      default: '',
    },
    statusHistory: [
      {
        status: {
          type: String,
          required: true,
        },
        changedBy: {
          type: mongoose.Schema.Types.ObjectId,
          ref: 'User',
          required: true,
        },
        changedAt: {
          type: Date,
          default: Date.now,
        },
        reason: {
          type: String,
          default: '',
        },
      },
    ],
  },

  { timestamps: true }
);

// Indexes for efficient queries
taskSchema.index({ assignedTo: 1, status: 1 });
taskSchema.index({ companyId: 1, createdAt: 1 });

module.exports = mongoose.model('Task', taskSchema);