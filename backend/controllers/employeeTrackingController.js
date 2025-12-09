const asyncHandler = require('express-async-handler');
const User = require('../models/User');
const Task = require('../models/Task');
const EmployeeLocation = require('../models/EmployeeLocation');

// @desc Get nearby employees within radius
// @route GET /api/employee-tracking/nearby?latitude=X&longitude=Y&radius=Z
// @access Private/Admin
const getNearbyEmployees = asyncHandler(async (req, res) => {
  const { latitude, longitude, radius = 5000 } = req.query;

  if (!latitude || !longitude) {
    res.status(400);
    throw new Error('latitude and longitude are required');
  }

  const lat = parseFloat(latitude);
  const lng = parseFloat(longitude);
  const rad = parseFloat(radius);

  // Get all active employees with location data
  const employees = await User.find({
    role: 'employee',
    isActive: true,
    lastLatitude: { $exists: true, $ne: null },
    lastLongitude: { $exists: true, $ne: null },
  }).select('name email phone lastLatitude lastLongitude activeTaskCount workloadWeight isOnline');

  // Calculate distances and filter
  const nearby = employees
    .map((emp) => {
      const distance = calculateDistance(lat, lng, emp.lastLatitude, emp.lastLongitude);
      return {
        ...emp.toObject(),
        distance,
      };
    })
    .filter((emp) => emp.distance <= rad)
    .sort((a, b) => a.distance - b.distance);

  res.status(200).json({
    count: nearby.length,
    employees: nearby,
  });
});

// @desc Get employee workload
// @route GET /api/employee-tracking/workload/:employeeId
// @access Private/Admin
const getEmployeeWorkload = asyncHandler(async (req, res) => {
  const { employeeId } = req.params;

  const employee = await User.findById(employeeId).select(
    'name activeTaskCount workloadWeight'
  );

  if (!employee) {
    res.status(404);
    throw new Error('Employee not found');
  }

  // Get tasks
  const tasks = await Task.find({
    assignedTo: employeeId,
    status: { $ne: 'completed' },
  }).select('title difficulty status dueDate');

  const now = new Date();
  const overdueTasks = tasks.filter((t) => t.dueDate && t.dueDate < now);

  res.status(200).json({
    employee: {
      id: employee._id,
      name: employee.name,
      activeTaskCount: employee.activeTaskCount || 0,
      workloadWeight: employee.workloadWeight || 0,
    },
    tasks: {
      total: tasks.length,
      overdue: overdueTasks.length,
      byDifficulty: tasks.reduce((acc, t) => {
        acc[t.difficulty || 'medium'] = (acc[t.difficulty || 'medium'] || 0) + 1;
        return acc;
      }, {}),
    },
  });
});

// @desc Get employee availability
// @route GET /api/employee-tracking/availability/:employeeId
// @access Private/Admin
const getEmployeeAvailability = asyncHandler(async (req, res) => {
  const { employeeId } = req.params;

  const employee = await User.findById(employeeId).select(
    'name isOnline activeTaskCount workloadWeight'
  );

  if (!employee) {
    res.status(404);
    throw new Error('Employee not found');
  }

  // Determine availability status
  let status = 'available';
  if (!employee.isOnline) {
    status = 'offline';
  } else if ((employee.workloadWeight || 0) > 10) {
    status = 'overloaded';
  } else if ((employee.activeTaskCount || 0) > 5) {
    status = 'busy';
  } else if ((employee.activeTaskCount || 0) === 0) {
    status = 'free';
  }

  res.status(200).json({
    employee: {
      id: employee._id,
      name: employee.name,
      status,
      isOnline: employee.isOnline,
      activeTaskCount: employee.activeTaskCount || 0,
      workloadWeight: employee.workloadWeight || 0,
    },
  });
});

// @desc Update employee location
// @route POST /api/employee-tracking/location
// @access Private
const updateEmployeeLocation = asyncHandler(async (req, res) => {
  const { latitude, longitude, accuracy } = req.body;
  const userId = req.user.id;

  if (latitude === undefined || longitude === undefined) {
    res.status(400);
    throw new Error('latitude and longitude are required');
  }

  // Update user location
  const user = await User.findByIdAndUpdate(
    userId,
    {
      lastLatitude: latitude,
      lastLongitude: longitude,
      lastLocationUpdate: new Date(),
      isOnline: true,
    },
    { new: true }
  );

  // Store location history
  await EmployeeLocation.create({
    user: userId,
    latitude,
    longitude,
    accuracy: accuracy || 0,
    timestamp: new Date(),
  });

  res.status(200).json({
    message: 'Location updated',
    location: {
      latitude: user.lastLatitude,
      longitude: user.lastLongitude,
      timestamp: user.lastLocationUpdate,
    },
  });
});

// @desc Get employee statistics
// @route GET /api/employee-tracking/stats/:employeeId
// @access Private/Admin
const getEmployeeStats = asyncHandler(async (req, res) => {
  const { employeeId } = req.params;

  const employee = await User.findById(employeeId);
  if (!employee) {
    res.status(404);
    throw new Error('Employee not found');
  }

  // Get task statistics
  const allTasks = await Task.find({ assignedTo: employeeId });
  const completedTasks = allTasks.filter((t) => t.status === 'completed');
  const activeTasks = allTasks.filter((t) => t.status !== 'completed');

  const now = new Date();
  const overdueTasks = activeTasks.filter((t) => t.dueDate && t.dueDate < now);

  res.status(200).json({
    employee: {
      id: employee._id,
      name: employee.name,
      email: employee.email,
      role: employee.role,
    },
    statistics: {
      totalTasks: allTasks.length,
      completedTasks: completedTasks.length,
      activeTasks: activeTasks.length,
      overdueTasks: overdueTasks.length,
      completionRate:
        allTasks.length > 0
          ? ((completedTasks.length / allTasks.length) * 100).toFixed(2)
          : 0,
      workloadWeight: employee.workloadWeight || 0,
      activeTaskCount: employee.activeTaskCount || 0,
      isOnline: employee.isOnline || false,
      lastLocationUpdate: employee.lastLocationUpdate,
    },
  });
});

// @desc Get overdue tasks for employee
// @route GET /api/employee-tracking/overdue/:employeeId
// @access Private/Admin
const getOverdueTasksForEmployee = asyncHandler(async (req, res) => {
  const { employeeId } = req.params;

  const employee = await User.findById(employeeId);
  if (!employee) {
    res.status(404);
    throw new Error('Employee not found');
  }

  const now = new Date();
  const overdueTasks = await Task.find({
    assignedTo: employeeId,
    dueDate: { $lt: now },
    status: { $ne: 'completed' },
  }).select('title description difficulty dueDate status createdAt');

  res.status(200).json({
    employee: {
      id: employee._id,
      name: employee.name,
    },
    overdueTasks: overdueTasks.map((t) => ({
      id: t._id,
      title: t.title,
      description: t.description,
      difficulty: t.difficulty,
      dueDate: t.dueDate,
      hoursOverdue: Math.floor((now - t.dueDate) / (1000 * 60 * 60)),
      status: t.status,
    })),
    totalOverdue: overdueTasks.length,
  });
});

// Helper function to calculate distance between two coordinates
function calculateDistance(lat1, lon1, lat2, lon2) {
  const R = 6371000; // Earth's radius in meters
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

function toRad(degrees) {
  return (degrees * Math.PI) / 180;
}

module.exports = {
  getNearbyEmployees,
  getEmployeeWorkload,
  getEmployeeAvailability,
  updateEmployeeLocation,
  getEmployeeStats,
  getOverdueTasksForEmployee,
};
