const mongoose = require('mongoose');

const ticketSchema = new mongoose.Schema(
  {
    companyId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Company',
      required: true,
    },
    serviceId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Service',
      default: null,
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
    status: {
      type: String,
      enum: ['open', 'in_progress', 'completed', 'closed'],
      default: 'open',
    },
  },
  { timestamps: true }
);

// Index for listing tickets by company and status
ticketSchema.index({ companyId: 1, status: 1 });

// Index for service-based queries
ticketSchema.index({ serviceId: 1 });

module.exports = mongoose.model('Ticket', ticketSchema);
