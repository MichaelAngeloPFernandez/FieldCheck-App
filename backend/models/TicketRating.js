const mongoose = require('mongoose');

const ticketRatingSchema = new mongoose.Schema(
  {
    ticketId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'ClientTicket',
      required: true,
      index: true,
    },

    employeeId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      default: null,
      index: true,
    },

    reportId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Report',
      default: null,
    },

    clientEmail: {
      type: String,
      required: true,
      lowercase: true,
      trim: true,
      index: true,
    },

    stars: {
      type: Number,
      required: true,
      min: 1,
      max: 5,
    },

    comment: {
      type: String,
      trim: true,
      // Required only if stars < 3
    },

    submittedAt: {
      type: Date,
      default: Date.now,
      index: true,
    },
  },
  {
    timestamps: true,
    collection: 'ticketRatings',
  }
);

// Validation: comment required if stars < 3
ticketRatingSchema.pre('save', function (next) {
  if (this.stars < 3 && (!this.comment || this.comment.trim().length === 0)) {
    return next(new Error('Comment is required for ratings below 3 stars'));
  }
  next();
});

ticketRatingSchema.index(
  { ticketId: 1, employeeId: 1, clientEmail: 1 },
  { unique: true, partialFilterExpression: { employeeId: { $exists: true } } }
);

module.exports = mongoose.model('TicketRating', ticketRatingSchema);
