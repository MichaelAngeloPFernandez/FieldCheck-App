const mongoose = require('mongoose');

const chatMessageSchema = new mongoose.Schema(
  {
    conversation: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Conversation',
      required: true,
      index: true,
    },
    senderUser: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
      index: true,
    },
    body: {
      type: String,
      required: true,
      trim: true,
      maxlength: 4000,
    },
    readBy: {
      type: [
        {
          type: mongoose.Schema.Types.ObjectId,
          ref: 'User',
        },
      ],
      default: [],
      index: true,
    },
  },
  { timestamps: true },
);

chatMessageSchema.index({ conversation: 1, createdAt: -1 });

module.exports = mongoose.model('ChatMessage', chatMessageSchema);
