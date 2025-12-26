/**
 * MongoDB Migration Script: Fix Null Geofences in Attendance Records
 * 
 * This script finds all attendance records with null or missing geofence references
 * and attempts to populate them based on the employee's assigned geofences.
 * 
 * Usage:
 * node fixNullGeofences.js
 */

const mongoose = require('mongoose');
const dotenv = require('dotenv');

dotenv.config();

// Import models
const Attendance = require('../models/Attendance');
const Geofence = require('../models/Geofence');
const User = require('../models/User');

async function fixNullGeofences() {
  try {
    // Connect to MongoDB
    await mongoose.connect(process.env.MONGO_URI || 'mongodb://localhost:27017/fieldcheck');
    console.log('✓ Connected to MongoDB');

    // Find all attendance records with null geofence
    const nullGeofenceRecords = await Attendance.find({
      $or: [
        { geofence: null },
        { geofence: { $exists: false } },
      ],
    }).populate('employee');

    console.log(`\n📋 Found ${nullGeofenceRecords.length} attendance records with null geofence`);

    if (nullGeofenceRecords.length === 0) {
      console.log('✓ No records to fix!');
      await mongoose.connection.close();
      return;
    }

    let fixed = 0;
    let unfixed = 0;

    // Process each record
    for (const record of nullGeofenceRecords) {
      try {
        if (!record.employee) {
          console.log(`⚠ Skipping record ${record._id}: Employee not found`);
          unfixed++;
          continue;
        }

        // Find geofences assigned to this employee
        const assignedGeofences = await Geofence.find({
          assignedEmployees: record.employee._id,
        });

        if (assignedGeofences.length === 0) {
          console.log(
            `⚠ Skipping record ${record._id}: No geofences assigned to employee ${record.employee.name}`,
          );
          unfixed++;
          continue;
        }

        // Use the first assigned geofence
        record.geofence = assignedGeofences[0]._id;
        await record.save();

        console.log(
          `✓ Fixed record ${record._id}: Assigned geofence ${assignedGeofences[0].name}`,
        );
        fixed++;
      } catch (err) {
        console.error(`✗ Error fixing record ${record._id}:`, err.message);
        unfixed++;
      }
    }

    console.log(`\n📊 Migration Summary:`);
    console.log(`   ✓ Fixed: ${fixed}`);
    console.log(`   ✗ Unfixed: ${unfixed}`);
    console.log(`   Total: ${fixed + unfixed}`);

    // Verify the fix
    const remainingNullRecords = await Attendance.find({
      $or: [
        { geofence: null },
        { geofence: { $exists: false } },
      ],
    });

    console.log(`\n✓ Verification: ${remainingNullRecords.length} records still have null geofence`);

    await mongoose.connection.close();
    console.log('\n✓ Migration complete!');
  } catch (error) {
    console.error('✗ Migration failed:', error);
    process.exit(1);
  }
}

// Run the migration
fixNullGeofences();
