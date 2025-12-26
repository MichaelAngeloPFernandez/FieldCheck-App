const mongoose = require('mongoose');
let memoryServer;

const connectDB = async () => {
  const uri = process.env.MONGO_URI;
  try {
    if (uri) {
      await mongoose.connect(uri);
      console.log(`MongoDB Connected: ${mongoose.connection.host}`);
      return;
    }
    throw new Error('MONGO_URI not set');
  } catch (error) {
    console.error(`Primary DB connect failed: ${error.message}`);
    try {
      const { MongoMemoryServer } = require('mongodb-memory-server');
      memoryServer = await MongoMemoryServer.create();
      const memUri = memoryServer.getUri();
      await mongoose.connect(memUri);
      process.env.USE_INMEMORY_DB = 'true';
      console.log('Using in-memory MongoDB for development.');
    } catch (memErr) {
      console.error(`In-memory DB startup failed: ${memErr.message}`);
      process.exit(1);
    }
  }
};

module.exports = connectDB;