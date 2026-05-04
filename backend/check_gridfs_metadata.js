const mongoose = require('mongoose');
const dotenv = require('dotenv');

dotenv.config();

async function checkGridFSMetadata() {
  try {
    await mongoose.connect(process.env.MONGO_URI || 'mongodb://localhost:27017/fieldcheck');
    console.log('✅ Connected to MongoDB\n');

    const db = mongoose.connection.db;
    
    // Get all avatar file details including metadata
    const avatarFiles = await db.collection('userAvatars.files').find({}).toArray();
    console.log(`📁 Avatar Files with Full Details:\n`);
    
    avatarFiles.forEach((file, idx) => {
      console.log(`${idx + 1}. File ID: ${file._id}`);
      console.log(`   Filename: ${file.filename}`);
      console.log(`   Uploaded: ${file.uploadDate}`);
      console.log(`   Full metadata:`, JSON.stringify(file, null, 2));
      console.log('');
    });

    // Also check report attachments to see how they store references
    const reportAttachments = await db.collection('reportAttachments.files').findOne({});
    if (reportAttachments) {
      console.log('Report attachment example (for comparison):');
      console.log(JSON.stringify(reportAttachments, null, 2));
    }

    await mongoose.connection.close();
  } catch (err) {
    console.error('❌ Error:', err.message);
    process.exit(1);
  }
}

checkGridFSMetadata();
