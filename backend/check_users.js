const mongoose = require('mongoose');
const dotenv = require('dotenv');
const User = require('./models/User');

dotenv.config();

async function checkUsers() {
  try {
    await mongoose.connect(process.env.MONGO_URI || 'mongodb://localhost:27017/fieldcheck');
    console.log('✅ Connected to MongoDB');

    // Get all users
    const users = await User.find().select('name username email role createdAt');
    
    console.log('\n📋 All Users in Database:');
    console.log('═'.repeat(80));
    
    if (users.length === 0) {
      console.log('No users found in database.');
    } else {
      users.forEach((user, index) => {
        console.log(`\n${index + 1}. Name: ${user.name || 'N/A'}`);
        console.log(`   Username: ${user.username || 'N/A'}`);
        console.log(`   Email: ${user.email || 'N/A'}`);
        console.log(`   Role: ${user.role}`);
        console.log(`   Created: ${user.createdAt?.toLocaleDateString()}`);
      });
    }

    console.log('\n' + '═'.repeat(80));
    console.log(`Total Users: ${users.length}\n`);

    await mongoose.connection.close();
  } catch (err) {
    console.error('❌ Error:', err.message);
    process.exit(1);
  }
}

checkUsers();
