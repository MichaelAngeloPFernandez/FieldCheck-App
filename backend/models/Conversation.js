const mongoose = require('mongoose');

const conversationSchema = new mongoose.Schema(
  {
    participants: {
      type: [
        {
          type: mongoose.Schema.Types.ObjectId,
          ref: 'User',
          required: true,
        },
      ],
      validate: {
        validator: function (arr) {
          return Array.isArray(arr) && arr.length === 2;
        },
        message: 'Conversation must have exactly 2 participants',
      },
      index: true,
    },
    lastMessageAt: {
      type: Date,
      default: null,
      index: true,
    },
    lastMessagePreview: {
      type: String,
      default: '',
    },
  },
  { timestamps: true },
);

conversationSchema.index({ participants: 1, updatedAt: -1 });

module.exports = mongoose.model('Conversation', conversationSchema);
