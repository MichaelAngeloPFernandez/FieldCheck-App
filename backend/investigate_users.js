const mongoose = require('mongoose');
const dotenv = require('dotenv');
const User = require('./models/User');

dotenv.config();

async function investigateUsers() {
  try {
    await mongoose.connect(process.env.MONGO_URI || 'mongodb://localhost:27017/fieldcheck');
    console.log('✅ Connected to MongoDB\n');

    // Get all users
    const users = await User.find().select('_id username email name employeeId createdAt');
    console.log(`📊 Current users in database: ${users.length}\n`);
    
    users.forEach(user => {
      console.log(`ID: ${user._id}`);
      console.log(`Username: ${user.username}`);
      console.log(`Name: ${user.name}`);
      console.log(`Created: ${user.createdAt}`);
      console.log('');
    });

    // Check other collections for references to old user IDs
    const db = mongoose.connection.db;
    
    console.log('\n═'.repeat(80));
    console.log('Checking for old user ID references in other collections:\n');
    
    // Get all employees from locations
    const locations = await db.collection('employeelocations').find({}).toArray();
    const uniqueUserIds = new Set(locations.map(l => l.user?.toString()));
    
    console.log(`📍 Employee locations reference ${uniqueUserIds.size} unique user IDs:`);
    [...uniqueUserIds].slice(0, 10).forEach(uid => console.log(`  - ${uid}`));
    
    // Check if any old IDs match avatar metadata
    const avatarFiles = await db.collection('userAvatars.files').find({}).toArray();
    console.log(`\n📁 Avatar file owner IDs:`);
    avatarFiles.forEach(file => {
      const uploadedBy = file.metadata?.uploadedBy;
      console.log(`  - ${uploadedBy} (${file.filename})`);
    });

    await mongoose.connection.close();
  } catch (err) {
    console.error('❌ Error:', err.message);
    process.exit(1);
  }
}

investigateUsers();
