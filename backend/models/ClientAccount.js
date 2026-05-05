const mongoose = require('mongoose');
const bcrypt = require('bcrypt');

const clientAccountSchema = new mongoose.Schema(
  {
    email: {
      type: String,
      required: true,
      unique: true,
      lowercase: true,
      trim: true,
      index: true,
    },

    clientName: {
      type: String,
      required: true,
      trim: true,
    },

    // Optional: hashed password for client portal login
    password: {
      type: String,
      default: null,
    },

    // Tokens for email verification and tracking
    emailVerified: {
      type: Boolean,
      default: false,
    },

    verificationToken: String,
    verificationTokenExpiry: Date,

    // Track tickets submitted by this client
    submittedTicketIds: [
      {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'ClientTicket',
      },
    ],

    // Timestamps
    createdAt: { type: Date, default: Date.now },
    updatedAt: { type: Date, default: Date.now },
  },
  {
    timestamps: true,
    collection: 'clientAccounts',
  }
);

// Hash password before saving
clientAccountSchema.pre('save', async function (next) {
  if (!this.isModified('password')) return next();
  
  if (!this.password) return next();
  
  try {
    const salt = await bcrypt.genSalt(10);
    this.password = await bcrypt.hash(this.password, salt);
    next();
  } catch (error) {
    next(error);
  }
});

// Method to compare password for login
clientAccountSchema.methods.comparePassword = async function (inputPassword) {
  return bcrypt.compare(inputPassword, this.password);
};

// Update 'updatedAt' on any save
clientAccountSchema.pre('save', function (next) {
  this.updatedAt = new Date();
  next();
});

module.exports = mongoose.model('ClientAccount', clientAccountSchema);
