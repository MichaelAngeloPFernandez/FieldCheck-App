const User = require('../models/User');
const Attendance = require('../models/Attendance');
const Task = require('../models/Task');
const UserTask = require('../models/UserTask');
const Geofence = require('../models/Geofence');
const Report = require('../models/Report');

async function countActiveNonOverdueTasksForUsers(userIds) {
  const now = new Date();
  const terminalStatuses = new Set(['completed', 'reviewed', 'closed']);

  const assignments = await UserTask.find({
    userId: { $in: userIds },
    isArchived: { $ne: true },
    status: { $ne: 'completed' },
  }).select('userId taskId');

  const counts = new Map(userIds.map((id) => [id.toString(), 0]));
  if (!assignments.length) return counts;

  const taskIds = assignments.map((a) => a.taskId).filter(Boolean);
  const tasks = taskIds.length
    ? await Task.find({ _id: { $in: taskIds }, isArchived: { $ne: true } }).select(
        '_id dueDate status isArchived',
      )
    : [];

  const countableTaskIds = new Set(
    tasks
      .filter((t) => {
        const status = String(t.status || '').toLowerCase();
        if (t.isArchived) return false;
        if (terminalStatuses.has(status)) return false;
        if (t.dueDate && t.dueDate < now) return false;
        return true;
      })
      .map((t) => t._id.toString()),
  );

  for (const a of assignments) {
    const taskId = a.taskId?.toString();
    if (!taskId || !countableTaskIds.has(taskId)) continue;
    const key = a.userId.toString();
    counts.set(key, (counts.get(key) || 0) + 1);
  }

  return counts;
}

async function trimOverLimitAssignmentsForUser(userId, maxActive) {
  const now = new Date();
  const terminalStatuses = new Set(['completed', 'reviewed', 'closed']);

  const assignments = await UserTask.find({
    userId,
    isArchived: { $ne: true },
    status: { $ne: 'completed' },
  })
    .sort({ assignedAt: 1 })
    .select('_id userId taskId assignedAt isArchived status');

  if (!assignments.length) return 0;

  const taskIds = assignments.map((a) => a.taskId).filter(Boolean);
  const tasks = taskIds.length
    ? await Task.find({ _id: { $in: taskIds }, isArchived: { $ne: true } }).select(
        '_id dueDate status isArchived',
      )
    : [];

  const taskMap = new Map(tasks.map((t) => [t._id.toString(), t]));
  const countable = assignments.filter((a) => {
    const t = taskMap.get(a.taskId?.toString() || '');
    if (!t) return false;
    const status = String(t.status || '').toLowerCase();
    if (t.isArchived) return false;
    if (terminalStatuses.has(status)) return false;
    if (t.dueDate && t.dueDate < now) return false;
    return true;
  });

  if (countable.length <= maxActive) return 0;

  const toArchive = countable.slice(0, countable.length - maxActive);
  for (const ut of toArchive) {
    if (ut.isArchived) continue;
    ut.isArchived = true;
    await ut.save();

    if (global.io) {
      global.io.emit('userTaskArchived', {
        id: ut._id.toString(),
        userId: ut.userId.toString(),
        taskId: ut.taskId.toString(),
      });
      global.io.emit('taskUnassigned', {
        taskId: ut.taskId.toString(),
        userId: ut.userId.toString(),
      });
    }
  }

  return toArchive.length;
}

async function populateReportById(reportId) {
  return await Report.findById(reportId)
    .populate('employee', 'name email employeeId avatarUrl')
    .populate('task', 'title description difficulty dueDate status isArchived')
    .populate('attendance')
    .populate('geofence', 'name');
}

/**
 * Location Controller - Handles real-time employee location tracking
 */

// Store active location streams for each employee
const activeLocationStreams = new Map();

/**
 * Update employee location
 * POST /api/location/update
 */
