const mongoose = require('mongoose');

const checklistItemSchema = new mongoose.Schema(
  {
    label: {
      type: String,
      required: true,
    },
    isCompleted: {
      type: Boolean,
      default: false,
    },
    itemCompletedAt: {
      type: Date,
      default: null,
    },
  },
  { _id: false }
);

const taskTemplateSchema = new mongoose.Schema(
  {
    serviceId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Service',
      required: true,
    },
    companyId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Company',
      required: true,
    },
    title: {
      type: String,
      required: true,
      trim: true,
    },
    description: {
      type: String,
      default: '',
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
    checklist: [checklistItemSchema],
    isActive: {
      type: Boolean,
      default: true,
    },
  },
  { timestamps: true }
);

// Index for listing templates by service
taskTemplateSchema.index({ serviceId: 1 });

// Index for company-scoped queries
taskTemplateSchema.index({ companyId: 1, isActive: 1 });

module.exports = mongoose.model('TaskTemplate', taskTemplateSchema);
