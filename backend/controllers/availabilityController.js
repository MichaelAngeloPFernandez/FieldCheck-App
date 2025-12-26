const asyncHandler = require('express-async-handler');
const mongoose = require('mongoose');
const User = require('../models/User');
const Geofence = require('../models/Geofence');
const Task = require('../models/Task');
const UserTask = require('../models/UserTask');
const { employeeLocations } = require('../server');

function toRad(deg) {
  return (deg * Math.PI) / 180;
}

function haversineMeters(lat1, lon1, lat2, lon2) {
  const R = 6371000;
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRad(lat1)) *
      Math.cos(toRad(lat2)) *
      Math.sin(dLon / 2) *
      Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

function workloadStatus(activeTasksCount, overdueTasksCount) {
  if (activeTasksCount <= 0 && overdueTasksCount <= 0) return 'available';
  if (overdueTasksCount > 0 || activeTasksCount >= 4) return 'overloaded';
  return 'busy';
}

async function buildAvailabilityForPoint(lat, lng, maxDistanceMeters, roles) {
  const now = new Date();
  const candidates = [];

  employeeLocations.forEach((loc, userId) => {
    if (typeof userId !== 'string') return;
    if (userId.length !== 24 || !mongoose.isValidObjectId(userId)) return;
    if (typeof loc?.lat !== 'number' || typeof loc?.lng !== 'number') return;
    const distance = haversineMeters(lat, lng, loc.lat, loc.lng);
    if (distance <= maxDistanceMeters) {
      candidates.push({
        userId,
        distanceMeters: distance,
        lastLocation: {
          latitude: loc.lat,
          longitude: loc.lng,
          accuracy: loc.accuracy,
          timestamp: loc.timestamp ? new Date(loc.timestamp) : now,
        },
      });
    }
  });

  if (!candidates.length) {
    return [];
  }

  const userIds = candidates.map((c) => c.userId);

  const userQuery = {
    _id: { $in: userIds },
    isActive: true,
  };
  if (Array.isArray(roles) && roles.length > 0) {
    userQuery.role = { $in: roles };
  }

  const users = await User.find(userQuery).select('name email phone role');
  if (!users.length) {
    return [];
  }

  const userMap = new Map(users.map((u) => [u._id.toString(), u]));

  const assignments = await UserTask.find({
    userId: { $in: users.map((u) => u._id) },
    status: { $ne: 'completed' },
  });

  const taskIds = assignments.map((a) => a.taskId);
  const tasks = taskIds.length
    ? await Task.find({ _id: { $in: taskIds }, isArchived: { $ne: true } }).select(
        'dueDate status'
      )
    : [];

  const taskMap = new Map(tasks.map((t) => [t._id.toString(), t]));

  const assignmentsByUser = new Map();
  for (const a of assignments) {
    const key = a.userId.toString();
    if (!assignmentsByUser.has(key)) assignmentsByUser.set(key, []);
    assignmentsByUser.get(key).push(a);
  }

  const result = [];

  for (const c of candidates) {
    const user = userMap.get(c.userId);
    if (!user) continue;

    const userAssignments = assignmentsByUser.get(c.userId) || [];
    let activeTasksCount = 0;
    let overdueTasksCount = 0;

    for (const a of userAssignments) {
      const t = taskMap.get(a.taskId.toString());
      if (!t) continue;
      activeTasksCount += 1;
      if (t.dueDate && t.dueDate < now && t.status !== 'completed') {
        overdueTasksCount += 1;
      }
    }

    result.push({
      userId: c.userId,
      name: user.name,
      email: user.email,
      phone: user.phone,
      role: user.role,
      distanceMeters: c.distanceMeters,
      lastLocation: c.lastLocation,
      activeTasksCount,
      overdueTasksCount,
      workloadStatus: workloadStatus(activeTasksCount, overdueTasksCount),
    });
  }

  result.sort((a, b) => a.distanceMeters - b.distanceMeters);
  return result;
}

