const asyncHandler = require('express-async-handler');
const Attendance = require('../models/Attendance');
const Geofence = require('../models/Geofence');
const { io } = require('../server'); // Import the io object
const Report = require('../models/Report');

// @desc    Employee check-in
// @route   POST /api/attendance/checkin
// @access  Private
const checkIn = asyncHandler(async (req, res) => {
  const { geofenceId, latitude, longitude } = req.body;
  const geofence = await Geofence.findById(geofenceId);

  if (!geofence) {
    res.status(404);
    throw new Error('Geofence not found');
  }

  // Server-side geofence validation
  if (geofence.isActive === false) {
    res.status(403);
    throw new Error('Geofence inactive');
  }
  if (Array.isArray(geofence.assignedEmployees) && geofence.assignedEmployees.length > 0) {
    const isAssigned = geofence.assignedEmployees.some((e) => e.toString() === req.user._id.toString());
    if (!isAssigned) {
      res.status(403);
      throw new Error('Employee not assigned to this geofence');
    }
  }
  const toRad = (deg) => (deg * Math.PI) / 180;
  const haversineMeters = (lat1, lon1, lat2, lon2) => {
    const R = 6371000; // meters
    const dLat = toRad(lat2 - lat1);
    const dLon = toRad(lon2 - lon1);
    const a =
      Math.sin(dLat / 2) * Math.sin(dLat / 2) +
      Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) *
      Math.sin(dLon / 2) * Math.sin(dLon / 2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return R * c;
  };
  const distanceMeters = haversineMeters(geofence.latitude, geofence.longitude, latitude, longitude);
  if (distanceMeters > geofence.radius) {
    res.status(403);
    throw new Error('Outside geofence boundary');
  }

  // Check for existing open attendance to prevent double check-in
  const existingOpen = await Attendance.findOne({ 
    employee: req.user._id, 
    checkOut: { $exists: false } 
  });
  if (existingOpen) {
    res.status(400);
    throw new Error('Employee already checked in. Check out first.');
  }

  const attendance = new Attendance({
    employee: req.user._id,
    geofence: geofence._id,
    checkIn: new Date(),
    status: 'in',
    location: { lat: latitude, lng: longitude },
  });

  const created = await attendance.save();
  // Populate before emitting to ensure complete data
  const populatedAttendance = await Attendance.findById(created._id)
    .populate('employee', 'name email')
    .populate('geofence', 'name');
  io.emit('newAttendanceRecord', populatedAttendance);

  // Auto-create attendance report on check-in
  try {
    const rep = await Report.create({
      type: 'attendance',
      attendance: created._id,
      employee: req.user._id,
      geofence: geofence._id,
      content: 'Employee checked in',
    });
    io.emit('newReport', rep);
  } catch (e) {
    console.error('Failed to auto-create attendance check-in report:', e);
  }

  res.status(201).json(created);
});

// @desc    Employee check-out
// @route   POST /api/attendance/checkout
// @access  Private
const checkOut = asyncHandler(async (req, res) => {
  const { latitude, longitude } = req.body;
  const openRecord = await Attendance.findOne({ employee: req.user._id, checkOut: { $exists: false } }).sort({ createdAt: -1 });

  if (!openRecord) {
    res.status(400);
    throw new Error('No active attendance record to check out');
  }

  // Server-side geofence validation on checkout
  const geofence = await Geofence.findById(openRecord.geofence);
  if (!geofence) {
    res.status(404);
    throw new Error('Geofence not found');
  }
  if (geofence.isActive === false) {
    res.status(403);
    throw new Error('Geofence inactive');
  }
  if (Array.isArray(geofence.assignedEmployees) && geofence.assignedEmployees.length > 0) {
    const isAssigned = geofence.assignedEmployees.some((e) => e.toString() === req.user._id.toString());
    if (!isAssigned) {
      res.status(403);
      throw new Error('Employee not assigned to this geofence');
    }
  }
  const toRad = (deg) => (deg * Math.PI) / 180;
  const haversineMeters = (lat1, lon1, lat2, lon2) => {
    const R = 6371000; // meters
    const dLat = toRad(lat2 - lat1);
    const dLon = toRad(lon2 - lon1);
    const a =
      Math.sin(dLat / 2) * Math.sin(dLat / 2) +
      Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) *
      Math.sin(dLon / 2) * Math.sin(dLon / 2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return R * c;
  };
  const distanceMeters = haversineMeters(geofence.latitude, geofence.longitude, latitude, longitude);
  if (distanceMeters > geofence.radius) {
    res.status(403);
    throw new Error('Outside geofence boundary');
  }

  openRecord.checkOut = new Date();
  openRecord.status = 'out';
  openRecord.location = { lat: latitude, lng: longitude };

  const updated = await openRecord.save();
  // Populate before emitting to ensure complete data
  const populatedAttendance = await Attendance.findById(updated._id)
    .populate('employee', 'name email')
    .populate('geofence', 'name');
  io.emit('updatedAttendanceRecord', populatedAttendance);

  // Auto-create attendance report on check-out
  try {
    const rep = await Report.create({
      type: 'attendance',
      attendance: updated._id,
      employee: req.user._id,
      geofence: updated.geofence,
      content: 'Employee checked out',
    });
    io.emit('newReport', rep);
  } catch (e) {
    console.error('Failed to auto-create attendance check-out report:', e);
  }

  res.json(updated);
});

