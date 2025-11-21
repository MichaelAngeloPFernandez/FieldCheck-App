const asyncHandler = require('express-async-handler');
const Geofence = require('../models/Geofence');
const { io } = require('../server');

// @desc    Create a new geofence
// @route   POST /api/geofences
// @access  Private/Admin
const createGeofence = asyncHandler(async (req, res) => {
  const { name, address, latitude, longitude, radius, shape, isActive, assignedEmployees, type, labelLetter } = req.body;

  const geofence = new Geofence({
    name,
    address,
    latitude,
    longitude,
    radius,
    shape,
    isActive,
    assignedEmployees,
    type,
    labelLetter,
  });

  const createdGeofence = await geofence.save();
  // Emit real-time geofence creation
  io.emit('geofenceCreated', createdGeofence);
  res.status(201).json(createdGeofence);
});

// @desc    Get all geofences
// @route   GET /api/geofences
// @access  Private/Admin
const getGeofences = asyncHandler(async (req, res) => {
  const geofences = await Geofence.find({}).populate('assignedEmployees', '_id name email role');
  res.json(geofences);
});

// @desc    Get geofence by ID
// @route   GET /api/geofences/:id
// @access  Private/Admin
const getGeofenceById = asyncHandler(async (req, res) => {
  const geofence = await Geofence.findById(req.params.id).populate('assignedEmployees', '_id name email role');

  if (geofence) {
    res.json(geofence);
  } else {
    res.status(404);
    throw new Error('Geofence not found');
  }
});

// @desc    Update a geofence
// @route   PUT /api/geofences/:id
// @access  Private/Admin
const updateGeofence = asyncHandler(async (req, res) => {
  const { name, address, latitude, longitude, radius, shape, isActive, assignedEmployees, type, labelLetter } = req.body;

  const geofence = await Geofence.findById(req.params.id);

  if (geofence) {
    geofence.name = name || geofence.name;
    geofence.address = address !== undefined ? address : geofence.address;
    geofence.latitude = latitude || geofence.latitude;
    geofence.longitude = longitude || geofence.longitude;
    geofence.radius = radius || geofence.radius;
    geofence.shape = shape || geofence.shape;
    geofence.isActive = isActive !== undefined ? isActive : geofence.isActive;
    geofence.assignedEmployees = assignedEmployees || geofence.assignedEmployees;
    geofence.type = type || geofence.type;
    geofence.labelLetter = labelLetter !== undefined ? labelLetter : geofence.labelLetter;

    const updatedGeofence = await geofence.save();
    // Emit real-time geofence update
    io.emit('geofenceUpdated', updatedGeofence);
    res.json(updatedGeofence);
  } else {
    res.status(404);
    throw new Error('Geofence not found');
  }
});

// @desc    Delete a geofence
// @route   DELETE /api/geofences/:id
// @access  Private/Admin
const deleteGeofence = asyncHandler(async (req, res) => {
  const geofence = await Geofence.findById(req.params.id);

  if (geofence) {
    await geofence.deleteOne();
    // Emit real-time geofence deletion
    io.emit('geofenceDeleted', { id: req.params.id });
    res.json({ message: 'Geofence removed' });
  } else {
    res.status(404);
    throw new Error('Geofence not found');
  }
});

module.exports = {
  createGeofence,
  getGeofences,
  getGeofenceById,
  updateGeofence,
  deleteGeofence,
};