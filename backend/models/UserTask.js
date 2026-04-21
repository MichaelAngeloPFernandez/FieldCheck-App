const mongoose = require('mongoose');

const userTaskSchema = new mongoose.Schema(
  {
    userId: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
    taskId: { type: mongoose.Schema.Types.ObjectId, ref: 'Task', required: true },
    isArchived: { type: Boolean, default: false },
    lastViewedAt: { type: Date, required: false },
    status: {
      type: String,
      enum: [
        'pending',
        'pending_acceptance',
        'accepted',
        'in_progress',
        'blocked',
        'completed',
        'reviewed',
        'closed',
      ],
      default: 'pending_acceptance',
    },
    progressPercent: {
      type: Number,
      min: 0,
      max: 100,
      default: 0,
    },
    assignedAt: { type: Date, default: Date.now },
    completedAt: { type: Date, required: false },
    blockStatus: {
      type: String,
      enum: ['blocked', 'unblocked', 'closed'],
      required: false,
    },
    blockReasonCategory: { type: String, required: false },
    blockReasonText: { type: String, required: false },
    blockEvidencePhotos: [{ type: String }],
    blockedAt: { type: Date, required: false },
    adminReviewNote: { type: String, required: false },
    adminAction: {
      type: String,
      enum: ['unblocked', 'closed'],
      required: false,
    },
    adminActionAt: { type: Date, required: false },
    adminActionBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: false },
    grade: {
      score: { type: Number, min: 0, max: 100, required: false },
      feedback: { type: String, required: false },
      gradedAt: { type: Date, required: false },
      gradedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: false },
    },
    comments: [
      {
        sender: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
        senderName: String,
        body: String,
        createdAt: { type: Date, default: Date.now },
      },
    ],
  },
  { timestamps: true }
);

module.exports = mongoose.model('UserTask', userTaskSchema);