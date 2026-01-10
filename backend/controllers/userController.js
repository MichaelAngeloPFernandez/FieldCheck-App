const asyncHandler = require('express-async-handler');
const crypto = require('crypto');
const User = require('../models/User');
const sendEmail = require('../utils/emailService');
const { generateToken, generateRefreshToken, verifyRefreshToken } = require('../utils/generateToken');
const { v4: uuidv4 } = require('uuid');

function escapeRegExp(str) {
  return String(str).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

// @desc    Auth user & get token
// @route   POST /api/users/login
// @access  Public
const authUser = asyncHandler(async (req, res) => {
  const { email, username, identifier, password } = req.body;

  let user;
  const value = (identifier || email || username || '').toString().trim().toLowerCase();
  if (!value) {
    res.status(400);
    throw new Error('Email or username is required');
  }
  if (value.includes('@')) {
    user = await User.findOne({ email: value });
  } else {
    user = await User.findOne({ username: value });
    // fallback: allow login by name if username not set
    if (!user) user = await User.findOne({ name: value });
  }

  if (!user) {
    res.status(401);
    throw new Error('Invalid email/username or password');
  }

  const passwordMatch = await user.matchPassword(password);
  if (!passwordMatch) {
    res.status(401);
    throw new Error('Invalid email/username or password');
  }

  if (!user.isVerified) {
    res.status(403);
    throw new Error('Account not verified. Please check your email.');
  }

  if (user.isActive === false) {
    res.status(403);
    throw new Error('Account is deactivated. Contact admin.');
  }

  res.json({
    _id: user._id,
    name: user.name,
    username: user.username,
    email: user.email,
    phone: user.phone,
    employeeId: user.employeeId,
    avatarUrl: user.avatarUrl,
    role: user.role,
    token: generateToken(user._id),
    refreshToken: generateRefreshToken(user._id, user.tokenVersion || 0),
  });
});

// @desc    Register a new user
// @route   POST /api/users
// @access  Public
const registerUser = asyncHandler(async (req, res) => {
  const { name, username, email, password, role, phone, employeeId } = req.body;

  const io = require('../server').io;

  const emailStr = (email || '').toString().trim().toLowerCase();
  const usernameStr = (username || '').toString().trim().toLowerCase();
  const roleStr = (role || 'employee').toString().trim().toLowerCase();
  const employeeIdStr = (employeeId || '').toString().trim();

  const userExists = await User.findOne({ email: emailStr });
  if (userExists) {
    res.status(400);
    throw new Error('User with this email already exists');
  }

  if (usernameStr) {
    const usernameTaken = await User.findOne({ username: usernameStr });
    if (usernameTaken) {
      res.status(400);
      throw new Error('Username is already taken');
    }
  }

  if (roleStr !== 'admin') {
    if (!employeeIdStr) {
      res.status(400);
      throw new Error('employeeId is required for employees');
    }
    const employeeIdTaken = await User.findOne({
      employeeId: { $regex: `^${escapeRegExp(employeeIdStr)}$`, $options: 'i' },
    });
    if (employeeIdTaken) {
      res.status(400);
      throw new Error('Employee ID is already taken');
    }
  }

  const verificationToken = uuidv4();

  const user = await User.create({
    name,
    username: usernameStr || emailStr.split('@')[0],
    email: emailStr,
    password,
    role: roleStr,
    phone: phone || undefined,
    employeeId: roleStr !== 'admin' ? employeeIdStr : '',
    verificationToken,
    verificationTokenExpires: Date.now() + 3600000, // 1 hour
  });

  // Dev mode: skip email and auto-verify when disabled
  if (process.env.DISABLE_EMAIL === 'true') {
    user.isVerified = true;
    user.verificationToken = undefined;
    user.verificationTokenExpires = undefined;
    await user.save();
    
    // Broadcast user created event for real-time sync
    if (io) {
      io.emit('userCreated', {
        id: user._id,
        name: user.name,
        email: user.email,
        role: user.role,
      });
    }
    
    return res.status(201).json({
      _id: user._id,
      name: user.name,
      username: user.username,
      email: user.email,
      phone: user.phone,
      employeeId: user.employeeId,
      avatarUrl: user.avatarUrl,
      role: user.role,
      token: generateToken(user._id),
      refreshToken: generateRefreshToken(user._id, user.tokenVersion || 0),
      message: 'User registered (email disabled in dev)',
    });
  }

  const verificationUrl = `${req.protocol}://${req.get('host')}/api/users/verify/${verificationToken}`;

  try {
    await sendEmail({
      email: user.email,
      subject: 'Activate your FieldCheck account',
      templateName: 'accountActivation',
      templateData: { name: user.name, activationLink: verificationUrl },
    });

    res.status(201).json({
      _id: user._id,
      name: user.name,
      username: user.username,
      email: user.email,
      phone: user.phone,
      employeeId: user.employeeId,
      avatarUrl: user.avatarUrl,
      role: user.role,
      message: 'Verification email sent',
    });
  } catch (error) {
    user.verificationToken = undefined;
    user.verificationTokenExpires = undefined;
    await user.save();
    res.status(500);
    throw new Error('Email could not be sent');
  }
});

// @desc    Verify user email
// @route   GET /api/users/verify/:token
// @access  Public
const verifyEmail = asyncHandler(async (req, res) => {
  const { token } = req.params;

  const user = await User.findOne({
    verificationToken: token,
    verificationTokenExpires: { $gt: Date.now() },
  });

  if (!user) {
    res.status(400);
    throw new Error('Invalid or expired verification token');
  }

  user.isVerified = true;
  user.verificationToken = undefined;
  user.verificationTokenExpires = undefined;
  await user.save();

  res.status(200).json({ message: 'Email verified successfully' });
});

// @desc    Forgot password - send reset email
// @route   POST /api/users/forgot-password
// @access  Public
const forgotPassword = asyncHandler(async (req, res) => {
  const { email } = req.body;
  const user = await User.findOne({ email });
  if (!user) {
    // Explicitly return 404 so client can show "Email not found"
    return res.status(404).json({ message: 'Email not found' });
  }

  const resetToken = crypto.randomBytes(32).toString('hex');
  const hashedToken = crypto.createHash('sha256').update(resetToken).digest('hex');
  user.resetPasswordToken = hashedToken;
  user.resetPasswordExpires = Date.now() + 3600000; // 1 hour
  await user.save();

  const resetUrl = `${req.protocol}://${req.get('host')}/api/users/reset-password/${resetToken}`;

  try {
    await sendEmail({
      email: user.email,
      subject: 'Reset your FieldCheck password',
      templateName: 'passwordReset',
      templateData: { name: user.name, resetLink: resetUrl },
    });
    return res.status(200).json({ message: 'Password reset email sent' });
  } catch (error) {
    user.resetPasswordToken = undefined;
    user.resetPasswordExpires = undefined;
    await user.save();
    res.status(500);
    throw new Error('Email could not be sent');
  }
});

// @desc    Reset password
// @route   POST /api/users/reset-password/:token
// @access  Public
const resetPassword = asyncHandler(async (req, res) => {
  const { token } = req.params;
  const { password } = req.body;

  const hashedToken = crypto.createHash('sha256').update(token).digest('hex');

  const user = await User.findOne({
    resetPasswordToken: hashedToken,
    resetPasswordExpires: { $gt: Date.now() },
  });

  if (!user) {
    res.status(400);
    throw new Error('Invalid or expired reset token');
  }

  user.password = password; // will be hashed by pre-save
  user.resetPasswordToken = undefined;
  user.resetPasswordExpires = undefined;
  await user.save();

  res.status(200).json({ message: 'Password reset successful' });
});

// @desc    Get user profile
// @route   GET /api/users/profile
// @access  Private
const getUserProfile = asyncHandler(async (req, res) => {
  const user = await User.findById(req.user._id);
  if (user) {
    res.json({
      _id: user._id,
      name: user.name,
      username: user.username,
      email: user.email,
      phone: user.phone,
      employeeId: user.employeeId,
      avatarUrl: user.avatarUrl,
      role: user.role,
    });
  } else {
    res.status(404);
    throw new Error('User not found');
  }
});

// @desc    Update user profile
// @route   PUT /api/users/profile
// @access  Private
const updateUserProfile = asyncHandler(async (req, res) => {
  const user = await User.findById(req.user._id);
  if (user) {
    user.name = req.body.name || user.name;
    user.username = (req.body.username || user.username || '').toString().trim().toLowerCase();
    user.email = (req.body.email || user.email || '').toString().trim().toLowerCase();
    if (Object.prototype.hasOwnProperty.call(req.body, 'phone')) {
      user.phone = req.body.phone;
    }
    user.avatarUrl = req.body.avatarUrl || user.avatarUrl; // Update avatarUrl

    if (req.body.password) {
      user.password = req.body.password;
    }
  const updatedUser = await user.save();
    res.json({
      _id: updatedUser._id,
      name: updatedUser.name,
      username: updatedUser.username,
      email: updatedUser.email,
      phone: updatedUser.phone,
      avatarUrl: updatedUser.avatarUrl, // Include avatarUrl in the response
      employeeId: updatedUser.employeeId,
      role: updatedUser.role,
      token: generateToken(updatedUser._id),
      refreshToken: generateRefreshToken(updatedUser._id, updatedUser.tokenVersion || 0),
    });
  } else {
    res.status(404);
    throw new Error('User not found');
  }
});

// @desc    Deactivate user account
// @route   PUT /api/users/:id/deactivate
// @access  Private/Admin
const deactivateUser = asyncHandler(async (req, res) => {
  const io = require('../server').io;
  const user = await User.findById(req.params.id);
  if (user) {
    user.isActive = false;
    await user.save();
    
    // Broadcast user deactivated event for real-time sync
    if (io) {
      io.emit('userDeactivated', {
        id: user._id,
        name: user.name,
        email: user.email,
      });
    }
    
    res.json({ message: 'User deactivated successfully' });
  } else {
    res.status(404);
    throw new Error('User not found');
  }
});

// @desc    Reactivate user account
// @route   PUT /api/users/:id/reactivate
// @access  Private/Admin
const reactivateUser = asyncHandler(async (req, res) => {
  const io = require('../server').io;
  const user = await User.findById(req.params.id);
  if (user) {
    user.isActive = true;
    await user.save();
    
    // Broadcast user reactivated event for real-time sync
    if (io) {
      io.emit('userReactivated', {
        id: user._id,
        name: user.name,
        email: user.email,
      });
    }
    
    res.json({ message: 'User reactivated successfully' });
  } else {
    res.status(404);
    throw new Error('User not found');
  }
});

// @desc    Delete user account
// @route   DELETE /api/users/:id
// @access  Private/Admin
const deleteUser = asyncHandler(async (req, res) => {
  const io = require('../server').io;
  const user = await User.findById(req.params.id);
  if (user) {
    const userId = user._id;
    const userName = user.name;
    await user.deleteOne();
    
    // Broadcast user deleted event for real-time sync
    if (io) {
      io.emit('userDeleted', {
        id: userId,
        name: userName,
      });
    }
    
    res.json({ message: 'User removed successfully' });
  } else {
    res.status(404);
    throw new Error('User not found');
  }
});

// @desc    Get users (optionally filter by role)
// @route   GET /api/users
// @access  Private/Admin
const getUsers = asyncHandler(async (req, res) => {
  const { role } = req.query;
  const query = {};
  if (role) {
    query.role = role;
  }
  const users = await User.find(query).select('_id name username email phone role isActive isVerified employeeId avatarUrl');
  res.json(users);
});

// @desc    Update a user (admin)
// @route   PUT /api/users/:id
// @access  Private/Admin
const updateUserByAdmin = asyncHandler(async (req, res) => {
  const user = await User.findById(req.params.id);
  if (!user) {
    res.status(404);
    throw new Error('User not found');
  }

  if (Object.prototype.hasOwnProperty.call(req.body, 'employeeId')) {
    const nextEmployeeId = (req.body.employeeId ?? '').toString().trim();
    if (nextEmployeeId && nextEmployeeId.toLowerCase() !== (user.employeeId || '').toString().trim().toLowerCase()) {
      const employeeIdTaken = await User.findOne({
        employeeId: { $regex: `^${escapeRegExp(nextEmployeeId)}$`, $options: 'i' },
        _id: { $ne: user._id },
      });
      if (employeeIdTaken) {
        res.status(400);
        throw new Error('Employee ID is already taken');
      }
    }
    user.employeeId = nextEmployeeId;
  }

  user.name = req.body.name ?? user.name;
  user.username = (req.body.username ?? user.username ?? '').toString().trim().toLowerCase();
  user.email = (req.body.email ?? user.email ?? '').toString().trim().toLowerCase();
  if (Object.prototype.hasOwnProperty.call(req.body, 'phone')) {
    user.phone = req.body.phone;
  }
  if (req.body.role) user.role = req.body.role;
  if (typeof req.body.isActive !== 'undefined') user.isActive = req.body.isActive;
  const updatedUser = await user.save();
  res.json({
    _id: updatedUser._id,
    name: updatedUser.name,
    username: updatedUser.username,
    email: updatedUser.email,
    phone: updatedUser.phone,
    employeeId: updatedUser.employeeId,
    avatarUrl: updatedUser.avatarUrl,
    role: updatedUser.role,
    isActive: updatedUser.isActive,
  });
});

// @desc    Admin reset user password
// @route   PUT /api/users/:id/reset-password-admin
// @access  Private/Admin
const resetUserPasswordByAdmin = asyncHandler(async (req, res) => {
  const { password } = req.body;
  if (typeof password !== 'string' || password.trim().length < 6) {
    res.status(400);
    throw new Error('Password must be at least 6 characters');
  }

  const user = await User.findById(req.params.id);
  if (!user) {
    res.status(404);
    throw new Error('User not found');
  }

  user.password = password.trim();
  user.tokenVersion = (user.tokenVersion || 0) + 1; // revoke refresh tokens
  await user.save();

  res.json({
    message: 'Password reset successful',
    user: {
      _id: user._id,
      name: user.name,
      username: user.username,
      email: user.email,
      phone: user.phone,
      role: user.role,
      isActive: user.isActive,
      isVerified: user.isVerified,
    },
  });
});

// @desc    Import users from JSON (admin)
// @route   POST /api/users/import
// @access  Private/Admin
const importUsers = asyncHandler(async (req, res) => {
  let list = [];
  if (Array.isArray(req.body)) {
    list = req.body;
  } else if (Array.isArray(req.body.users)) {
    list = req.body.users;
  }
  if (!Array.isArray(list) || list.length === 0) {
    res.status(400);
    throw new Error('No users provided for import');
  }

  const result = { created: 0, updated: 0, skipped: 0, errors: [] };
  for (const raw of list) {
    try {
      const email = raw.email && String(raw.email).toLowerCase().trim();
      if (!email) { result.skipped++; continue; }
      const username = (raw.username && String(raw.username).toLowerCase().trim()) || email.split('@')[0];
      const name = raw.name || username || email.split('@')[0];
      const role = raw.role === 'admin' ? 'admin' : 'employee';
      const isActive = typeof raw.isActive === 'boolean' ? raw.isActive : true;
      const password = raw.password || 'Temp@123';
      const phone = raw.phone && String(raw.phone).trim();

      const existing = await User.findOne({ email });
      if (!existing) {
        await User.create({ name, username, email, password, role, isVerified: true, isActive, phone });
        result.created++;
      } else {
        existing.name = name ?? existing.name;
        existing.username = username ?? existing.username;
        if (raw.password) existing.password = raw.password; // will be hashed by pre-save
        if (raw.role) existing.role = role;
        if (typeof raw.isActive !== 'undefined') existing.isActive = isActive;
        if (typeof phone !== 'undefined' && phone !== null) existing.phone = phone;
        await existing.save();
        result.updated++;
      }
    } catch (e) {
      result.errors.push(String(e.message || e));
    }
  }
  res.json(result);
});

module.exports = {
  authUser,
  registerUser,
  verifyEmail,
  forgotPassword,
  resetPassword,
  getUserProfile,
  updateUserProfile,
  deactivateUser,
  reactivateUser,
  deleteUser,
  getUsers,
  updateUserByAdmin,
  resetUserPasswordByAdmin,
  importUsers,
};

// @desc    Refresh access token
// @route   POST /api/users/refresh-token
// @access  Public (requires refresh token)
const refreshAccessToken = asyncHandler(async (req, res) => {
  const { refreshToken } = req.body;
  if (!refreshToken) {
    res.status(400);
    throw new Error('refreshToken is required');
  }
  let decoded;
  try {
    decoded = verifyRefreshToken(refreshToken);
  } catch (e) {
    res.status(401);
    throw new Error('Invalid refresh token');
  }
  const user = await User.findById(decoded.id);
  if (!user || user.isActive === false) {
    res.status(401);
    throw new Error('User not found or inactive');
  }
  if (!user.isVerified) {
    res.status(403);
    throw new Error('Account not verified');
  }
  const currentVersion = user.tokenVersion || 0;
  if (typeof decoded.tv === 'number' && decoded.tv !== currentVersion) {
    res.status(401);
    throw new Error('Refresh token revoked');
  }
  return res.json({
    token: generateToken(user._id),
    refreshToken: generateRefreshToken(user._id, currentVersion),
  });
});

// @desc    Logout (invalidate refresh tokens)
// @route   POST /api/users/logout
// @access  Private
const logout = asyncHandler(async (req, res) => {
  const user = await User.findById(req.user._id);
  if (!user) {
    res.status(404);
    throw new Error('User not found');
  }
  user.tokenVersion = (user.tokenVersion || 0) + 1;
  user.isOnline = false;
  if (typeof user.status === 'string') {
    user.status = 'offline';
  }
  await user.save();

  try {
    if (global.io) {
      global.io.emit('employeeOffline', {
        employeeId: user._id.toString(),
        timestamp: new Date().toISOString(),
      });
    }
  } catch (_) {}

  res.json({ message: 'Logged out' });
});

// @desc    Google Sign-In
// @route   POST /api/users/google-signin
// @access  Public
const googleSignIn = asyncHandler(async (req, res) => {
  const { idToken } = req.body;
  if (!idToken) {
    res.status(400);
    throw new Error('idToken is required');
  }
  const { OAuth2Client } = require('google-auth-library');
  const googleClient = new OAuth2Client(process.env.GOOGLE_CLIENT_ID);
  const ticket = await googleClient.verifyIdToken({
    idToken,
    audience: process.env.GOOGLE_CLIENT_ID,
  });
  const payload = ticket.getPayload();
  const googleId = payload.sub;
  const email = (payload.email || '').toLowerCase();
  const name = payload.name || payload.given_name || 'User';
  const username = (email ? email.split('@')[0] : name).toLowerCase();

  let user = await User.findOne({ $or: [{ googleId }, { email }] });
  if (!user) {
    const randomPassword = `Google@${crypto.randomBytes(12).toString('hex')}`;
    user = await User.create({
      name,
      username,
      email,
      password: randomPassword,
      role: 'employee',
      isVerified: true,
      isActive: true,
      provider: 'google',
      googleId,
    });
  } else {
    if (!user.googleId) {
      user.googleId = googleId;
      user.provider = 'google';
      await user.save();
    }
  }
  res.json({
    _id: user._id,
    name: user.name,
    username: user.username,
    email: user.email,
    employeeId: user.employeeId,
    avatarUrl: user.avatarUrl,
    role: user.role,
    token: generateToken(user._id),
    refreshToken: generateRefreshToken(user._id, user.tokenVersion || 0),
  });
});

module.exports.refreshAccessToken = refreshAccessToken;
module.exports.logout = logout;
module.exports.googleSignIn = googleSignIn;