const User = require('../models/User');
const Attendance = require('../models/Attendance');
const Task = require('../models/Task');
const Geofence = require('../models/Geofence');

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
    let status = 'available';
    if (speed && speed > 0.5) {
      status = 'moving'; // Employee is moving
    }

    // Check for active tasks
    const activeTasks = await Task.find({
      assignedTo: employeeId,
      status: { $in: ['assigned', 'in_progress'] },
    });

    if (activeTasks.length > 0) {
      status = 'busy';
    }

    // Calculate workload score
    const workloadScore = Math.min(activeTasks.length / 5, 1.0); // Max 5 tasks = 100%

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
      activeTaskCount: activeTasks.length,
      workloadScore,
      currentGeofence: currentGeofence?.name || null,
      distanceToNearestTask: null,
      isOnline: true,
      batteryLevel: req.body.batteryLevel || null,
    };

    // Calculate distance to nearest task
    if (activeTasks.length > 0) {
      let minDistance = Infinity;
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
 * Get all online employees with their locations
 * GET /api/location/online-employees
 */
exports.getOnlineEmployees = async (req, res) => {
  try {
    const employees = await User.find({
      isOnline: true,
      role: 'employee',
      lastLatitude: { $exists: true },
      lastLongitude: { $exists: true },
    }).select(
      'id name lastLatitude lastLongitude lastLocationUpdate activeTaskCount workloadWeight'
    );

    // Enrich with status and task info
    const enrichedEmployees = await Promise.all(
      employees.map(async (emp) => {
        const activeTasks = await Task.find({
          assignedTo: emp._id,
          status: { $in: ['assigned', 'in_progress'] },
        });

        let status = 'available';
        if (activeTasks.length > 0) {
          status = 'busy';
        }

        return {
          employeeId: emp._id,
          name: emp.name,
          latitude: emp.lastLatitude,
          longitude: emp.lastLongitude,
          status,
          activeTaskCount: activeTasks.length,
          workloadScore: Math.min(activeTasks.length / 5, 1.0),
          isOnline: true,
          timestamp: emp.lastLocationUpdate,
        };
      })
    );

    res.json({
      success: true,
      data: enrichedEmployees,
    });
  } catch (error) {
    console.error('Error fetching online employees:', error);
    res.status(500).json({ error: 'Failed to fetch online employees' });
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

    const activeTasks = await Task.find({
      assignedTo: employeeId,
      status: { $in: ['assigned', 'in_progress'] },
    });

    const location = {
      employeeId: user._id,
      name: user.name,
      latitude: user.lastLatitude,
      longitude: user.lastLongitude,
      activeTaskCount: activeTasks.length,
      workloadScore: Math.min(activeTasks.length / 5, 1.0),
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

    // Find active attendance record
    const attendance = await Attendance.findOne({
      userId: employeeId,
      checkOutTime: null,
      isVoid: false,
    });

    if (!attendance) {
      return res.status(400).json({ error: 'No active check-in found' });
    }

    // Mark attendance as void and auto-checkout
    const now = new Date();
    attendance.checkOutTime = now;
    attendance.isVoid = true;
    attendance.voidReason = reason;
    attendance.autoCheckout = true;
    await attendance.save();

    // Update user status
    await User.findByIdAndUpdate(employeeId, {
      isOnline: false,
      status: 'offline',
    });

    // Emit auto-checkout event
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

module.exports = exports;
