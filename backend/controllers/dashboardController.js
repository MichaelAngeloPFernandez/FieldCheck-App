const asyncHandler = require('express-async-handler');
const User = require('../models/User');
const Geofence = require('../models/Geofence');
const Task = require('../models/Task');
const Attendance = require('../models/Attendance');

// @desc    Get dashboard statistics
// @route   GET /api/dashboard/stats
// @access  Private/Admin
const getDashboardStats = asyncHandler(async (req, res) => {
  try {
    // Get total counts
    const totalEmployees = await User.countDocuments({ role: 'employee' });
    const activeEmployees = await User.countDocuments({ role: 'employee', isActive: true });
    const totalAdmins = await User.countDocuments({ role: 'admin' });
    const totalGeofences = await Geofence.countDocuments();
    const activeGeofences = await Geofence.countDocuments({ isActive: true });
    const totalTasks = await Task.countDocuments();
    const pendingTasks = await Task.countDocuments({ status: 'pending' });
    const completedTasks = await Task.countDocuments({ status: 'completed' });
    
    // Get today's attendance
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const tomorrow = new Date(today);
    tomorrow.setDate(tomorrow.getDate() + 1);
    
    const todayAttendance = await Attendance.countDocuments({
      createdAt: { $gte: today, $lt: tomorrow }
    });
    
    const todayCheckIns = await Attendance.countDocuments({
      checkIn: { $gte: today, $lt: tomorrow }
    });
    
    const todayCheckOuts = await Attendance.countDocuments({
      checkOut: { $gte: today, $lt: tomorrow }
    });
    
    // Get recent activities (last 7 days)
    const sevenDaysAgo = new Date();
    sevenDaysAgo.setDate(sevenDaysAgo.getDate() - 7);
    
    const recentAttendancesRaw = await Attendance.find({
      checkIn: { $gte: sevenDaysAgo }
    }).populate('employee', 'name email').populate('geofence', 'name').sort({ checkIn: -1 }).limit(10).lean();

    // Normalize to expected shape with 'user' key for frontend model
    const recentAttendances = recentAttendancesRaw.map(a => ({
      ...a,
      user: a.employee,
      timestamp: a.checkIn,
    }));
    
    const recentTasks = await Task.find({
      createdAt: { $gte: sevenDaysAgo }
    }).sort({ createdAt: -1 }).limit(10).lean();
    
    // Get attendance trends (last 7 days)
    const attendanceTrends = [];
    for (let i = 6; i >= 0; i--) {
      const date = new Date();
      date.setDate(date.getDate() - i);
      date.setHours(0, 0, 0, 0);
      const nextDate = new Date(date);
      nextDate.setDate(nextDate.getDate() + 1);
      
      const dayAttendance = await Attendance.countDocuments({
        checkIn: { $gte: date, $lt: nextDate }
      });
      
      attendanceTrends.push({
        date: date.toISOString().split('T')[0],
        count: dayAttendance
      });
    }
    
    res.json({
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
    });
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
    // True current online employees based on User.isOnline flag
    const onlineUsers = await User.countDocuments({
      role: 'employee',
      isOnline: true,
    });
    
    // Get recent check-ins (last 5 minutes)
    const fiveMinutesAgo = new Date(Date.now() - 5 * 60 * 1000);
    const recentCheckInsRaw = await Attendance.find({
      checkIn: { $gte: fiveMinutesAgo }
    }).populate('employee', 'name email').populate('geofence', 'name').sort({ checkIn: -1 }).lean();

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
    }).sort({ createdAt: -1 }).lean();
    
    res.json({
      onlineUsers,
      recentCheckIns,
      pendingTasksToday,
      timestamp: new Date()
    });
  } catch (error) {
    console.error('Error fetching realtime updates:', error);
    res.status(500).json({ message: 'Error fetching realtime updates' });
  }
});

module.exports = {
  getDashboardStats,
  getRealtimeUpdates,
};
