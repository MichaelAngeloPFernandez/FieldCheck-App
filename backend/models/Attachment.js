const mongoose = require('mongoose');

const attachmentSchema = new mongoose.Schema(
  {
    // Reference to parent resource
    resourceType: {
      type: String,
      enum: ['report', 'task', 'ticket'],
      required: true,
      index: true,
    },
    resourceId: {
      type: mongoose.Schema.Types.ObjectId,
      required: true,
      index: true,
    },

    // File metadata
    fileName: {
      type: String,
      required: true,
    },
    fileSize: {
      type: Number,
      required: true,
    },
    fileType: {
      type: String,
      required: true,
      example: 'image/jpeg',
    },

    // Storage reference
    url: {
      type: String,
      required: true,
      description: 'Full URL to access the file (via proxy or direct)',
    },
    provider: {
      type: String,
      enum: ['render', 'cloudinary', 's3', 'local'],
      default: 'render',
      description: 'Where file is actually stored',
    },

    // Data integrity
    checksum: {
      type: String,
      required: false,
      index: true,
      description: 'SHA256 hash for deduplication',
    },

    // Audit
    uploadedBy: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
    },
    uploadedAt: {
      type: Date,
      default: Date.now,
      immutable: true,
    },

    // Soft delete
    isDeleted: {
      type: Boolean,
      default: false,
      index: true,
    },
    deletedAt: Date,
    deletedBy: mongoose.Schema.Types.ObjectId,
  },
  { timestamps: true }
);

// Indexes for performance
attachmentSchema.index({ resourceId: 1, uploadedAt: -1 });
attachmentSchema.index({ uploadedBy: 1, uploadedAt: -1 });
attachmentSchema.index({ checksum: 1 }); // For deduplication

module.exports = mongoose.model('Attachment', attachmentSchema);
