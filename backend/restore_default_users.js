const dotenv = require('dotenv');
const path = require('path');
const mongoose = require('mongoose');
const bcrypt = require('bcryptjs');

dotenv.config({ path: path.join(__dirname, '.env') });

const User = require('./models/User');

function getArg(name, fallback) {
  const prefix = `--${name}=`;
  const arg = process.argv.find((a) => a.startsWith(prefix));
  if (!arg) return fallback;
  return arg.slice(prefix.length);
}

function escapeRegExp(str) {
  return String(str).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

async function upsertByEmployeeIdInsensitive(employeeId, update, createIfMissing) {
  const exactInsensitive = new RegExp(`^${escapeRegExp(employeeId)}$`, 'i');
  const existing = await User.findOne({ employeeId: exactInsensitive }).select('_id employeeId');

  if (!existing && !createIfMissing) {
    return { action: 'skipped_missing', employeeId };
  }

  if (!existing) {
    const user = new User(update);
    await user.save();
    return { action: 'created', employeeId, id: String(user._id) };
  }

  await User.updateOne({ _id: existing._id }, { $set: update });
  return { action: 'updated', employeeId, id: String(existing._id) };
}

async function main() {
  const from = parseInt(getArg('from', '1'), 10);
  const to = parseInt(getArg('to', '10'), 10);
  const adminId = (getArg('admin', 'AD001') || 'AD001').trim();
  const password = getArg('password', 'password123');

  const resetPasswords = process.argv.includes('--reset-passwords');
  const createMissingOnly = !process.argv.includes('--update-existing');

  if (!process.env.MONGO_URI) {
    throw new Error('MONGO_URI is not set. Put it in backend/.env or your environment variables.');
  }

  if (Number.isNaN(from) || Number.isNaN(to) || from < 1 || to < from) {
    throw new Error('Invalid range. Use --from=1 --to=10');
  }

  await mongoose.connect(process.env.MONGO_URI);

  const salt = await bcrypt.genSalt(10);
  const hashedPassword = await bcrypt.hash(password, salt);

  const results = [];

  // Admin
  {
    const update = {
      name: `Admin ${adminId}`,
      username: adminId.toLowerCase(),
      employeeId: adminId,
      role: 'admin',
      isVerified: true,
      isActive: true,
      provider: 'local',
    };

    if (resetPasswords) {
      update.password = hashedPassword;
    }

    if (!createMissingOnly) {
      // update existing or create
      results.push(await upsertByEmployeeIdInsensitive(adminId, update, true));
    } else {
      // create only if missing
      const exactInsensitive = new RegExp(`^${escapeRegExp(adminId)}$`, 'i');
      const existing = await User.findOne({ employeeId: exactInsensitive }).select('_id');
      if (existing) {
        results.push({ action: 'skipped_existing', employeeId: adminId, id: String(existing._id) });
      } else {
        const user = new User({ ...update, password: hashedPassword });
        await user.save();
        results.push({ action: 'created', employeeId: adminId, id: String(user._id) });
      }
    }
  }

  // Employees ENxxx
  for (let i = from; i <= to; i += 1) {
    const empId = `EN${String(i).padStart(3, '0')}`;

    const update = {
      name: `Employee ${empId}`,
      username: empId.toLowerCase(),
      employeeId: empId,
      role: 'employee',
      isVerified: true,
      isActive: true,
      provider: 'local',
    };

    if (resetPasswords) {
      update.password = hashedPassword;
    }

    if (!createMissingOnly) {
      results.push(await upsertByEmployeeIdInsensitive(empId, update, true));
      continue;
    }

    const exactInsensitive = new RegExp(`^${escapeRegExp(empId)}$`, 'i');
    const existing = await User.findOne({ employeeId: exactInsensitive }).select('_id');
    if (existing) {
      results.push({ action: 'skipped_existing', employeeId: empId, id: String(existing._id) });
    } else {
      const user = new User({ ...update, password: hashedPassword });
      await user.save();
      results.push({ action: 'created', employeeId: empId, id: String(user._id) });
    }
  }

  console.log(JSON.stringify({
    mongo: process.env.MONGO_URI.replace(/:\/\/.*@/, '://***@'),
    adminId,
    from,
    to,
    resetPasswords,
    updateExisting: !createMissingOnly,
    results,
  }, null, 2));

  await mongoose.disconnect();
}

main().catch((err) => {
  console.error('❌ Error:', err.message);
  process.exit(1);
});
