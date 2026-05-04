const mongoose = require('mongoose');
const dotenv = require('dotenv');
const User = require('./models/User');

dotenv.config();

async function restoreAvatarUrls() {
  try {
    await mongoose.connect(process.env.MONGO_URI || 'mongodb://localhost:27017/fieldcheck');
    console.log('✅ Connected to MongoDB\n');

    const db = mongoose.connection.db;
    
    // Get all avatar files with metadata
    const avatarFiles = await db.collection('userAvatars.files').find({}).toArray();
    console.log(`📁 Found ${avatarFiles.length} avatar files\n`);
    
    let restored = 0;
    
    for (const file of avatarFiles) {
      const userId = file.metadata?.uploadedBy;
      if (!userId) {
        console.log(`❌ File ${file._id} has no uploadedBy metadata`);
        continue;
      }
      
      const user = await User.findById(userId);
      if (!user) {
        console.log(`❌ User ${userId} not found for file ${file.filename}`);
        continue;
      }
      
      // Restore the avatarUrl - format is typically /api/users/{userId}/avatar or similar
      const avatarUrl = `/api/users/${userId}/avatar`;
      await User.updateOne(
        { _id: userId },
        { $set: { avatarUrl } }
      );
      
      console.log(`✅ Restored avatar for ${user.username} (${user.name})`);
      console.log(`   Avatar URL: ${avatarUrl}`);
      console.log(`   File: ${file.filename}\n`);
      restored++;
    }
    
    console.log(`\n✅ Successfully restored ${restored} avatar references`);
    
    // Verify
    const usersWithAvatars = await User.find({ avatarUrl: { $exists: true, $ne: '' } });
    console.log(`👤 Users with avatarUrl now: ${usersWithAvatars.length}`);
    
    await mongoose.connection.close();
  } catch (err) {
    console.error('❌ Error:', err.message);
    process.exit(1);
  }
}

restoreAvatarUrls();
