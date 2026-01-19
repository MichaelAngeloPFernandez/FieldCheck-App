const mongoose = require('mongoose');
const dotenv = require('dotenv');
const bcrypt = require('bcryptjs');
const readline = require('readline');

const User = require('./models/User');

dotenv.config();

async function confirmOrExit() {
  if (process.argv.includes('--yes')) return;

  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  const answer = await new Promise((resolve) => {
    rl.question('This will reset ALL user passwords. Type RESET to continue: ', resolve);
  });
  rl.close();

  if (answer.trim() !== 'RESET') {
    console.log('Aborted.');
    process.exit(0);
  }
}

async function main() {
  const newPasswordArg = process.argv.find((a) => a.startsWith('--password='));
  const newPassword = newPasswordArg ? newPasswordArg.split('=').slice(1).join('=') : 'password123';

  if (!process.env.MONGO_URI) {
    throw new Error('MONGO_URI is not set. Put it in backend/.env or your environment variables.');
  }

  await confirmOrExit();

  await mongoose.connect(process.env.MONGO_URI);

  const total = await User.countDocuments({});
  console.log(`Connected. Users found: ${total}`);

  const salt = await bcrypt.genSalt(10);
  const hashedPassword = await bcrypt.hash(newPassword, salt);

  const result = await User.updateMany({}, { $set: { password: hashedPassword } });

  const modifiedCount =
    typeof result.modifiedCount === 'number'
      ? result.modifiedCount
      : typeof result.nModified === 'number'
        ? result.nModified
        : undefined;

  console.log('Password reset complete.');
  console.log(`New password: ${newPassword}`);
  console.log(`Matched: ${result.matchedCount ?? result.n ?? 'unknown'}`);
  console.log(`Modified: ${modifiedCount ?? 'unknown'}`);

  await mongoose.disconnect();
}

main().catch((err) => {
  console.error('❌ Error:', err.message);
  process.exit(1);
});
