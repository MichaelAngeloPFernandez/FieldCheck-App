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
  
  // Validate location coordinates
  if (isNaN(latitude) || isNaN(longitude) || latitude === undefined || longitude === undefined) {
    res.status(400);
    throw new Error('Invalid latitude or longitude');
  }
  
  const geofence = await Geofence.findById(geofenceId);

  if (!geofence) {
    res.status(404);
    throw new Error('Geofence not found');
  }

  // Note: We allow any employee to check in at any geofence if within boundary.
  // Geofence active status is not enforced - employees can check in at inactive geofences.
  // Assignment is optional and not enforced at check-in time.
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

  // Record time in Philippine timezone (UTC+8)
  const phTime = new Date(new Date().getTime() + (8 * 60 * 60 * 1000));
  
  const attendance = new Attendance({
    employee: req.user._id,
    geofence: geofence._id,
    checkIn: phTime,
    status: 'in',
    location: { lat: latitude, lng: longitude },
  });

  const created = await attendance.save();
  
  // Emit immediately with basic data for fast UI update
  io.emit('newAttendanceRecord', {
    _id: created._id,
    employee: { _id: req.user._id, name: req.user.name },
    geofence: { _id: geofence._id, name: geofence.name },
    checkIn: created.checkIn,
    status: created.status,
    location: created.location,
  });

  // Populate and emit full data asynchronously (don't block response)
  setImmediate(async () => {
    try {
      const populatedAttendance = await Attendance.findById(created._id)
        .populate('employee', 'name email')
        .populate('geofence', 'name');
      io.emit('newAttendanceRecord', populatedAttendance);
    } catch (e) {
      console.error('Error populating attendance:', e);
    }
  });

  // Auto-create attendance report in background (don't block response)
  setImmediate(async () => {
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
  });

  res.status(201).json(created);
});

// @desc    Employee check-out
// @route   POST /api/attendance/checkout
// @access  Private
const checkOut = asyncHandler(async (req, res) => {
  const { latitude, longitude, geofenceId } = req.body;
  
  // Validate location coordinates
  if (isNaN(latitude) || isNaN(longitude) || latitude === undefined || longitude === undefined) {
    res.status(400);
    throw new Error('Invalid latitude or longitude');
  }
  
  const openRecord = await Attendance.findOne({ 
    employee: req.user._id, 
    checkOut: { $exists: false } 
  }).sort({ createdAt: -1 }).populate('geofence');

  if (!openRecord) {
    res.status(400);
    throw new Error('No active attendance record to check out');
  }

  // CRITICAL: Ensure geofence exists in the record
  if (!openRecord.geofence) {
    // If geofence is missing, try to find employee's assigned geofence
    if (!geofenceId) {
      res.status(400);
      throw new Error('Geofence information missing. Please check in again.');
    }
    
    const geofence = await Geofence.findById(geofenceId);
    if (!geofence) {
      res.status(404);
      throw new Error('Geofence not found');
    }
    
    // Assign geofence to the record
    openRecord.geofence = geofence._id;
    console.warn(`⚠️ WARNING: Attendance record ${openRecord._id} had missing geofence. Auto-assigned: ${geofence._id}`);
  }
  
  // Get the geofence (either from record or just assigned)
  const geofence = openRecord.geofence._id 
    ? await Geofence.findById(openRecord.geofence._id)
    : await Geofence.findById(openRecord.geofence);
    
  if (!geofence) {
    res.status(404);
    throw new Error('Geofence not found in database');
  }
  // Note: We skip geofence active/assignment/distance checks on checkout.
  // Client already validated on check-in. Employees should be able to check out
  // even if they've moved outside the geofence or if the geofence is inactive.

  // Record time in Philippine timezone (UTC+8)
  const phTime = new Date(new Date().getTime() + (8 * 60 * 60 * 1000));
  
  openRecord.checkOut = phTime;
  openRecord.status = 'out';
  openRecord.location = { lat: latitude, lng: longitude };

  const updated = await openRecord.save();
  
  // Emit immediately with basic data for fast UI update
  io.emit('updatedAttendanceRecord', {
    _id: updated._id,
    employee: { _id: req.user._id, name: req.user.name },
    geofence: { _id: geofence._id, name: geofence.name },
    checkIn: updated.checkIn,
    checkOut: updated.checkOut,
    status: updated.status,
    location: updated.location,
  });

  // Populate and emit full data asynchronously (don't block response)
  setImmediate(async () => {
    try {
      const populatedAttendance = await Attendance.findById(updated._id)
        .populate('employee', 'name email')
        .populate('geofence', 'name');
      io.emit('updatedAttendanceRecord', populatedAttendance);
    } catch (e) {
      console.error('Error populating attendance:', e);
    }
  });

  // Auto-create attendance report in background (don't block response)
  setImmediate(async () => {
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
  });

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
    .populate('geofence', 'name')
    .sort({ checkIn: -1 });

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

// @desc    Delete a single attendance record for the logged-in employee
// @route   DELETE /api/attendance/history/:id
// @access  Private
const deleteMyAttendanceRecord = asyncHandler(async (req, res) => {
  const attendance = await Attendance.findById(req.params.id);

  if (!attendance) {
    res.status(404);
    throw new Error('Attendance record not found');
  }

  if (attendance.employee.toString() !== req.user._id.toString()) {
    res.status(403);
    throw new Error('Not authorized to delete this attendance record');
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

  // Helper function to format time as HH:MM AM/PM in PH timezone (UTC+8)
  const formatTime = (date) => {
    if (!date) return null;
    const d = new Date(date);
    // Convert to PH timezone (UTC+8)
    const phTime = new Date(d.getTime() + (8 * 60 * 60 * 1000));
    const hours = phTime.getUTCHours();
    const minutes = String(phTime.getUTCMinutes()).padStart(2, '0');
    const ampm = hours >= 12 ? 'PM' : 'AM';
    const displayHours = hours % 12 || 12;
    return `${String(displayHours).padStart(2, '0')}:${minutes} ${ampm}`;
  };

  if (openRecord) {
    lastCheckTime = formatTime(openRecord.checkIn);
    lastGeofenceName = openRecord.geofence?.name;
    lastCheckTimestamp = openRecord.checkIn;
  } else {
    // Get last check-out time
    const lastRecord = await Attendance.findOne({ 
      employee: req.user._id 
    }).populate('geofence', 'name').sort({ createdAt: -1 });
    
    if (lastRecord) {
      lastCheckTime = formatTime(lastRecord.checkOut || lastRecord.checkIn);
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

// @desc    Delete attendance history for logged-in employee for a specific month
// @route   DELETE /api/attendance/history?year=YYYY&month=MM
// @access  Private
const deleteMyAttendanceHistoryByMonth = asyncHandler(async (req, res) => {
  const { year, month } = req.query;

  if (!year || !month) {
    res.status(400);
    throw new Error('Year and month are required');
  }

  const y = parseInt(year, 10);
  const m = parseInt(month, 10);

  if (Number.isNaN(y) || Number.isNaN(m) || m < 1 || m > 12) {
    res.status(400);
    throw new Error('Invalid year or month');
  }

  const start = new Date(Date.UTC(y, m - 1, 1, 0, 0, 0, 0));
  const end = new Date(Date.UTC(y, m, 0, 23, 59, 59, 999));

  const result = await Attendance.deleteMany({
    employee: req.user._id,
    checkIn: { $gte: start, $lte: end },
  });

  res.json({ deletedCount: result.deletedCount || 0 });
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
  deleteMyAttendanceRecord,
  deleteMyAttendanceHistoryByMonth,
};