const asyncHandler = require('express-async-handler');
const User = require('../models/User');
const Geofence = require('../models/Geofence');
const Task = require('../models/Task');
const Attendance = require('../models/Attendance');

let _statsCache = { ts: 0, data: null };
let _realtimeCache = { ts: 0, data: null };

const STATS_TTL_MS = 30 * 1000;
const REALTIME_TTL_MS = 2 * 1000;

// @desc    Get dashboard statistics
// @route   GET /api/dashboard/stats
// @access  Private/Admin
const getDashboardStats = asyncHandler(async (req, res) => {
  try {
    const now = Date.now();
    if (_statsCache.data && now - _statsCache.ts < STATS_TTL_MS) {
      return res.json(_statsCache.data);
    }

    // Get total counts (run in parallel)
    const [
      totalEmployees,
      activeEmployees,
      totalAdmins,
      totalGeofences,
      activeGeofences,
      totalTasks,
      pendingTasks,
      completedTasks,
    ] = await Promise.all([
      User.countDocuments({ role: 'employee' }),
      User.countDocuments({ role: 'employee', isActive: true }),
      User.countDocuments({ role: 'admin' }),
      Geofence.countDocuments(),
      Geofence.countDocuments({ isActive: true }),
      Task.countDocuments(),
      Task.countDocuments({ status: 'pending' }),
      Task.countDocuments({ status: 'completed' }),
    ]);
    
    // Get today's attendance
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const tomorrow = new Date(today);
    tomorrow.setDate(tomorrow.getDate() + 1);
    
    const [todayAttendance, todayCheckIns, todayCheckOuts] = await Promise.all([
      Attendance.countDocuments({ createdAt: { $gte: today, $lt: tomorrow } }),
      Attendance.countDocuments({ checkIn: { $gte: today, $lt: tomorrow } }),
      Attendance.countDocuments({ checkOut: { $gte: today, $lt: tomorrow } }),
    ]);
    
    // Get recent activities (last 7 days)
    const sevenDaysAgo = new Date();
    sevenDaysAgo.setDate(sevenDaysAgo.getDate() - 7);
    
    const [recentAttendancesRaw, recentTasks] = await Promise.all([
      Attendance.find({ checkIn: { $gte: sevenDaysAgo } })
        .populate('employee', 'name email')
        .populate('geofence', 'name')
        .sort({ checkIn: -1 })
        .limit(10)
        .lean(),
      Task.find({ createdAt: { $gte: sevenDaysAgo } })
        .sort({ createdAt: -1 })
        .limit(10)
        .lean(),
    ]);

    // Normalize to expected shape with 'user' key for frontend model
    const recentAttendances = recentAttendancesRaw.map(a => ({
      ...a,
      user: a.employee,
      timestamp: a.checkIn,
    }));
    
    // Get attendance trends (last 7 days) using a single aggregation
    const start = new Date();
    start.setDate(start.getDate() - 6);
    start.setHours(0, 0, 0, 0);

    const trendRows = await Attendance.aggregate([
      { $match: { checkIn: { $gte: start } } },
      {
        $group: {
          _id: {
            $dateToString: { format: '%Y-%m-%d', date: '$checkIn' },
          },
          count: { $sum: 1 },
        },
      },
      { $sort: { _id: 1 } },
    ]);

    const trendMap = new Map(trendRows.map(r => [r._id, r.count]));
    const attendanceTrends = [];
    for (let i = 6; i >= 0; i--) {
      const date = new Date();
      date.setDate(date.getDate() - i);
      date.setHours(0, 0, 0, 0);
      const key = date.toISOString().split('T')[0];
      attendanceTrends.push({ date: key, count: trendMap.get(key) || 0 });
    }
    
    const payload = {
      users: {
        totalEmployees,
        activeEmployees,
        totalAdmins,
        inactiveEmployees: totalEmployees - activeEmployees
      },
      geofences: {
        total: totalGeofences,
        active: activeGeofences,
        inactive: totalGeofences - activeGeofences
      },
      tasks: {
        total: totalTasks,
        pending: pendingTasks,
        completed: completedTasks,
        inProgress: totalTasks - pendingTasks - completedTasks
      },
      attendance: {
        today: todayAttendance,
        todayCheckIns,
        todayCheckOuts,
        trends: attendanceTrends
      },
      recentActivities: {
        attendances: recentAttendances,
        tasks: recentTasks
      }

    };

    _statsCache = { ts: Date.now(), data: payload };
    res.json(payload);
  } catch (error) {
    console.error('Error fetching dashboard stats:', error);
    res.status(500).json({ message: 'Error fetching dashboard statistics' });
  }
});

// @desc    Get real-time updates
// @route   GET /api/dashboard/realtime
// @access  Private/Admin
const getRealtimeUpdates = asyncHandler(async (req, res) => {
  try {
    const now = Date.now();
    if (_realtimeCache.data && now - _realtimeCache.ts < REALTIME_TTL_MS) {
      return res.json(_realtimeCache.data);
    }

    // Only treat employees as "online" if they are marked online AND
    // have a recent location update (last 5 minutes).
    const fiveMinutesAgo = new Date(Date.now() - 5 * 60 * 1000);

    const onlineUsers = await User.countDocuments({
      role: 'employee',
      isOnline: true,
      lastLocationUpdate: { $gte: fiveMinutesAgo },
    });
    
    // Get recent check-ins (last 5 minutes)
    const recentCheckInsRaw = await Attendance.find({
      checkIn: { $gte: fiveMinutesAgo }
    }).populate('employee', 'name email').populate('geofence', 'name').sort({ checkIn: -1 }).limit(25).lean();

    const recentCheckIns = recentCheckInsRaw.map(a => ({
      ...a,
      user: a.employee,
      timestamp: a.checkIn,
    }));
    
    // Get pending tasks assigned today
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const pendingTasksToday = await Task.find({
      status: 'pending',
      createdAt: { $gte: today }
    }).sort({ createdAt: -1 }).limit(25).lean();
    
    const payload = {
      onlineUsers,
      recentCheckIns,
      pendingTasksToday,
      timestamp: new Date()

    };

    _realtimeCache = { ts: Date.now(), data: payload };
    res.json(payload);
  } catch (error) {
    console.error('Error fetching realtime updates:', error);
    res.status(500).json({ message: 'Error fetching realtime updates' });
  }
});

module.exports = {
  getDashboardStats,
  getRealtimeUpdates,
};
