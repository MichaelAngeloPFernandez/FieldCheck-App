const asyncHandler = require('express-async-handler');
const Attendance = require('../models/Attendance');
const Geofence = require('../models/Geofence');
const { io } = require('../server'); // Import the io object
const Report = require('../models/Report');
const User = require('../models/User');
const UserTask = require('../models/UserTask');
const appNotificationService = require('../services/appNotificationService');
const notificationService = require('../services/notificationService');

async function populateReportById(reportId) {
  return await Report.findById(reportId)
    .populate('employee', 'name email employeeId avatarUrl')
    .populate('task', 'title description difficulty dueDate status isArchived')
    .populate('attendance')
    .populate('geofence', 'name');
}

// @desc    Employee check-in
// @route   POST /api/attendance/checkin
// @access  Private
const checkIn = asyncHandler(async (req, res) => {
  const { geofenceId, latitude, longitude } = req.body;
  
  // Validate location coordinates
  if (isNaN(latitude) || isNaN(longitude) || latitude === undefined || longitude === undefined) {
    notificationService
      .notifyLocationWarning(req.user, 'Invalid latitude or longitude')
      .catch(() => {});
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
    notificationService
      .notifyLocationWarning(
        req.user,
        `Outside geofence boundary of ${geofence.name}`,
      )
      .catch(() => {});
    res.status(403);
    throw new Error('Outside geofence boundary');
  }

  // If there's any prior open attendance record for this employee, close it
  // before creating a new check-in. This prevents stuck/open sessions when
  // previous check-outs were missed due to client/network/timezone issues.
  const now = new Date();
  const phTime = new Date(now.getTime());

  const priorOpen = await Attendance.findOne({
    employee: req.user._id,
    checkOut: { $exists: false },
  }).sort({ createdAt: -1 }).populate('geofence');

  if (priorOpen) {
    try {
      priorOpen.checkOut = phTime;
      priorOpen.status = 'out';
      priorOpen.autoCheckout = true;
      priorOpen.voidReason = 'Auto-closed by new check-in to prevent overlapping sessions';
      const saved = await priorOpen.save();

      // Emit updated record and an admin notification about the auto-close
      io.emit('updatedAttendanceRecord', {
        _id: saved._id,
        employee: { _id: req.user._id, name: req.user.name },
        geofence: { _id: priorOpen.geofence?._id || null, name: priorOpen.geofence?.name || null },
        checkIn: saved.checkIn,
        checkOut: saved.checkOut,
        status: saved.status,
        location: saved.location,
        autoCheckout: true,
      });

      io.emit('adminNotification', {
        type: 'attendance',
        action: 'auto-checkout',
        userId: req.user._id,
        employeeId: req.user.employeeId,
        employeeName: req.user.name,
        geofenceName: priorOpen.geofence?.name || null,
        checkInTime: saved.checkIn,
        checkOutTime: saved.checkOut,
        elapsedHours: saved.checkOut && saved.checkIn ? ((saved.checkOut - saved.checkIn) / (1000 * 60 * 60)).toFixed(2) : null,
        timestamp: saved.checkOut,
        message: `${req.user.name} previous session auto-closed before new check-in`,
        severity: 'warning',
      });

      setImmediate(async () => {
        try {
          await notificationService.notifyAutoCheckoutWarning(
            req.user,
            null,
            priorOpen.geofence?.name || null,
          );
        } catch (_) {}
      });
    } catch (e) {
      console.error('Failed to auto-close prior open attendance for', req.user._id, e.message || e);
    }
  }

  // Record time in Philippine timezone (UTC+8)
  // (phTime already computed above to support prior auto-close)
  const attendance = new Attendance({
    employee: req.user._id,
    geofence: geofence._id,
    checkIn: phTime,
    status: 'in',
    location: { lat: latitude, lng: longitude },
  });

  const created = await attendance.save();

  // Persist last-known coordinates & online status so admin late-join snapshots
  // always have a reliable location even if live GPS sharing is disabled.
  try {
    const now = new Date();
    const userId = req.user?._id;
    if (userId) {
      const activeTaskCount = await UserTask.countDocuments({
        userId,
        isArchived: { $ne: true },
        status: { $ne: 'completed' },
      });

      await User.findByIdAndUpdate(
        userId,
        {
          isOnline: true,
          lastLatitude: Number(latitude),
          lastLongitude: Number(longitude),
          lastLocationUpdate: now,
          activeTaskCount,
        },
        { new: false },
      );

      const inProgressCount = await UserTask.countDocuments({
        userId,
        isArchived: { $ne: true },
        status: 'in_progress',
      });

      io.emit('employeeLocationUpdate', {
        employeeId: userId.toString(),
        name: req.user?.name ? String(req.user.name) : 'Employee',
        username: req.user?.username ? String(req.user.username) : null,
        latitude: Number(latitude),
        longitude: Number(longitude),
        accuracy: 0,
        speed: 0,
        status: inProgressCount > 0 ? 'busy' : 'available',
        timestamp: now.toISOString(),
        activeTaskCount,
        workloadScore: 0,
        currentGeofence: geofence?.name || null,
        distanceToNearestTask: null,
        isOnline: true,
        batteryLevel: null,
      });
    }
  } catch (_) {}

  // Emit immediately with basic data for fast UI update
  io.emit('newAttendanceRecord', {
    _id: created._id,
    employee: { _id: req.user._id, name: req.user.name },
    geofence: { _id: geofence._id, name: geofence.name },
    checkIn: created.checkIn,
    status: created.status,
    location: created.location,
  });

  // Emit admin notification for check-in event
  io.emit('adminNotification', {
    type: 'attendance',
    action: 'check-in',
    userId: req.user._id,
    employeeId: req.user.employeeId,
    employeeName: req.user.name,
    geofenceName: geofence.name,
    timestamp: created.checkIn,
    message: `${req.user.name} checked in at ${geofence.name}`,
    severity: 'info',
  });

  try {
    await appNotificationService.createForAdmins({
      excludeUserId: req.user._id,
      type: 'attendance',
      action: 'check-in',
      title: 'Employee Check-in',
      message: `${req.user.name} checked in at ${geofence.name}`,
      payload: {
        userId: req.user._id.toString(),
        employeeId: req.user.employeeId,
        employeeName: req.user.name,
        geofenceName: geofence.name,
        checkInTime: created.checkIn,
      },
    });
  } catch (_) {}

  setImmediate(async () => {
    try {
      await notificationService.notifyAttendanceCheckIn(req.user, geofence);
    } catch (_) {}
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
      try {
        const populated = await populateReportById(rep._id);
        io.emit('newReport', populated || rep);
      } catch (_) {
        io.emit('newReport', rep);
      }
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

  console.log(
    `[CHECKOUT] Employee ${req.user._id} attempting checkout with geofenceId: ${geofenceId}`,
  );

  // Validate location coordinates
  if (isNaN(latitude) || isNaN(longitude) || latitude === undefined || longitude === undefined) {
    notificationService
      .notifyLocationWarning(req.user, 'Invalid latitude or longitude')
      .catch(() => {});
    res.status(400);
    throw new Error('Invalid latitude or longitude');
  }

  // Find the most recent open attendance record for this employee
  // Do NOT restrict by local "today" window — sometimes date math
  // mismatches (timezone shifts) can prevent finding the open record.
  // Searching by employee + missing checkOut and sorting ensures we
  // pick the latest open session to close out.
  const openRecord = await Attendance.findOne({
    employee: req.user._id,
    checkOut: { $exists: false },
  })
    .sort({ createdAt: -1 })
    .populate('geofence');

  if (!openRecord) {
    console.log(`[CHECKOUT] No open record found for employee ${req.user._id}`);
    res.status(400);
    throw new Error('No active attendance record to check out');
  }

  console.log(
    `[CHECKOUT] Found open record: ${openRecord._id}, geofence: ${openRecord.geofence?._id}`,
  );

  // CRITICAL: Ensure geofence exists in the record
  if (!openRecord.geofence) {
    // If geofence is missing, try to find employee's assigned geofence
    if (!geofenceId) {
      res.status(400);
      throw new Error('Geofence information missing. Please check in again.');
    }

    const fallbackGeofence = await Geofence.findById(geofenceId);
    if (!fallbackGeofence) {
      res.status(404);
      throw new Error('Geofence not found');
    }

    // Assign geofence to the record
    openRecord.geofence = fallbackGeofence._id;
    console.warn(
      `⚠️ WARNING: Attendance record ${openRecord._id} had missing geofence. Auto-assigned: ${fallbackGeofence._id}`,
    );
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
  const phTime = new Date();

  openRecord.checkOut = phTime;
  openRecord.status = 'out';
  openRecord.location = { lat: latitude, lng: longitude };

  const updated = await openRecord.save();

  // Persist last-known coordinates & online status for late-join admin snapshots
  // and emit a rich employeeLocationUpdate to refresh admin map/status instantly.
  try {
    const now = new Date();
    const userId = req.user?._id;
    if (userId) {
      const activeTaskCount = await UserTask.countDocuments({
        userId,
        isArchived: { $ne: true },
        status: { $ne: 'completed' },
      });

      await User.findByIdAndUpdate(
        userId,
        {
          isOnline: true,
          lastLatitude: Number(latitude),
          lastLongitude: Number(longitude),
          lastLocationUpdate: now,
          activeTaskCount,
        },
        { new: false },
      );

      const inProgressCount = await UserTask.countDocuments({
        userId,
        isArchived: { $ne: true },
        status: 'in_progress',
      });

      io.emit('employeeLocationUpdate', {
        employeeId: userId.toString(),
        name: req.user?.name ? String(req.user.name) : 'Employee',
        username: req.user?.username ? String(req.user.username) : null,
        latitude: Number(latitude),
        longitude: Number(longitude),
        accuracy: 0,
        speed: 0,
        status: inProgressCount > 0 ? 'busy' : 'moving',
        timestamp: now.toISOString(),
        activeTaskCount,
        workloadScore: 0,
        currentGeofence: geofence?.name || null,
        distanceToNearestTask: null,
        isOnline: true,
        batteryLevel: null,
      });
    }
  } catch (_) {}

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

  // Emit admin notification for check-out event
  io.emit('adminNotification', {
    type: 'attendance',
    action: 'check-out',
    userId: req.user._id,
    employeeId: req.user.employeeId,
    employeeName: req.user.name,
    geofenceName: geofence.name,
    checkInTime: updated.checkIn,
    checkOutTime: updated.checkOut,
    elapsedHours: ((updated.checkOut - updated.checkIn) / (1000 * 60 * 60)).toFixed(2),
    timestamp: updated.checkOut,
    message: `${req.user.name} checked out from ${geofence.name}`,
    severity: 'info',
  });

  try {
    await appNotificationService.createForAdmins({
      excludeUserId: req.user._id,
      type: 'attendance',
      action: 'check-out',
      title: 'Employee Checked Out',
      message: `${req.user.name} checked out from ${geofence.name}`,
      payload: {
        userId: req.user._id.toString(),
        employeeId: req.user.employeeId,
        employeeName: req.user.name,
        geofenceId: geofence._id.toString(),
        geofenceName: geofence.name,
        checkInTime: updated.checkIn,
        checkOutTime: updated.checkOut,
        elapsedHours: ((updated.checkOut - updated.checkIn) / (1000 * 60 * 60)).toFixed(2),
      },
    });
  } catch (_) {}

  setImmediate(async () => {
    try {
      await notificationService.notifyAttendanceCheckOut(req.user, geofence);
    } catch (_) {}
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
      try {
        const populated = await populateReportById(rep._id);
        io.emit('newReport', populated || rep);
      } catch (_) {
        io.emit('newReport', rep);
      }
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
  const { employeeId, geofenceId, startDate, endDate, status, archived } =
    req.query;

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

  if (archived === 'true') {
    filter.isArchived = true;
  } else if (archived === 'false') {
    filter.isArchived = false;
  }

  const attendance = await Attendance.find(filter)
    .populate('employee', 'name email')
    .populate('geofence', 'name')
    .sort({ checkIn: -1 });

  res.json(attendance);
});

// @desc    Archive attendance record
// @route   PUT /api/attendance/:id/archive
// @access  Private/Admin
const archiveAttendanceRecord = asyncHandler(async (req, res) => {
  const attendance = await Attendance.findById(req.params.id)
    .populate('employee', 'name email')
    .populate('geofence', 'name');

  if (!attendance) {
    res.status(404);
    throw new Error('Attendance record not found');
  }

  attendance.isArchived = true;
  const saved = await attendance.save();

  io.emit('updatedAttendanceRecord', saved);

  res.json(saved);
});

// @desc    Restore attendance record
// @route   PUT /api/attendance/:id/restore
// @access  Private/Admin
const restoreAttendanceRecord = asyncHandler(async (req, res) => {
  const attendance = await Attendance.findById(req.params.id)
    .populate('employee', 'name email')
    .populate('geofence', 'name');

  if (!attendance) {
    res.status(404);
    throw new Error('Attendance record not found');
  }

  attendance.isArchived = false;
  const saved = await attendance.save();

  io.emit('updatedAttendanceRecord', saved);

  res.json(saved);
});

// @desc    Get attendance status for all employees (Admin only)
// @route   GET /api/attendance/admin/all-status
// @access  Private/Admin
const getAllEmployeesAttendanceStatus = asyncHandler(async (req, res) => {
  const now = new Date();
  const offsetMs = 8 * 60 * 60 * 1000;
  const phNow = new Date(now.getTime() + offsetMs);
  const todayStart = new Date(
    Date.UTC(
      phNow.getUTCFullYear(),
      phNow.getUTCMonth(),
      phNow.getUTCDate(),
      0,
      0,
      0,
      0,
    ) - offsetMs,
  );
  const todayEnd = new Date(
    Date.UTC(
      phNow.getUTCFullYear(),
      phNow.getUTCMonth(),
      phNow.getUTCDate(),
      23,
      59,
      59,
      999,
    ) - offsetMs,
  );

  // Get all open attendance records for today
  const openRecords = await Attendance.find({
    checkOut: { $exists: false },
    checkIn: { $gte: todayStart, $lte: todayEnd }
  })
    .populate('employee', 'name email')
    .populate('geofence', 'name');

  // Get all employees
  const allEmployees = await User.find({ role: 'employee', isActive: true }).select('name email');

  // Map attendance status by employee ID
  const attendanceMap = new Map();
  openRecords.forEach(record => {
    attendanceMap.set(record.employee._id.toString(), {
      isCheckedIn: true,
      checkInTime: record.checkIn,
      geofenceName: record.geofence?.name,
      employeeName: record.employee.name,
    });
  });

  // Build response with all employees
  const result = allEmployees.map(emp => {
    const status = attendanceMap.get(emp._id.toString());
    if (status) {
      return {
        employeeId: emp._id,
        employeeName: emp.name,
        email: emp.email,
        isCheckedIn: true,
        checkInTime: status.checkInTime,
        geofenceName: status.geofenceName,
      };
    }
    return {
      employeeId: emp._id,
      employeeName: emp.name,
      email: emp.email,
      isCheckedIn: false,
      checkInTime: null,
      geofenceName: null,
    };
  });

  res.json({ employees: result, timestamp: new Date() });
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
  // Find the most recent open attendance record (no date filter).
  // Using a strict "today" filter here caused missed open records
  // when timezone math drifted; show open state if there's any
  // attendance record without a checkOut for the user.
  const openRecord = await Attendance.findOne({
    employee: req.user._id,
    checkOut: { $exists: false },
  }).populate('geofence', 'name').sort({ createdAt: -1 });

  // NOTE: removed fragile debug code that referenced undefined date window variables.
  // This endpoint intentionally returns open state for any attendance record
  // without a `checkOut` for the user (no date window).

  const isCheckedIn = !!openRecord;
  let lastCheckTime = null;
  let lastGeofenceName = null;
  let lastCheckTimestamp = null;

  // Helper function to format time as HH:MM AM/PM in Asia/Manila (UTC+8)
  // without mutating stored timestamps (we store dates in UTC in MongoDB).
  const _manilaTimeFormatter = new Intl.DateTimeFormat('en-US', {
    timeZone: 'Asia/Manila',
    hour: '2-digit',
    minute: '2-digit',
    hour12: true,
  });

  const formatTime = (date) => {
    if (!date) return null;
    return _manilaTimeFormatter.format(new Date(date));
  };

  if (openRecord) {
    lastCheckTime = formatTime(openRecord.checkIn);
    lastGeofenceName = openRecord.geofence?.name;
    lastCheckTimestamp = openRecord.checkIn;
  } else {
    // Get last check-out time (most recent record regardless of date)
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
    .populate('employee', 'name email')
    .sort({ checkIn: -1 })
    .limit(100); // Limit to last 100 records

  const records = attendance.map(record => {
    const elapsedMs = record.checkOut ? (record.checkOut - record.checkIn) : 0;
    const elapsedHours = (elapsedMs / (1000 * 60 * 60)).toFixed(2);
    
    return {
      id: record._id,
      isCheckIn: record.status === 'in',
      checkInTime: record.checkIn,
      checkOutTime: record.checkOut,
      elapsedHours: record.checkOut ? parseFloat(elapsedHours) : null,
      status: record.status, // 'in' (open) or 'out' (closed)
      latitude: record.location?.lat,
      longitude: record.location?.lng,
      geofenceId: record.geofence?._id,
      geofenceName: record.geofence?.name || 'Unknown Location',
      employeeName: record.employee?.name || 'Unknown Employee',
      employeeEmail: record.employee?.email,
      userId: record.employee?._id,
      isVoid: record.isVoid || false,
      autoCheckout: record.autoCheckout || false,
      voidReason: record.voidReason,
    };
  });

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
  archiveAttendanceRecord,
  restoreAttendanceRecord,
  getAttendanceById,
  updateAttendance,
  deleteAttendance,
  getAttendanceStatus,
  getAttendanceHistory,
  deleteMyAttendanceRecord,
  deleteMyAttendanceHistoryByMonth,
  getAllEmployeesAttendanceStatus,
};