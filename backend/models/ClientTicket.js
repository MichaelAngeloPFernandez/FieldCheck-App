const mongoose = require('mongoose');

const clientTicketSchema = new mongoose.Schema(
  {
    // Unique ticket identifier: RNG-YYYYMMDD-XXXX
    ticketNumber: {
      type: String,
      required: true,
      unique: true,
      index: true,
      uppercase: true,
    },

    // Client information (no account registration required)
    clientEmail: {
      type: String,
      required: true,
      lowercase: true,
      trim: true,
      index: true,
    },
    clientName: {
      type: String,
      required: true,
      trim: true,
    },

    // Service request details
    serviceType: {
      type: String,
      enum: [
        'facility_inspection',
        'maintenance',
        'equipment_check',
        'cleaning',
        'security_audit',
        'aircon_cleaning',
        'other',
      ],
      required: true,
      index: true,
    },

    // For "other" service type: client-provided details
    otherServiceDetails: {
      type: String,
      trim: true,
      default: null,
    },

    description: {
      type: String,
      required: true,
      trim: true,
    },

    // File attachments uploaded by client
    attachments: [
      {
        fileName: String,
        fileUrl: String, // Cloudinary or GridFS URL
        fileType: String, // mime type
        uploadedAt: { type: Date, default: Date.now },
      },
    ],

    // Ticket lifecycle
    status: {
      type: String,
      enum: ['open', 'in_progress', 'pending_review', 'completed', 'closed', 'expired'],
      default: 'open',
      index: true,
    },

    // Assignment to employee
    assignedEmployeeId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      default: null,
      index: true,
    },

    // Link to auto-created employee task
    linkedTaskId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Task',
      default: null,
    },

    // Admin assignment tracking
    assignedAt: Date,
    assignedBy: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
    },

    // Completion tracking
    completedAt: Date,
    completedBy: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
    },

    // Comments/notes thread
    comments: [
      {
        authorType: {
          type: String,
          enum: ['admin', 'employee', 'client'],
          required: true,
        },
        authorId: {
          type: mongoose.Schema.Types.ObjectId,
          ref: 'User',
          default: null,
        },
        authorEmail: String, // For client comments, we store email instead of ID
        text: String,
        createdAt: { type: Date, default: Date.now },
      },
    ],

    // Client rating (submitted after ticket completion)
    rating: {
      stars: {
        type: Number,
        min: 1,
        max: 5,
      },
      comment: String,
      submittedAt: Date,
      submittedBy: String, // client email
    },

    // Internal admin notes
    adminNotes: String,

    // Archival & expiration tracking
    archived: {
      type: Boolean,
      default: false,
      index: true,
    },
    archivedAt: Date,
    archivedBy: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
    },

    // Admin read status (when admin first viewed ticket)
    adminReadAt: Date,

    // Ticket expiration (auto-expire after 3 days if still open)
    expiresAt: Date,

    // Email token for public ticket tracking (hashed for security)
    trackingToken: {
      type: String,
      default: null,
      select: false, // Don't include in queries by default
    },

    // Timestamps
    createdAt: { type: Date, default: Date.now, index: true },
    updatedAt: { type: Date, default: Date.now },
  },
  {
    timestamps: true,
    collection: 'clientTickets',
  }
);

// Indexes for advanced filtering
clientTicketSchema.index({ status: 1, createdAt: -1 });
clientTicketSchema.index({ serviceType: 1, status: 1 });
clientTicketSchema.index({ clientEmail: 1, createdAt: -1 });
clientTicketSchema.index({ assignedEmployeeId: 1, status: 1 });

// Update 'updatedAt' on any save
clientTicketSchema.pre('save', function (next) {
  this.updatedAt = new Date();
  next();
});

module.exports = mongoose.model('ClientTicket', clientTicketSchema);
