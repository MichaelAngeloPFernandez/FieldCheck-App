const dotenv = require('dotenv');
const path = require('path');
const mongoose = require('mongoose');

dotenv.config({ path: path.join(__dirname, '.env') });

const User = require('./models/User');

async function main() {
  const identifierArg = process.argv.find((a) => a.startsWith('--identifier='));
  const identifier = identifierArg
    ? identifierArg.split('=').slice(1).join('=').trim()
    : 'admin001';

  const value = identifier.toLowerCase();
  const exactInsensitive = new RegExp(`^${value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}$`, 'i');

  if (!process.env.MONGO_URI) {
    throw new Error('MONGO_URI is not set. Put it in backend/.env or your environment variables.');
  }

  await mongoose.connect(process.env.MONGO_URI);

  const user = await User.findOne({
    $or: [
      { email: exactInsensitive },
      { username: exactInsensitive },
      { employeeId: exactInsensitive },
      { name: exactInsensitive },
    ],
  }).select('name username email employeeId role isVerified isActive tokenVersion createdAt updatedAt');

  console.log(JSON.stringify(user, null, 2));

  await mongoose.disconnect();
}

main().catch((err) => {
  console.error('❌ Error:', err.message);
  process.exit(1);
});
