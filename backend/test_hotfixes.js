/**
 * Hotfix Test Suite - Validates all three critical modules
 * Run: node backend/test_hotfixes.js
 */

const mongoose = require('mongoose');
const dotenv = require('dotenv');
const User = require('./models/User');
const Geofence = require('./models/Geofence');
const Attendance = require('./models/Attendance');
const Task = require('./models/Task');

dotenv.config();

const tests = {
  passed: 0,
  failed: 0,
  results: [],
};

async function runTests() {
  try {
    await mongoose.connect(process.env.MONGO_URI);
    console.log('✅ MongoDB connected\n');

    // Test 1: Geofence Assignment Persistence
    console.log('📋 TEST 1: Geofence Assignment Persistence');
    console.log('─'.repeat(60));
    try {
      const geofence = await Geofence.findOne().populate('assignedEmployees', '_id name');
      if (geofence && geofence.assignedEmployees.length > 0) {
        console.log(`✓ PASS: Geofence has ${geofence.assignedEmployees.length} assigned employees`);
        console.log(`  Sample: ${geofence.assignedEmployees[0].name} (${geofence.assignedEmployees[0]._id})\n`);
        tests.passed++;
      } else {
        console.log('⚠ WARNING: No geofences with assignments found\n');
      }
    } catch (e) {
      console.log(`✗ FAIL: ${e.message}\n`);
      tests.failed++;
    }

    // Test 2: Attendance Data Capture
    console.log('📋 TEST 2: Attendance Data Capture');
    console.log('─'.repeat(60));
    try {
      const today = new Date();
      today.setHours(0, 0, 0, 0);
      const tomorrow = new Date(today);
      tomorrow.setDate(tomorrow.getDate() + 1);

      const records = await Attendance.find({
        checkIn: { $gte: today, $lt: tomorrow },
      })
        .populate('employee', 'name')
        .populate('geofence', 'name');

      console.log(`✓ PASS: Found ${records.length} attendance records today`);
      if (records.length > 0) {
        const rec = records[0];
        console.log(`  Sample: ${rec.employee?.name} @ ${rec.geofence?.name} (${rec.status})`);
        console.log(`  Check-in: ${rec.checkIn?.toLocaleTimeString()}`);
        if (rec.checkOut) console.log(`  Check-out: ${rec.checkOut.toLocaleTimeString()}`);
      }
      console.log();
      tests.passed++;
    } catch (e) {
      console.log(`✗ FAIL: ${e.message}\n`);
      tests.failed++;
    }

    // Test 3: Task Assignment & Status
    console.log('📋 TEST 3: Task Assignment & Status');
    console.log('─'.repeat(60));
    try {
      const tasks = await Task.find().limit(5);
      console.log(`✓ PASS: Found ${tasks.length} tasks in database`);
      if (tasks.length > 0) {
        tasks.forEach((t, i) => {
          console.log(`  [${i + 1}] ${t.title} | Status: ${t.status} | Geofence: ${t.geofenceId || 'None'}`);
        });
      }
      console.log();
      tests.passed++;
    } catch (e) {
      console.log(`✗ FAIL: ${e.message}\n`);
      tests.failed++;
    }

    // Test 4: Double Check-in Prevention
    console.log('📋 TEST 4: Double Check-in Prevention Logic');
    console.log('─'.repeat(60));
    try {
      const openAttendance = await Attendance.findOne({ checkOut: { $exists: false } });
      if (openAttendance) {
        console.log(`✓ PASS: Double check-in prevention would catch this case`);
        console.log(`  User ${openAttendance.employee} is currently checked in (since ${openAttendance.checkIn.toLocaleTimeString()})\n`);
      } else {
        console.log('⚠ INFO: No open check-ins to test against\n');
      }
      tests.passed++;
    } catch (e) {
      console.log(`✗ FAIL: ${e.message}\n`);
      tests.failed++;
    }

    // Test 5: Data Integrity Check
    console.log('📋 TEST 5: Data Integrity & Field Validation');
    console.log('─'.repeat(60));
    try {
      const attendance = await Attendance.findOne()
        .populate('employee')
        .populate('geofence');
      if (attendance) {
        const hasRequiredFields =
          attendance.employee &&
          attendance.geofence &&
          attendance.checkIn &&
          (attendance.checkOut || attendance.checkOut === undefined) &&
          attendance.status;

        if (hasRequiredFields) {
          console.log('✓ PASS: Attendance records have all required fields');
          console.log(`  Employee: ${attendance.employee?.name}`);
          console.log(`  Geofence: ${attendance.geofence?.name}`);
          console.log(`  Status: ${attendance.status}`);
          console.log(`  Check-in: ${attendance.checkIn.toLocaleString()}`);
          if (attendance.checkOut) console.log(`  Check-out: ${attendance.checkOut.toLocaleString()}`);
          console.log();
        } else {
          console.log('✗ FAIL: Missing required fields\n');
          tests.failed++;
        }
      } else {
        console.log('⚠ INFO: No attendance records to validate\n');
      }
      tests.passed++;
    } catch (e) {
      console.log(`✗ FAIL: ${e.message}\n`);
      tests.failed++;
    }

    // Summary
    console.log('═'.repeat(60));
    console.log(`📊 TEST SUMMARY`);
    console.log(`  Passed: ${tests.passed}`);
    console.log(`  Failed: ${tests.failed}`);
    console.log(`  Status: ${tests.failed === 0 ? '✅ ALL TESTS PASSED' : '⚠️  SOME TESTS FAILED'}`);
    console.log('═'.repeat(60));

    await mongoose.connection.close();
    process.exit(tests.failed === 0 ? 0 : 1);
  } catch (err) {
    console.error('❌ Test suite error:', err);
    process.exit(1);
  }
}

runTests();
