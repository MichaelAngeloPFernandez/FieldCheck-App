const mongoose = require('mongoose');
const dotenv = require('dotenv');

dotenv.config();

async function checkCollections() {
  try {
    await mongoose.connect(process.env.MONGO_URI || 'mongodb://localhost:27017/fieldcheck');
    console.log('✅ Connected to MongoDB\n');

    const db = mongoose.connection.db;
    const collections = await db.listCollections().toArray();
    
    console.log(`📊 Total Collections: ${collections.length}\n`);
    console.log('═'.repeat(100));
    
    for (const coll of collections) {
      const count = await db.collection(coll.name).countDocuments();
      console.log(`\n📋 ${coll.name}: ${count} documents`);
      
      if (count > 0 && coll.name !== 'users') {
        const sample = await db.collection(coll.name).findOne();
        if (sample) {
          console.log('   Sample document:');
          console.log('   ', JSON.stringify(sample).substring(0, 150) + '...');
        }
      }
    }

    await mongoose.connection.close();
  } catch (err) {
    console.error('❌ Error:', err.message);
    process.exit(1);
  }
}

checkCollections();
