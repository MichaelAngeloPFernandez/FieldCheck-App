const mongoose = require('mongoose');
const dotenv = require('dotenv');
const User = require('./models/User');

dotenv.config();

async function migrateOldUserData() {
  try {
    await mongoose.connect(process.env.MONGO_URI || 'mongodb://localhost:27017/fieldcheck');
    console.log('✅ Connected to MongoDB\n');

    const db = mongoose.connection.db;
    
    // Get all unique old user IDs from various collections
    const oldUserIds = new Set();
    
    // From employee locations
    const locations = await db.collection('employeelocations').find({}).toArray();
    locations.forEach(loc => {
      if (loc.user) oldUserIds.add(loc.user.toString());
    });
    
    // From usertasks
    const userTasks = await db.collection('usertasks').find({}).toArray();
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
    
    // From chat messages
    const chatMessages = await db.collection('chatmessages').find({}).toArray();
    chatMessages.forEach(msg => {
      if (msg.senderUser) oldUserIds.add(msg.senderUser.toString());
      if (Array.isArray(msg.readBy)) {
        msg.readBy.forEach(r => oldUserIds.add(r.toString()));
      }
    });
    
    // From avatar files metadata
    const avatarFiles = await db.collection('userAvatars.files').find({}).toArray();
    avatarFiles.forEach(file => {
      if (file.metadata?.uploadedBy) oldUserIds.add(file.metadata.uploadedBy.toString());
    });

    console.log(`📊 Found ${oldUserIds.size} old user IDs referenced in data:`);
    console.log('─'.repeat(80));
    
    // Try to find old users (they might still exist in the database with old IDs)
    let foundOldUsers = 0;
    for (const userId of oldUserIds) {
      try {
        const oldUser = await User.findById(userId).select('-password');
        if (oldUser) {
          console.log(`✅ Found old user: ${oldUser.name || 'Unknown'} (${oldUser.username || 'N/A'})`);
          foundOldUsers++;
        }
      } catch (e) {
        // User not found, that's ok
      }
    }
    
    console.log(`\n${foundOldUsers} old users still exist in database`);
    console.log(`${oldUserIds.size - foundOldUsers} old user IDs have no user record (data orphaned)\n`);
    
    if (foundOldUsers > 0) {
      console.log('✅ Good news: Old user records still exist!');
      console.log('   Your profile data, locations, tasks, and messages can be recovered.');
      console.log('\nNext steps:');
      console.log('1. Log in with your old username/password');
      console.log('2. All your data will be available');
    } else {
      console.log('⚠️  Old user records have been deleted from the database.');
      console.log('   However, all the data (locations, tasks, messages) still exists.');
      console.log('   We need to restore the user records to link the data.');
    }

    await mongoose.connection.close();
  } catch (err) {
    console.error('❌ Error:', err.message);
    process.exit(1);
  }
}

migrateOldUserData();
