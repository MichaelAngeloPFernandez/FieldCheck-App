const mongoose = require('mongoose');
const dotenv = require('dotenv');

dotenv.config();

async function detailedAnalysis() {
  try {
    await mongoose.connect(process.env.MONGO_URI);
    console.log('✅ Connected to MongoDB\n');

    const db = mongoose.connection.db;
    
    // Get ALL users with all their data
    const allUsers = await db.collection('users').find({}).toArray();
    console.log(`📊 Total users in collection: ${allUsers.length}\n`);
    
    // Group by creation date
    const byDate = {};
    allUsers.forEach(user => {
      const date = new Date(user.createdAt).toLocaleDateString();
      if (!byDate[date]) byDate[date] = [];
      byDate[date].push(user);
    });
    
    console.log('Users by creation date:');
    Object.keys(byDate).sort().forEach(date => {
      console.log(`\n${date}: ${byDate[date].length} users`);
      byDate[date].slice(0, 3).forEach(u => {
        console.log(`  - ${u.username} (${u._id})`);
      });
      if (byDate[date].length > 3) {
        console.log(`  ... and ${byDate[date].length - 3} more`);
      }
    });
    
    // Check for duplicate usernames
    console.log('\n' + '═'.repeat(80));
    console.log('Checking for duplicate usernames:\n');
    
    const usersByUsername = {};
    allUsers.forEach(user => {
      if (!usersByUsername[user.username]) {
        usersByUsername[user.username] = [];
      }
      usersByUsername[user.username].push(user._id);
    });
    
    let duplicates = 0;
    Object.entries(usersByUsername).forEach(([username, ids]) => {
      if (ids.length > 1) {
        console.log(`⚠️  Username "${username}" has ${ids.length} records:`);
        ids.forEach(id => console.log(`   - ${id}`));
        duplicates++;
      }
    });
    
    if (duplicates === 0) {
      console.log('✅ No duplicate usernames found');
    }
    
    // Check oldest users
    console.log('\n' + '═'.repeat(80));
    console.log('Oldest users (first 5):\n');
    
    const sorted = allUsers.sort((a, b) => new Date(a.createdAt) - new Date(b.createdAt));
    sorted.slice(0, 5).forEach((user, idx) => {
      console.log(`${idx + 1}. ${user.username} - ID: ${user._id}`);
      console.log(`   Created: ${new Date(user.createdAt).toLocaleString()}`);
      console.log(`   Name: ${user.name}`);
      console.log('');
    });

    await mongoose.connection.close();
  } catch (err) {
    console.error('❌ Error:', err.message);
    process.exit(1);
  }
}

detailedAnalysis();
