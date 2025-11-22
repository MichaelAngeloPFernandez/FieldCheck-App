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
    // Update all fields with proper null/undefined handling
    if (name !== undefined && name !== null) geofence.name = name;
    if (address !== undefined && address !== null) geofence.address = address;
    if (latitude !== undefined && latitude !== null) geofence.latitude = latitude;
    if (longitude !== undefined && longitude !== null) geofence.longitude = longitude;
    if (radius !== undefined && radius !== null) geofence.radius = radius;
    if (shape !== undefined && shape !== null) geofence.shape = shape;
    if (isActive !== undefined && isActive !== null) geofence.isActive = isActive;
    if (type !== undefined && type !== null) geofence.type = type;
    if (labelLetter !== undefined && labelLetter !== null) geofence.labelLetter = labelLetter;
    // Important: Handle assignedEmployees as array with proper validation
    if (Array.isArray(assignedEmployees)) {
      geofence.assignedEmployees = assignedEmployees;
    }

    const updatedGeofence = await geofence.save();
    // Populate assignedEmployees before emitting to ensure frontend has complete data
    const populatedGeofence = await Geofence.findById(updatedGeofence._id)
      .populate('assignedEmployees', '_id name email role');
    // Emit real-time geofence update
    io.emit('geofenceUpdated', populatedGeofence);
    res.json(populatedGeofence);
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