exports.updateLocation = async (req, res) => {
  try {
    const { latitude, longitude, accuracy, speed, altitude } = req.body;
    const employeeId = req.user.id;

    // Validate coordinates
    if (!latitude || !longitude) {
      return res.status(400).json({ error: 'Latitude and longitude required' });
    }

    // Update user's last known location
    const user = await User.findByIdAndUpdate(
      employeeId,
      {
        lastLatitude: latitude,
        lastLongitude: longitude,
        lastLocationUpdate: new Date(),
        isOnline: true,
      },
      { new: true }
    );

    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    // Check if employee is in any geofence
    const geofences = await Geofence.find({ isActive: true });
    let currentGeofence = null;

    for (const geofence of geofences) {
      const distance = calculateDistance(
        latitude,
        longitude,
        geofence.latitude,
        geofence.longitude
      );

      if (distance <= geofence.radius) {
        currentGeofence = geofence;
        break;
      }
    }

    // Determine employee status based on activity
    let activeTaskCount = 0;
    try {
      const userTaskDocs = await UserTask.find({
        userId: employeeId,
        status: { $in: ['pending', 'in_progress'] },
      }).select('taskId');
      const taskIds = Array.isArray(userTaskDocs)
        ? userTaskDocs.map((d) => d.taskId).filter(Boolean)
        : [];

      if (taskIds.length > 0) {
        activeTaskCount = await Task.countDocuments({
          _id: { $in: taskIds },
          isArchived: false,
          status: { $nin: ['completed', 'closed'] },
        });
      }
    } catch (_) {
      activeTaskCount = 0;
    }

    let status = 'moving';
    if (activeTaskCount >= 1) {
      status = 'busy';
    } else if (currentGeofence) {
      status = 'available';
    }

    const workloadScore = Math.min(activeTaskCount / 5, 1.0);

    // Prepare location data
    const locationData = {
      employeeId,
      name: user.name,
      latitude,
      longitude,
      accuracy: accuracy || 0,
      speed: speed || 0,
      altitude: altitude || 0,
      status,
      timestamp: new Date().toISOString(),
      activeTaskCount,
      workloadScore,
      currentGeofence: currentGeofence?.name || null,
      distanceToNearestTask: null,
      isOnline: true,
      batteryLevel: req.body.batteryLevel || null,
    };

    // Calculate distance to nearest task
    if (activeTaskCount > 0) {
      let minDistance = Infinity;
      try {
        const userTaskDocs = await UserTask.find({
          userId: employeeId,
          status: { $in: ['pending', 'in_progress'] },
        }).select('taskId');
        const taskIds = Array.isArray(userTaskDocs)
          ? userTaskDocs.map((d) => d.taskId).filter(Boolean)
          : [];

        const activeTasks = await Task.find({
          _id: { $in: taskIds },
          isArchived: false,
          status: { $nin: ['completed', 'closed'] },
        }).select('latitude longitude');

        for (const task of activeTasks) {
          if (task.latitude && task.longitude) {
            const distance = calculateDistance(
              latitude,
              longitude,
              task.latitude,
              task.longitude
            );
            minDistance = Math.min(minDistance, distance);
          }
        }
      } catch (_) {}
      if (minDistance !== Infinity) {
        locationData.distanceToNearestTask = minDistance;
      }
    }

    // Emit real-time location update via Socket.io
    if (global.io) {
      global.io.emit('employeeLocationUpdate', locationData);
    }

    res.json({
      success: true,
      message: 'Location updated',
      data: locationData,
    });
  } catch (error) {
    console.error('Error updating location:', error);
    res.status(500).json({ error: 'Failed to update location' });
  }
};


/**
 * Get employee location history
 * GET /api/location/history/:employeeId
 */
exports.getLocationHistory = async (req, res) => {
  try {
    const { employeeId } = req.params;
    const { minutes = 20 } = req.query;

    // Get attendance records with location data from the past X minutes
    const timeAgo = new Date(Date.now() - minutes * 60 * 1000);

    const records = await Attendance.find({
      userId: employeeId,
      timestamp: { $gte: timeAgo },
      latitude: { $exists: true },
      longitude: { $exists: true },
    })
      .sort({ timestamp: -1 })
      .limit(50);

    const history = records.map((record) => ({
      latitude: record.latitude,
      longitude: record.longitude,
      accuracy: record.accuracy || 0,
      timestamp: record.timestamp,
    }));

    res.json({
      success: true,
      data: history,
    });
  } catch (error) {
    console.error('Error fetching location history:', error);
    res.status(500).json({ error: 'Failed to fetch location history' });
  }
};

/**
 * Mark employee as offline
 * POST /api/location/offline
 */
