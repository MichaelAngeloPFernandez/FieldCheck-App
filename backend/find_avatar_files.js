const mongoose = require('mongoose');
const dotenv = require('dotenv');
const User = require('./models/User');

dotenv.config();

async function findAvatarFiles() {
  try {
    await mongoose.connect(process.env.MONGO_URI || 'mongodb://localhost:27017/fieldcheck');
    console.log('✅ Connected to MongoDB\n');

    const db = mongoose.connection.db;
    
    // Get all avatar files from GridFS
    const avatarFiles = await db.collection('userAvatars.files').find({}).toArray();
    console.log(`📁 Found ${avatarFiles.length} avatar files in GridFS\n`);
    
    avatarFiles.forEach(file => {
      console.log(`File ID: ${file._id}`);
      console.log(`Filename: ${file.filename}`);
      console.log(`Uploaded: ${file.uploadDate}`);
      console.log(`Size: ${file.length} bytes`);
      console.log('');
    });

    // Check all users with avatarUrl
    const usersWithAvatars = await User.find({ avatarUrl: { $exists: true, $ne: '' } });
    console.log(`\n👤 Users with avatarUrl: ${usersWithAvatars.length}`);
    usersWithAvatars.forEach(user => {
      console.log(`  - ${user.username}: ${user.avatarUrl}`);
    });

    await mongoose.connection.close();
  } catch (err) {
    console.error('❌ Error:', err.message);
    process.exit(1);
  }
}

findAvatarFiles();
