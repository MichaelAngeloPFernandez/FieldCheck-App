const mongoose = require('mongoose');

const userTaskSchema = new mongoose.Schema(
  {
    userId: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
    taskId: { type: mongoose.Schema.Types.ObjectId, ref: 'Task', required: true },
    isArchived: { type: Boolean, default: false },
    lastViewedAt: { type: Date, required: false },
    status: {
      type: String,
      enum: ['pending', 'pending_acceptance', 'accepted', 'in_progress', 'completed', 'reviewed'],
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
    grade: {
      score: { type: Number, min: 0, max: 100, required: false },
      feedback: { type: String, required: false },
      gradedAt: { type: Date, required: false },
      gradedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: false },
    },
  },
  { timestamps: true }
);

module.exports = mongoose.model('UserTask', userTaskSchema);