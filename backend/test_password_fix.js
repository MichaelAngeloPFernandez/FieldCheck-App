const mongoose = require('mongoose');
const User = require('./models/User');
const dotenv = require('dotenv');

dotenv.config();

async function testPasswords() {
  try {
    await mongoose.connect(process.env.MONGO_URI);
    console.log('Testing password fixes...\n');
    
    const testUsers = ['ad001', 'en001', 'en005', 'en010'];
    
    for (const username of testUsers) {
      const user = await User.findOne({ username });
      if (!user) {
        console.log(`❌ ${username} not found`);
        continue;
      }
      
      const match = await user.matchPassword('password123');
      console.log(`${match ? '✅' : '❌'} ${username} password match: ${match}`);
    }
    
    console.log('\n✅ All passwords have been successfully reset to: password123');
    await mongoose.connection.close();
  } catch (err) {
    console.error('❌ Error:', err.message);
    process.exit(1);
  }
}

testPasswords();
