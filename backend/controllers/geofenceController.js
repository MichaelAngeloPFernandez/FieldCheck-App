const asyncHandler = require('express-async-handler');
const Geofence = require('../models/Geofence');
const Attendance = require('../models/Attendance');
const Report = require('../models/Report');
const { io } = require('../server');

// @desc    Create a new geofence
// @route   POST /api/geofences
// @access  Private/Admin
const createGeofence = asyncHandler(async (req, res) => {
  const { name, address, latitude, longitude, radius, shape, isActive, assignedEmployees, labelLetter } = req.body;

  // Validate required fields
  if (!name || name.trim() === '') {
    res.status(400);
    throw new Error('Geofence name is required');
  }
  if (latitude === undefined || latitude === null) {
    res.status(400);
    throw new Error('Latitude is required');
  }
  if (longitude === undefined || longitude === null) {
    res.status(400);
    throw new Error('Longitude is required');
  }
  if (radius === undefined || radius === null || radius <= 0) {
    res.status(400);
    throw new Error('Radius must be a positive number');
  }

  const geofence = new Geofence({
    name: name.trim(),
    address: address || '',
    latitude: parseFloat(latitude),
    longitude: parseFloat(longitude),
    radius: parseFloat(radius),
    shape: shape || 'circle',
    isActive: isActive !== undefined ? isActive : true,
    assignedEmployees: Array.isArray(assignedEmployees) ? assignedEmployees : [],
    labelLetter: labelLetter || '',
  });

  try {
    const createdGeofence = await geofence.save();
    // Populate before emitting
    const populatedGeofence = await Geofence.findById(createdGeofence._id)
      .populate('assignedEmployees', '_id name email role');
    // Emit real-time geofence creation
    io.emit('geofenceCreated', populatedGeofence);
    res.status(201).json(populatedGeofence);
  } catch (error) {
    res.status(400);
    throw new Error(`Failed to create geofence: ${error.message}`);
  }
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
  const { name, address, latitude, longitude, radius, shape, isActive, labelLetter, assignedEmployees } = req.body;

  const geofence = await Geofence.findById(req.params.id);

  if (geofence) {
    // Track which employees were removed from assignment
    const previousEmployeeIds = geofence.assignedEmployees.map(id => id.toString());
    const newEmployeeIds = Array.isArray(assignedEmployees) ? assignedEmployees.map(id => id.toString()) : [];
    const removedEmployeeIds = previousEmployeeIds.filter(id => !newEmployeeIds.includes(id));

    // Update all fields with proper null/undefined handling
    if (name !== undefined && name !== null) geofence.name = name;
    if (address !== undefined && address !== null) geofence.address = address;
    if (latitude !== undefined && latitude !== null) geofence.latitude = latitude;
    if (longitude !== undefined && longitude !== null) geofence.longitude = longitude;
    if (radius !== undefined && radius !== null) geofence.radius = radius;
    if (shape !== undefined && shape !== null) geofence.shape = shape;
    if (isActive !== undefined && isActive !== null) geofence.isActive = isActive;
    if (labelLetter !== undefined && labelLetter !== null) geofence.labelLetter = labelLetter;
    if (Array.isArray(assignedEmployees)) geofence.assignedEmployees = assignedEmployees;

    const updatedGeofence = await geofence.save();

    // Auto-checkout employees removed from this geofence
    if (removedEmployeeIds.length > 0) {
      setImmediate(async () => {
        try {
          for (const employeeId of removedEmployeeIds) {
            // Find active attendance record for this employee at this geofence
            const openRecord = await Attendance.findOne({
              employee: employeeId,
              geofence: geofence._id,
              checkOut: { $exists: false },
            }).populate('employee', 'name');

            if (openRecord) {
              // Auto-checkout the employee
              const now = new Date();
              openRecord.checkOut = now;
              openRecord.status = 'out';
              openRecord.isVoid = true;
              openRecord.voidReason = 'Auto-checkout: Employee removed from geofence assignment';
              await openRecord.save();

              // Create void attendance report
              try {
                const report = await Report.create({
                  type: 'attendance',
                  attendance: openRecord._id,
                  employee: employeeId,
                  geofence: geofence._id,
                  content: `Auto-checkout: Employee removed from geofence assignment by admin`,
                });
                io.emit('newReport', report);
              } catch (e) {
                console.error('Failed to create auto-checkout report:', e);
              }

              // Emit auto-checkout event
              io.emit('employeeAutoCheckout', {
                employeeId,
                employeeName: openRecord.employee?.name || 'Unknown',
                geofenceName: geofence.name,
                reason: 'Employee removed from geofence assignment',
                checkOutTime: now,
                isVoid: true,
              });

              console.log(`✅ Auto-checkout: ${openRecord.employee?.name} from ${geofence.name} (removed from assignment)`);
            }
          }
        } catch (e) {
          console.error('Error auto-checking out removed employees:', e);
        }
      });
    }

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