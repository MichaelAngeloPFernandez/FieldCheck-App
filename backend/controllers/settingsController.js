const asyncHandler = require('express-async-handler');
const Settings = require('../models/Settings');
const { io } = require('../server');

// @desc    Get all settings
// @route   GET /api/settings
// @access  Private/Admin
const getSettings = asyncHandler(async (req, res) => {
  const settings = await Settings.find({});
  const settingsObject = {};
  settings.forEach(setting => {
    settingsObject[setting.key] = setting.value;
  });
  res.json(settingsObject);
});

// @desc    Get a specific setting
// @route   GET /api/settings/:key
// @access  Private/Admin
const getSetting = asyncHandler(async (req, res) => {
  const setting = await Settings.findOne({ key: req.params.key });
  
  if (setting) {
    res.json({ key: setting.key, value: setting.value });
  } else {
    res.status(404);
    throw new Error('Setting not found');
  }
});

// @desc    Update or create a setting
// @route   PUT /api/settings/:key
// @access  Private/Admin
const updateSetting = asyncHandler(async (req, res) => {
  const { value, description } = req.body;
  
  const setting = await Settings.findOneAndUpdate(
    { key: req.params.key },
    { 
      value,
      description: description || undefined,
    },
    { 
      upsert: true, 
      new: true,
      runValidators: true 
    }
  );
  
  // Emit real-time settings update for a single key
  io.emit('settingsUpdated', { key: setting.key, value: setting.value });
  res.json(setting);
});

// @desc    Update multiple settings
// @route   PUT /api/settings
// @access  Private/Admin
const updateSettings = asyncHandler(async (req, res) => {
  const settingsToUpdate = req.body;
  
  const updatePromises = Object.entries(settingsToUpdate).map(async ([key, value]) => {
    return Settings.findOneAndUpdate(
      { key },
      { value },
      { upsert: true, new: true }
    );
  });
  
  await Promise.all(updatePromises);
  
  // Return all settings
  const allSettings = await Settings.find({});
  const settingsObject = {};
  allSettings.forEach(setting => {
    settingsObject[setting.key] = setting.value;
  });
  
  // Emit real-time bulk settings update
  io.emit('settingsUpdated', settingsObject);
  res.json(settingsObject);
});

// @desc    Delete a setting
// @route   DELETE /api/settings/:key
// @access  Private/Admin
const deleteSetting = asyncHandler(async (req, res) => {
  const setting = await Settings.findOneAndDelete({ key: req.params.key });
  
  if (setting) {
    // Emit real-time deletion notification
    io.emit('settingsUpdated', { key: req.params.key, deleted: true });
    res.json({ message: 'Setting removed' });
  } else {
    res.status(404);
    throw new Error('Setting not found');
  }
});

module.exports = {
  getSettings,
  getSetting,
  updateSetting,
  updateSettings,
  deleteSetting,
};
