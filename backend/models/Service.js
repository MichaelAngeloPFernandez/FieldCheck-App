const mongoose = require('mongoose');

const serviceSchema = new mongoose.Schema(
  {
    companyId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Company',
      required: true,
    },
    name: {
      type: String,
      required: true,
      trim: true,
    },
    description: {
      type: String,
      default: '',
    },
    isActive: {
      type: Boolean,
      default: true,
    },
  },
  { timestamps: true }
);

// Unique index: name must be unique per company
serviceSchema.index({ companyId: 1, name: 1 }, { unique: true });

// Index for listing active services by company
serviceSchema.index({ companyId: 1, isActive: 1 });

// Validation: ensure name is unique per company
serviceSchema.pre('save', async function (next) {
  if (!this.isModified('name') && !this.isNew) {
    return next();
  }

  try {
    const existingService = await mongoose.model('Service').findOne({
      companyId: this.companyId,
      name: this.name,
      _id: { $ne: this._id }, // Exclude current document for updates
    });

    if (existingService) {
      const error = new Error(
        `Service with name "${this.name}" already exists for this company`
      );
      error.code = 11000;
      throw error;
    }

    next();
  } catch (error) {
    next(error);
  }
});

module.exports = mongoose.model('Service', serviceSchema);
