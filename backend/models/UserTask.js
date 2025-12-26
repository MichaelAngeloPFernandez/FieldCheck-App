const mongoose = require('mongoose');

const userTaskSchema = new mongoose.Schema(
  {
    userId: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
    taskId: { type: mongoose.Schema.Types.ObjectId, ref: 'Task', required: true },
    status: {
      type: String,
      enum: ['pending', 'in_progress', 'completed'],
      default: 'pending',
    },
    assignedAt: { type: Date, default: Date.now },
    completedAt: { type: Date, required: false },
  },
  { timestamps: true }
);

module.exports = mongoose.model('UserTask', userTaskSchema);