const mongoose = require('mongoose');
const dotenv = require('dotenv');
const User = require('./models/User');

dotenv.config();

async function inspectUsers() {
  try {
    await mongoose.connect(process.env.MONGO_URI || 'mongodb://localhost:27017/fieldcheck');
    console.log('✅ Connected to MongoDB\n');

    const users = await User.find().lean();
    
    console.log(`📊 Found ${users.length} users\n`);
    console.log('═'.repeat(100));
    
    users.slice(0, 3).forEach((user, idx) => {
      console.log(`\n${idx + 1}. ${user.name || 'N/A'} (${user.username})`);
      console.log('   Full user document:');
      console.log(JSON.stringify(user, null, 2));
      console.log('');
    });

    await mongoose.connection.close();
  } catch (err) {
    console.error('❌ Error:', err.message);
    process.exit(1);
  }
}

inspectUsers();