async function buildAvailabilityForOnlineEmployees(roles) {
  const now = new Date();
  const candidates = [];

  employeeLocations.forEach((loc, userId) => {
    if (typeof userId !== 'string') return;
    if (userId.length !== 24 || !mongoose.isValidObjectId(userId)) return;
    if (typeof loc?.lat !== 'number' || typeof loc?.lng !== 'number') return;
    candidates.push({
      userId,
      lastLocation: {
        latitude: loc.lat,
        longitude: loc.lng,
        accuracy: loc.accuracy,
        timestamp: loc.timestamp ? new Date(loc.timestamp) : now,
      },
    });
  });

  if (!candidates.length) {
    return [];
  }

  const userIds = candidates.map((c) => c.userId);

  const userQuery = {
    _id: { $in: userIds },
    isActive: true,
  };
  if (Array.isArray(roles) && roles.length > 0) {
    userQuery.role = { $in: roles };
  }

  const users = await User.find(userQuery).select('name email phone role');
  if (!users.length) {
    return [];
  }

  const userMap = new Map(users.map((u) => [u._id.toString(), u]));

  const assignments = await UserTask.find({
    userId: { $in: users.map((u) => u._id) },
    status: { $ne: 'completed' },
  });

  const taskIds = assignments.map((a) => a.taskId);
  const tasks = taskIds.length
    ? await Task.find({ _id: { $in: taskIds }, isArchived: { $ne: true } }).select(
        'dueDate status'
      )
    : [];

  const taskMap = new Map(tasks.map((t) => [t._id.toString(), t]));

  const assignmentsByUser = new Map();
  for (const a of assignments) {
    const key = a.userId.toString();
    if (!assignmentsByUser.has(key)) assignmentsByUser.set(key, []);
    assignmentsByUser.get(key).push(a);
  }

  const result = [];

  for (const c of candidates) {
    const user = userMap.get(c.userId);
    if (!user) continue;

    const userAssignments = assignmentsByUser.get(c.userId) || [];
    let activeTasksCount = 0;
    let overdueTasksCount = 0;

    for (const a of userAssignments) {
      const t = taskMap.get(a.taskId.toString());
      if (!t) continue;
      activeTasksCount += 1;
      if (t.dueDate && t.dueDate < now && t.status !== 'completed') {
        overdueTasksCount += 1;
      }
    }

    result.push({
      userId: c.userId,
      name: user.name,
      email: user.email,
      phone: user.phone,
      role: user.role,
      lastLocation: c.lastLocation,
      activeTasksCount,
      overdueTasksCount,
      workloadStatus: workloadStatus(activeTasksCount, overdueTasksCount),
    });
  }

  return result;
}

// @route   GET /api/availability/online
// @access  Private/Admin
const getOnlineEmployeesAvailability = asyncHandler(async (req, res) => {
  const employees = await buildAvailabilityForOnlineEmployees(['employee']);
  res.json({ employees });
});

// @route   GET /api/availability/geofence/:geofenceId
// @access  Private/Admin
const getNearbyEmployeesForGeofence = asyncHandler(async (req, res) => {
  const { geofenceId } = req.params;
  const maxDistanceMeters = Number(req.query.maxDistanceMeters) || 2000;

  const geofence = await Geofence.findById(geofenceId);
  if (!geofence) {
    res.status(404);
    throw new Error('Geofence not found');
  }

  const employees = await buildAvailabilityForPoint(
    geofence.latitude,
    geofence.longitude,
    maxDistanceMeters,
    ['employee']
  );

  res.json({
    geofenceId,
    center: {
      latitude: geofence.latitude,
      longitude: geofence.longitude,
      radius: geofence.radius,
    },
    maxDistanceMeters,
    employees,
  });
});

// @route   GET /api/availability/task/:taskId
// @access  Private/Admin
const getNearbyEmployeesForTask = asyncHandler(async (req, res) => {
  const { taskId } = req.params;
  const maxDistanceMeters = Number(req.query.maxDistanceMeters) || 2000;

  const task = await Task.findById(taskId).populate('geofenceId');
  if (!task) {
    res.status(404);
    throw new Error('Task not found');
  }

  let lat = null;
  let lng = null;

  if (task.geofenceId && task.geofenceId.latitude && task.geofenceId.longitude) {
    lat = task.geofenceId.latitude;
    lng = task.geofenceId.longitude;
  } else if (typeof task.latitude === 'number' && typeof task.longitude === 'number') {
    lat = task.latitude;
    lng = task.longitude;
  }

  if (lat === null || lng === null) {
    res.status(400);
    throw new Error('Task has no geolocation or linked geofence');
  }

  const employees = await buildAvailabilityForPoint(lat, lng, maxDistanceMeters, ['employee']);

  res.json({
    taskId,
    center: {
      latitude: lat,
      longitude: lng,
    },
    maxDistanceMeters,
    employees,
  });
});

module.exports = {
  getOnlineEmployeesAvailability,
  getNearbyEmployeesForGeofence,
  getNearbyEmployeesForTask,
};