// @desc    Log new attendance record (generic)
// @route   POST /api/attendance
// @access  Private
const logAttendance = asyncHandler(async (req, res) => {
  const { employee, geofence, checkIn, checkOut, status, location } = req.body;

  const attendance = new Attendance({
    employee,
    geofence,
    checkIn,
    checkOut,
    status,
    location,
  });

  const createdAttendance = await attendance.save();
  res.status(201).json(createdAttendance);
});

// @desc    Get all attendance records
// @route   GET /api/attendance
// @access  Private/Admin
const getAttendanceRecords = asyncHandler(async (req, res) => {
  const { employeeId, geofenceId, startDate, endDate, status } = req.query;

  const filter = {};

  if (employeeId) {
    filter.employee = employeeId;
  }
  if (geofenceId) {
    filter.geofence = geofenceId;
  }
  if (status) {
    filter.status = status;
  }
  if (startDate || endDate) {
    filter.checkIn = {};
    if (startDate) {
      filter.checkIn.$gte = new Date(startDate);
    }
    if (endDate) {
      filter.checkIn.$lte = new Date(endDate);
    }
  }

  const attendance = await Attendance.find(filter)
    .populate('employee', 'name email')
    .populate('geofence', 'name');

  res.json(attendance);
});

// @desc    Get attendance record by ID
// @route   GET /api/attendance/:id
// @access  Private/Admin
const getAttendanceById = asyncHandler(async (req, res) => {
  const attendance = await Attendance.findById(req.params.id)
    .populate('employee', 'name email')
    .populate('geofence', 'name');

  if (!attendance) {
    res.status(404);
    throw new Error('Attendance record not found');
  }

  res.json(attendance);
});

// @desc    Update attendance record
// @route   PUT /api/attendance/:id
// @access  Private/Admin
const updateAttendance = asyncHandler(async (req, res) => {
  const attendance = await Attendance.findById(req.params.id);

  if (!attendance) {
    res.status(404);
    throw new Error('Attendance record not found');
  }

  attendance.status = req.body.status || attendance.status;
  attendance.location = req.body.location || attendance.location;

  const updatedAttendance = await attendance.save();
  res.json(updatedAttendance);
});

// @desc    Delete attendance record
// @route   DELETE /api/attendance/:id
// @access  Private/Admin
const deleteAttendance = asyncHandler(async (req, res) => {
  const attendance = await Attendance.findById(req.params.id);

  if (!attendance) {
    res.status(404);
    throw new Error('Attendance record not found');
  }

  await attendance.deleteOne();
  res.status(204).send();
});

// @desc    Get current attendance status for employee
// @route   GET /api/attendance/status
// @access  Private
const getAttendanceStatus = asyncHandler(async (req, res) => {
  const openRecord = await Attendance.findOne({ 
    employee: req.user._id, 
    checkOut: { $exists: false } 
  }).populate('geofence', 'name').sort({ createdAt: -1 });

  const isCheckedIn = !!openRecord;
  let lastCheckTime = null;
  let lastGeofenceName = null;
  let lastCheckTimestamp = null;

  if (openRecord) {
    lastCheckTime = openRecord.checkIn.toLocaleTimeString();
    lastGeofenceName = openRecord.geofence?.name;
    lastCheckTimestamp = openRecord.checkIn;
  } else {
    // Get last check-out time
    const lastRecord = await Attendance.findOne({ 
      employee: req.user._id 
    }).populate('geofence', 'name').sort({ createdAt: -1 });
    
    if (lastRecord) {
      lastCheckTime = lastRecord.checkOut ? lastRecord.checkOut.toLocaleTimeString() : lastRecord.checkIn.toLocaleTimeString();
      lastGeofenceName = lastRecord.geofence?.name;
      lastCheckTimestamp = lastRecord.checkOut || lastRecord.checkIn;
    }
  }

  res.json({
    isCheckedIn,
    lastCheckTime,
    lastGeofenceName,
    lastCheckTimestamp,
  });
});

// @desc    Get attendance history for employee
// @route   GET /api/attendance/history
// @access  Private
const getAttendanceHistory = asyncHandler(async (req, res) => {
  const { startDate, endDate } = req.query;
  
  const filter = { employee: req.user._id };
  
  if (startDate || endDate) {
    filter.checkIn = {};
    if (startDate) {
      filter.checkIn.$gte = new Date(startDate);
    }
    if (endDate) {
      filter.checkIn.$lte = new Date(endDate);
    }
  }

  const attendance = await Attendance.find(filter)
    .populate('geofence', 'name')
    .sort({ checkIn: -1 })
    .limit(100); // Limit to last 100 records

  const records = attendance.map(record => ({
    id: record._id,
    isCheckIn: record.status === 'in',
    timestamp: record.checkIn,
    latitude: record.location?.lat,
    longitude: record.location?.lng,
    geofenceId: record.geofence?._id,
    geofenceName: record.geofence?.name,
    userId: record.employee,
  }));

  res.json({ records });
});

module.exports = {
  checkIn,
  checkOut,
  logAttendance,
  getAttendanceRecords,
  getAttendanceById,
  updateAttendance,
  deleteAttendance,
  getAttendanceStatus,
  getAttendanceHistory,
};