exports.markOffline = async (req, res) => {
  try {
    const employeeId = req.user.id;

    await User.findByIdAndUpdate(employeeId, {
      isOnline: false,
    });

    // Emit offline event
    if (global.io) {
      global.io.emit('employeeOffline', {
        employeeId,
        timestamp: new Date().toISOString(),
      });
    }

    res.json({ success: true, message: 'Marked as offline' });
  } catch (error) {
    console.error('Error marking offline:', error);
    res.status(500).json({ error: 'Failed to mark offline' });
  }
};

/**
 * Get employee location by ID
 * GET /api/location/:employeeId
 */
exports.getEmployeeLocation = async (req, res) => {
  try {
    const { employeeId } = req.params;

    const user = await User.findById(employeeId).select(
      'name lastLatitude lastLongitude lastLocationUpdate isOnline'
    );

    if (!user) {
      return res.status(404).json({ error: 'Employee not found' });
    }

    let activeTaskCount = 0;
    try {
      const userTaskDocs = await UserTask.find({
        userId: employeeId,
        status: { $in: ['pending', 'in_progress'] },
      }).select('taskId');
      const taskIds = Array.isArray(userTaskDocs)
        ? userTaskDocs.map((d) => d.taskId).filter(Boolean)
        : [];
      if (taskIds.length > 0) {
        activeTaskCount = await Task.countDocuments({
          _id: { $in: taskIds },
          isArchived: false,
          status: { $nin: ['completed', 'closed'] },
        });
      }
    } catch (_) {
      activeTaskCount = 0;
    }

    const location = {
      employeeId: user._id,
      name: user.name,
      latitude: user.lastLatitude,
      longitude: user.lastLongitude,
      activeTaskCount,
      workloadScore: Math.min(activeTaskCount / 5, 1.0),
      isOnline: user.isOnline,
      timestamp: user.lastLocationUpdate,
    };

    res.json({
      success: true,
      data: location,
    });
  } catch (error) {
    console.error('Error fetching employee location:', error);
    res.status(500).json({ error: 'Failed to fetch location' });
  }
};

/**
 * Update employee status (admin action)
 * POST /api/location/status/:employeeId
 */
exports.updateEmployeeStatus = async (req, res) => {
  try {
    const { employeeId } = req.params;
    const { status } = req.body;

    // Validate status
    const validStatuses = ['available', 'moving', 'busy', 'offline'];
    if (!validStatuses.includes(status)) {
      return res.status(400).json({ error: 'Invalid status' });
    }

    const user = await User.findById(employeeId);
    if (!user) {
      return res.status(404).json({ error: 'Employee not found' });
    }

    // Emit status change event
    if (global.io) {
      global.io.emit('employeeStatusChange', {
        employeeId,
        status,
        timestamp: new Date().toISOString(),
      });
    }

    res.json({
      success: true,
      message: 'Status updated',
      data: { employeeId, status },
    });
  } catch (error) {
    console.error('Error updating status:', error);
    res.status(500).json({ error: 'Failed to update status' });
  }
};

/**
 * Auto-checkout employee due to offline status
 * POST /api/location/auto-checkout/:employeeId
 */
exports.autoCheckoutEmployee = async (req, res) => {
  try {
    const { employeeId } = req.params;
    const { reason = 'Offline for extended period' } = req.body;

    const user = await User.findById(employeeId);
    if (!user) {
      return res.status(404).json({ error: 'Employee not found' });
    }

    // Find active attendance record (no checkout yet and not already voided)
    const attendance = await Attendance.findOne({
      employee: employeeId,
      checkOut: { $exists: false },
      isVoid: { $ne: true },
    });

    if (!attendance) {
      return res.status(400).json({ error: 'No active check-in found' });
    }

    // Mark attendance as void and auto-checkout
    const now = new Date();
    attendance.checkOut = now;
    attendance.status = 'out';
    attendance.isVoid = true;
    attendance.voidReason = reason;
    attendance.autoCheckout = true;
    await attendance.save();

    // Update user status
    await User.findByIdAndUpdate(employeeId, {
      isOnline: false,
      status: 'offline',
    });

    // Auto-create attendance report for auto-checkout
    try {
      const rep = await Report.create({
        type: 'attendance',
        attendance: attendance._id,
        employee: employeeId,
        geofence: attendance.geofence,
        content: 'Attendance auto-checked out and voided (offline too long)',
      });
      if (global.io) {
        try {
          const populated = await populateReportById(rep._id);
          global.io.emit('newReport', populated || rep);
        } catch (_) {
          global.io.emit('newReport', rep);
        }
      }
    } catch (e) {
      console.error('Failed to auto-create auto-checkout report:', e);
    }

    // Emit auto-checkout event for realtime notifications
    if (global.io) {
      global.io.emit('employeeAutoCheckout', {
        employeeId,
        employeeName: user.name,
        reason,
        timestamp: now.toISOString(),
        isVoid: true,
      });
    }

    console.log(`✅ Auto-checkout: ${user.name} (${employeeId}) - ${reason}`);

    res.json({
      success: true,
      message: 'Employee auto-checked out',
      data: {
        employeeId,
        checkOutTime: now,
        isVoid: true,
        reason,
      },
    });
  } catch (error) {
    console.error('Error auto-checking out employee:', error);
    res.status(500).json({ error: 'Failed to auto-checkout employee' });
  }
};

