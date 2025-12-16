const User = require('../models/User');
const Attendance = require('../models/Attendance');
const Geofence = require('../models/Geofence');
const Report = require('../models/Report');

/**
 * Offline Employee Void Job
 * Automatically voids attendance records for employees who:
 * 1. Are offline for too long (> 30 minutes without location update)
 * 2. Are outside their geofence boundary
 * 3. Have an active check-in (no checkout yet)
 */

const OFFLINE_THRESHOLD_MINUTES = 30; // Mark as void if offline for 30+ minutes
const CHECK_INTERVAL_MINUTES = 5; // Run job every 5 minutes

let jobInterval = null;

/**
 * Initialize the offline employee void job
 */
function initializeOfflineEmployeeVoidJob() {
  console.log('🔄 Initializing offline employee void attendance job...');

  // Run immediately on startup
  voidOfflineEmployeesOutsideGeofence();

  // Schedule recurring job
  jobInterval = setInterval(voidOfflineEmployeesOutsideGeofence, CHECK_INTERVAL_MINUTES * 60 * 1000);

  console.log(`✅ Offline employee void job initialized (runs every ${CHECK_INTERVAL_MINUTES} minutes)`);
}

/**
 * Check for offline employees outside geofence and void their attendance
 */
async function voidOfflineEmployeesOutsideGeofence() {
  try {
    const now = new Date();
    const offlineThreshold = new Date(now.getTime() - OFFLINE_THRESHOLD_MINUTES * 60 * 1000);

    // Find all employees with active check-ins (no checkout)
    const activeAttendances = await Attendance.find({
      checkOut: { $exists: false },
    })
      .populate('employee', '_id name lastLatitude lastLongitude lastLocationUpdate')
      .populate('geofence', '_id name latitude longitude radius');

    console.log(`📊 Checking ${activeAttendances.length} active attendance records...`);

    for (const attendance of activeAttendances) {
      try {
        const employee = attendance.employee;
        const geofence = attendance.geofence;

        if (!employee || !geofence) {
          console.warn(`⚠️ Skipping attendance ${attendance._id}: missing employee or geofence`);
          continue;
        }

        // Check if employee is offline
        const lastUpdate = employee.lastLocationUpdate ? new Date(employee.lastLocationUpdate) : null;
        const isOffline = !lastUpdate || lastUpdate < offlineThreshold;

        if (!isOffline) {
          continue; // Employee is online, skip
        }

        // Check if employee is outside geofence boundary
        const lastLat = employee.lastLatitude;
        const lastLng = employee.lastLongitude;

        if (lastLat === undefined || lastLng === undefined || lastLat === null || lastLng === null) {
          console.warn(`⚠️ Skipping ${employee.name}: no last known location`);
          continue;
        }

        const distanceMeters = calculateDistance(
          geofence.latitude,
          geofence.longitude,
          lastLat,
          lastLng
        );

        const isOutsideGeofence = distanceMeters > geofence.radius;

        if (!isOutsideGeofence) {
          continue; // Employee is inside geofence, skip
        }

        // Employee is offline AND outside geofence - void their attendance
        console.log(
          `🔴 Voiding attendance for ${employee.name}: offline for ${Math.round((now - lastUpdate) / 60000)} min, ${Math.round(distanceMeters)}m outside ${geofence.name}`
        );

        // Mark attendance as void
        attendance.checkOut = now;
        attendance.status = 'out';
        attendance.isVoid = true;
        attendance.voidReason = `Auto-void: Offline for ${OFFLINE_THRESHOLD_MINUTES}+ minutes and ${Math.round(distanceMeters)}m outside geofence`;
        await attendance.save();

        // Create void attendance report
        try {
          const report = await Report.create({
            type: 'attendance',
            attendance: attendance._id,
            employee: employee._id,
            geofence: geofence._id,
            content: `Auto-void: Employee offline for ${OFFLINE_THRESHOLD_MINUTES}+ minutes and outside geofence boundary`,
          });

          if (global.io) {
            global.io.emit('newReport', report);
          }
        } catch (e) {
          console.error('Failed to create void attendance report:', e);
        }

        // Emit auto-checkout event
        if (global.io) {
          global.io.emit('employeeAutoCheckout', {
            employeeId: employee._id,
            employeeName: employee.name,
            geofenceName: geofence.name,
            reason: `Offline for ${OFFLINE_THRESHOLD_MINUTES}+ minutes and outside geofence`,
            checkOutTime: now,
            isVoid: true,
          });
        }
      } catch (e) {
        console.error('Error processing attendance record:', e);
      }
    }
  } catch (e) {
    console.error('❌ Error in offline employee void job:', e);
  }
}

/**
 * Calculate distance between two coordinates using Haversine formula
 */
function calculateDistance(lat1, lon1, lat2, lon2) {
  const toRad = (deg) => (deg * Math.PI) / 180;
  const R = 6371000; // Earth radius in meters

  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);

  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) * Math.sin(dLon / 2);

  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));

  return R * c;
}

/**
 * Stop the job
 */
function stopOfflineEmployeeVoidJob() {
  if (jobInterval) {
    clearInterval(jobInterval);
    jobInterval = null;
    console.log('⏹️ Offline employee void job stopped');
  }
}

module.exports = {
  initializeOfflineEmployeeVoidJob,
  stopOfflineEmployeeVoidJob,
  voidOfflineEmployeesOutsideGeofence,
};
