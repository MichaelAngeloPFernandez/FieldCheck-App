const mongoose = require('mongoose');

const appNotificationSchema = new mongoose.Schema(
  {
    recipientUser: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
      index: true,
    },
    scope: {
      type: String,
      required: true,
      enum: ['tasks', 'adminFeed'],
      index: true,
    },
    type: {
      type: String,
      required: true,
      default: 'info',
    },
    action: {
      type: String,
      required: true,
      default: 'info',
    },
    title: {
      type: String,
      required: true,
      default: 'Notification',
    },
    message: {
      type: String,
      required: true,
      default: '',
    },
    payload: {
      type: mongoose.Schema.Types.Mixed,
      default: {},
    },
    readAt: {
      type: Date,
      default: null,
      index: true,
    },
  },
  { timestamps: true }
);

appNotificationSchema.index({ recipientUser: 1, scope: 1, readAt: 1, createdAt: -1 });

module.exports = mongoose.model('AppNotification', appNotificationSchema);