/**
 * Send auto-checkout warning to employee
 * POST /api/location/checkout-warning/:employeeId
 */
exports.sendCheckoutWarning = async (req, res) => {
  try {
    const { employeeId } = req.params;
    const { minutesRemaining = 5 } = req.body;

    const user = await User.findById(employeeId);
    if (!user) {
      return res.status(404).json({ error: 'Employee not found' });
    }

    // Emit warning event
    if (global.io) {
      global.io.emit('checkoutWarning', {
        employeeId,
        employeeName: user.name,
        minutesRemaining,
        message: `⚠️ You will be auto-checked out in ${minutesRemaining} minutes if you remain offline`,
        timestamp: new Date().toISOString(),
      });
    }

    console.log(`⚠️ Checkout warning sent to ${user.name}`);

    res.json({
      success: true,
      message: 'Warning sent',
      data: { employeeId, minutesRemaining },
    });
  } catch (error) {
    console.error('Error sending checkout warning:', error);
    res.status(500).json({ error: 'Failed to send warning' });
  }
};

/**
 * Utility function to calculate distance between two coordinates (Haversine formula)
 */
function calculateDistance(lat1, lon1, lat2, lon2) {
  const R = 6371000; // Earth's radius in meters
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLon = ((lon2 - lon1) * Math.PI) / 180;
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos((lat1 * Math.PI) / 180) *
      Math.cos((lat2 * Math.PI) / 180) *
      Math.sin(dLon / 2) *
      Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c; // Distance in meters
}

/**
 * Get all online employees with their locations
 * GET /api/location/online-employees
 */
exports.getOnlineEmployees = async (req, res) => {
  try {
    const fiveMinutesAgo = new Date(Date.now() - 5 * 60 * 1000);
    const maxActive = 3;

    const onlineUsers = await User.find({
      isOnline: true,
    }).select('_id name username email phone employeeId lastLatitude lastLongitude lastLocationUpdate isOnline activeTaskCount workloadWeight');

    await Promise.all(
      onlineUsers.map(async (u) => {
        try {
          const trimmed = await trimOverLimitAssignmentsForUser(u._id, maxActive);
          return trimmed;
        } catch (_) {
          return 0;
        }
      }),
    );

    const activeCounts = await countActiveNonOverdueTasksForUsers(
      onlineUsers.map((u) => u._id),
    );

    const locations = onlineUsers
      .filter((user) =>
        user.lastLatitude !== undefined &&
        user.lastLongitude !== undefined &&
        user.lastLatitude !== null &&
        user.lastLongitude !== null
      )
      .map((user) => ({
        userId: user._id.toString(),
        employeeId: user._id.toString(),
        employeeCode: (user.employeeId || '').toString(),
        name: user.name,
        username: user.username,
        email: user.email,
        phone: user.phone,
        latitude: user.lastLatitude,
        longitude: user.lastLongitude,
        accuracy: 0,
        timestamp: user.lastLocationUpdate?.toISOString() || new Date().toISOString(),
        isOnline: user.isOnline,
        isStale: !!(user.lastLocationUpdate && user.lastLocationUpdate < fiveMinutesAgo),
        activeTaskCount: activeCounts.get(user._id.toString()) || 0,
        workloadScore: user.workloadWeight || 0,
      }));

    res.json(locations);
  } catch (error) {
    console.error('Error fetching online employees:', error);
    res.status(500).json({ error: 'Failed to fetch online employees' });
  }
};

module.exports = exports;
