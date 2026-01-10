const mongoose = require('mongoose');
const bcrypt = require('bcryptjs');

const userSchema = mongoose.Schema(
  {
    name: { type: String, required: true },

    username: {
      type: String,
      unique: true,
      sparse: true, // allow null usernames without violating uniqueness
      lowercase: true,
      trim: true,
    },
    employeeId: {
      type: String,
      trim: true,
      default: '',
    },
    email: {
      type: String,
      required: false,
      unique: true,
      sparse: true,
      lowercase: true,
      trim: true,
    },
    phone: {
      type: String,
      required: false,
      trim: true,
    },

    avatarUrl: {
      type: String,
      default: '',
    },
    lastLatitude: {
      type: Number,
      default: null,
    },
    lastLongitude: {
      type: Number,
      default: null,
    },
    lastLocationUpdate: {
      type: Date,
      default: null,
    },
    isOnline: {
      type: Boolean,
      default: false,
    },
    activeTaskCount: {
      type: Number,
      default: 0,
    },
    workloadWeight: {
      type: Number,
      default: 0,
    },
    password: {
      type: String,
      required: true,
    },
    role: { type: String, enum: ['employee', 'admin'], default: 'employee' },
    isVerified: { type: Boolean, default: false },
    verificationToken: String,
    verificationTokenExpires: Date,
    resetPasswordToken: String,
    resetPasswordExpires: Date,
    isActive: { type: Boolean, default: true },
    tokenVersion: { type: Number, default: 0 },
    provider: { type: String, enum: ['local', 'google'], default: 'local' },
    googleId: { type: String },
  },
  { timestamps: true }
);

userSchema.pre('save', async function (next) {
  if (!this.isModified('password')) return next();
  const salt = await bcrypt.genSalt(10);
  this.password = await bcrypt.hash(this.password, salt);
  next();
});

userSchema.methods.matchPassword = async function (enteredPassword) {
  return await bcrypt.compare(enteredPassword, this.password);
};

module.exports = mongoose.model('User', userSchema);