const mongoose = require('mongoose');
const dotenv = require('dotenv');
const Attendance = require('../models/Attendance');
const User = require('../models/User');

dotenv.config();

const MONGO = process.env.MONGO_URI || process.env.MONGO || 'mongodb://localhost:27017/fieldcheck';

async function run() {
  console.log('Cleanup: connecting to', MONGO);
  await mongoose.connect(MONGO, { useNewUrlParser: true, useUnifiedTopology: true });

  // Threshold hours (records older than this will be closed)
  const thresholdHours = Number(process.env.CLEANUP_THRESHOLD_HOURS) || 24; // default 24h
  const cutoff = new Date(Date.now() - thresholdHours * 60 * 60 * 1000);

  console.log(`Cleanup: closing open attendance records with checkIn <= ${cutoff.toISOString()}`);

  const openRecords = await Attendance.find({ checkOut: { $exists: false }, checkIn: { $lte: cutoff } });

  console.log(`Found ${openRecords.length} open record(s) to close`);

  let closed = 0;

  for (const rec of openRecords) {
    try {
      rec.checkOut = new Date();
      rec.status = 'out';
      rec.autoCheckout = true;
      rec.voidReason = `Auto-closed by cleanup script (threshold ${thresholdHours}h)`;
      await rec.save();

      // Emit socket events if socket.io is available (when script run from server folder, global.io might exist)
      try {
        const io = global.io || (require('../server').io);
        if (io && io.emit) {
          io.emit('updatedAttendanceRecord', rec);
          io.emit('adminNotification', {
            type: 'attendance',
            action: 'auto-checkout',
            employeeId: rec.employee,
            employeeName: rec.employee?.name || null,
            geofenceName: rec.geofence || null,
            timestamp: rec.checkOut,
            message: `Auto-closed attendance ${rec._id}`,
            severity: 'warning',
          });
        }
      } catch (e) {
        // ignore socket errors when running standalone
      }

      closed++;
    } catch (e) {
      console.error('Failed closing record', rec._id, e.message || e);
    }
  }

  console.log(`Cleanup complete. Closed ${closed} record(s).`);
  await mongoose.disconnect();
  process.exit(0);
}

run().catch((e) => {
  console.error('Cleanup failed:', e);
  process.exit(1);
});
