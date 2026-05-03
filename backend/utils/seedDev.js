const User = require('../models/User');

async function seedDevData() {
  try {
    const adminEmail = 'admin@example.com';
    const adminExists = await User.findOne({ email: adminEmail });
    if (!adminExists) {
      await User.create({
        name: 'Admin',
        username: 'admin',
        email: adminEmail,
        password: 'admin123',
        role: 'admin',
        isVerified: true,
        isActive: true,
      });
      console.log('Seeded dev admin: admin / admin123');
    } else {
      let changed = false;
      if (adminExists.username !== 'admin') {
        adminExists.username = 'admin';
        changed = true;
      }
      if (adminExists.email !== adminEmail) {
        adminExists.email = adminEmail;
        changed = true;
      }
      if (adminExists.role !== 'admin') {
        adminExists.role = 'admin';
        changed = true;
      }
      if (adminExists.isVerified !== true) {
        adminExists.isVerified = true;
        changed = true;
      }
      if (adminExists.isActive !== true) {
        adminExists.isActive = true;
        changed = true;
      }

      // Refresh admin password for local testing
      adminExists.password = 'admin123';
      changed = true;

      if (changed) {
        await adminExists.save();
        console.log('Updated dev admin: admin / admin123');
      }
    }

    // Employees: employee1..employee5 username-only with incrementing password pattern
    const employees = [
      { name: 'employee1', username: 'employee1', password: 'employee123' },
      { name: 'employee2', username: 'employee2', password: 'employee1234' },
      { name: 'employee3', username: 'employee3', password: 'employee12345' },
      { name: 'employee4', username: 'employee4', password: 'employee123456' },
      { name: 'employee5', username: 'employee5', password: 'employee1234567' },
      { name: 'Mark Perfecto', username: 'marper', password: 'marper123', email: 'karevindp@gmail.com' },
    ];

    for (const e of employees) {
      // Prefer finding by username; fall back to email records to migrate
      let existing = await User.findOne({ username: e.username });
      if (!existing) {
        existing = await User.findOne({ name: e.name });
      }
      if (!existing) {
        await User.create({
          name: e.name,
          username: e.username,
          email: e.email || undefined,
          password: e.password,
          role: 'employee',
          isVerified: true,
          isActive: true,
        });
        console.log(`Seeded dev employee: ${e.username} / ${e.password}`);
      } else {
        // Migrate any old email-based records to username-only and refresh password
        let changed = false;
        if (existing.username !== e.username) {
          existing.username = e.username;
          changed = true;
        }
        if (existing.name !== e.name) {
          existing.name = e.name;
          changed = true;
        }
        // Update email if provided
        if (e.email && existing.email !== e.email) {
          existing.email = e.email;
          changed = true;
        }
        // Always refresh the password to the specified one
        existing.password = e.password; // Will be hashed by pre-save hook
        changed = true;
        if (changed) {
          await existing.save();
          console.log(`Updated dev employee: ${e.username} / ${e.password}`);
        }
      }
    }
  } catch (err) {
    console.error('Dev seeding failed:', err.message);
  }
}

module.exports = { seedDevData };