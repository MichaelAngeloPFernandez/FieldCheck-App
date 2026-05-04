const mongoose = require('mongoose');
const bcrypt = require('bcryptjs');
const dotenv = require('dotenv');
const User = require('./models/User');

dotenv.config();

async function attemptRecovery() {
  try {
    await mongoose.connect(process.env.MONGO_URI);
    console.log('✅ Connected to MongoDB\n');

    const db = mongoose.connection.db;
    
    // Get all old user IDs that have data
    const oldUserIds = new Set();
    
    console.log('🔍 Collecting old user IDs from data...\n');
    
    // From employee locations
    const locations = await db.collection('employeelocations').find({}).limit(100).toArray();
    locations.forEach(loc => {
      if (loc.user) oldUserIds.add(loc.user.toString());
    });
    
    // From usertasks
    const userTasks = await db.collection('usertasks').find({}).limit(100).toArray();
    userTasks.forEach(ut => {
      if (ut.userId) oldUserIds.add(ut.userId.toString());
    });
    
    // From conversations
    const conversations = await db.collection('conversations').find({}).toArray();
    conversations.forEach(conv => {
      if (Array.isArray(conv.participants)) {
        conv.participants.forEach(p => oldUserIds.add(p.toString()));
      }
    });

    console.log(`📋 Found ${oldUserIds.size} old user IDs with data\n`);
    console.log('═'.repeat(80));
    console.log('\n⚠️  RECOVERY OPTIONS:\n');
    
    console.log('Option 1: RESTORE FROM MONGODB ATLAS BACKUP (Recommended)');
    console.log('─────────────────────────────────────────────────────────');
    console.log('If you have Atlas automatic backups enabled:');
    console.log('1. Go to: https://cloud.mongodb.com/');
    console.log('2. Select your project and cluster');
    console.log('3. Go to: Backup > Cloud Backup');
    console.log('4. Find a snapshot from before 5/5/2026');
    console.log('5. Click "Restore" and choose a target (create new cluster or overwrite)');
    console.log('');
    console.log('Option 2: RECONSTRUCT USER RECORDS');
    console.log('────────────────────────────────────');
    console.log(`We can recreate ${oldUserIds.size} user records with their old IDs`);
    console.log('and set a temporary password for all of them.');
    console.log('');
    console.log('Old User IDs with data:');
    const idsArray = Array.from(oldUserIds).slice(0, 10);
    idsArray.forEach((id, idx) => {
      console.log(`  ${idx + 1}. ${id}`);
    });
    if (oldUserIds.size > 10) {
      console.log(`  ... and ${oldUserIds.size - 10} more`);
    }
    
    console.log('\n═'.repeat(80));
    console.log('\n🎯 RECOMMENDED ACTION:');
    console.log('─────────────────────');
    console.log('1. Check if MongoDB Atlas backups are available');
    console.log('2. If yes: Restore from a pre-5/5/2026 backup');
    console.log('3. If no: Run the user reconstruction script we provide');
    console.log('\n');

    await mongoose.connection.close();
  } catch (err) {
    console.error('❌ Error:', err.message);
    process.exit(1);
  }
}

attemptRecovery();
