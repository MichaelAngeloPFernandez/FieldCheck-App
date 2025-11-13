# 👥 GROUPMATE SETUP GUIDE - FieldCheck 2.0

**For:** Team members testing FieldCheck 2.0
**Time Required:** 30 minutes total
**Difficulty:** Easy

---

## 🎯 What You'll Learn

By the end of this guide, you'll be able to:
- ✅ Set up MongoDB Atlas account
- ✅ Access the shared MongoDB cluster
- ✅ Run the backend locally
- ✅ Run the Flutter app
- ✅ Test all features

---

## ⏱️ Timeline

| Task | Time |
|------|------|
| MongoDB Setup | 5 min |
| Clone Repository | 3 min |
| Install Dependencies | 10 min |
| Run Backend | 2 min |
| Run Flutter App | 5 min |
| Test Features | 5 min |
| **TOTAL** | **30 min** |

---

## 📋 PART 1: MongoDB Atlas Setup

### Step 1.1: Create MongoDB Atlas Account

1. Go to: https://www.mongodb.com/cloud/atlas
2. Click "Try Free"
3. Sign up with:
   - Email: Your email
   - Password: Create strong password
4. Verify your email (check inbox)

✅ You now have a MongoDB account!

### Step 1.2: Ask Mark for Cluster Access

**Contact Mark Karevin:**
- Say: "Can I be added to the FieldCheck 2.0 MongoDB cluster?"
- Mark will:
  1. Add your email to the organization
  2. Share the project link
  3. Give you access to cluster0

Once Mark adds you:
1. Check email for MongoDB invitation
2. Click the link
3. Accept the invitation
4. You'll see `cluster0.qpphvdn.mongodb.net` in your dashboard

✅ You now have access to the shared database!

---

## 💻 PART 2: Clone & Setup Code

### Step 2.1: Clone the Repository

```powershell
# Open PowerShell or Git Bash

# Navigate to where you want the project
cd Documents

# Clone the repository
git clone https://github.com/ShaqmayBalS/capstone_fieldcheck_2.0.git

# Enter the project folder
cd capstone_fieldcheck_2.0
```

✅ Code is now on your machine!

### Step 2.2: Install Backend Dependencies

```powershell
# Navigate to backend folder
cd backend

# Install Node.js packages
npm install

# Wait for all packages to download (~30 seconds)
```

✅ Backend dependencies installed!

### Step 2.3: Install Flutter Dependencies

```powershell
# Navigate to Flutter app folder
cd ..
cd field_check

# Get all Flutter packages
flutter pub get

# Wait for packages to download (~1-2 minutes)
```

✅ Flutter dependencies installed!

---

## 🚀 PART 3: Configure & Run

### Step 3.1: Backend Configuration (Already Done!)

The backend `.env` file is already configured with:
- ✅ MongoDB connection string
- ✅ JWT settings
- ✅ Port 3002
- ✅ All production settings

**No changes needed!** Just run it.

### Step 3.2: Start the Backend

```powershell
# From project root, go to backend
cd backend

# Start the server
npm start
```

You should see:
```
✅ MongoDB Connected: ac-uzkdtz2-shard-00-00.qpphvdn.mongodb.net
✅ Server running on port 3002
✅ Seeded dev admin: admin / Admin@123
✅ Seeded dev employee: employee1 / employee123
```

**Keep this terminal running!** (Don't close it)

### Step 3.3: Start Flutter App (New Terminal)

**Open a NEW PowerShell window:**

```powershell
# Navigate to Flutter project
cd "path\to\FIELDCHECK_2.0\field_check"

# Run the app
flutter run

# Choose your platform:
# - web (Chrome browser) - easiest
# - android (if you have Android)
# - ios (if you have iPhone)
# - windows (if installed)
```

**Easiest option:** `flutter run -d chrome` (runs in browser)

---

## 📱 PART 4: Test the App

### Test Account 1: Admin

```
Email: admin@example.com
Password: Admin@123
```

**Admin can:**
- View all employees
- Search employees
- Filter by status
- Bulk deactivate users
- Manage geofences
- View reports

### Test Account 2: Employee

```
Email: employee1@example.com
Password: employee123
```

**Employee can:**
- Check in/out via GPS
- View attendance history
- Edit profile
- View geofences on map
- Manage assigned tasks

### Test Procedures

**1. Test Login:**
- [ ] Admin login works
- [ ] Employee login works
- [ ] Invalid password rejected
- [ ] Tokens saved correctly

**2. Test Employee Features:**
- [ ] Can view profile
- [ ] Can see attendance history
- [ ] Can view map with geofences
- [ ] Can view dashboard

**3. Test Admin Features:**
- [ ] Can search employees
- [ ] Can filter by status
- [ ] Can see employee details
- [ ] Can manage geofences

**4. Test Data Persistence:**
- [ ] Close and reopen app
- [ ] Data still there ✅
- [ ] Database in cloud ✅

---

## 🔌 PART 5: Verify MongoDB Connection

### Check Backend Logs

In the backend terminal where `npm start` is running, you should see:

```
🚀 Starting server initialization...
📦 Modules loaded, environment configured
🔌 Socket.io initialized
✅ MongoDB Connected: ac-uzkdtz2-shard-00-00.qpphvdn.mongodb.net
✅ Seeded dev admin: admin / Admin@123
✅ Seeded dev employee: employee1 / employee123
⚙️  Initializing automation jobs...
✅ Scheduled cleanup job: 0 2 * * * UTC (2 AM daily)
Backend server listening at http://localhost:3002
```

✅ If you see this, everything works!

---

## ⚠️ Troubleshooting

### Issue: "MongoDB Connection Failed"

**Solution:**
1. Check internet connection
2. Verify Mark added your email to cluster
3. Check if cluster status is "Connected" in MongoDB Atlas dashboard
4. Wait 1-2 minutes and try again

### Issue: "Port 3002 Already in Use"

**Solution:**
1. Another backend is already running
2. Find and close the other terminal running `npm start`
3. Or restart your computer
4. Then try again

### Issue: "npm install fails"

**Solution:**
1. Make sure Node.js is installed: `node --version`
2. Try: `npm cache clean --force`
3. Then: `npm install` again

### Issue: "Flutter not found"

**Solution:**
1. Make sure Flutter is installed: `flutter --version`
2. If not installed, download from: https://flutter.dev/docs/get-started/install
3. Add Flutter to PATH environment variable
4. Restart PowerShell
5. Try again: `flutter run`

---

## 🎓 Architecture Overview

```
Your Machine:
┌─────────────────┐
│  Flutter App    │ (21 screens)
│  (Web/Mobile)   │
└────────┬────────┘
         │ API calls
         │ (localhost:3002)
         ▼
┌─────────────────┐
│  Node.js Server │ (Your machine)
│  13 endpoints   │
└────────┬────────┘
         │ Database access
         │ (TLS encrypted)
         ▼
┌─────────────────┐
│  MongoDB Atlas  │ (Cloud)
│  Shared cluster │
└─────────────────┘
```

---

## 📱 API Endpoints Available

**Test with Postman (optional):**

```
Base URL: http://localhost:3002/api

Login:
  POST /users/login
  Body: {"email":"admin@example.com","password":"Admin@123"}

Get Profile:
  GET /users/profile
  Header: Authorization: Bearer <token>

List Users (Admin):
  GET /users
  Header: Authorization: Bearer <token>

Check In:
  POST /attendance/checkin
  Header: Authorization: Bearer <token>
  Body: {"latitude":37.7749,"longitude":-122.4194}
```

---

## 📝 Quick Reference

### Commands You'll Use

```powershell
# Clone repo
git clone https://github.com/ShaqmayBalS/capstone_fieldcheck_2.0.git

# Install backend deps
cd backend && npm install

# Install Flutter deps
cd field_check && flutter pub get

# Start backend
npm start

# Start Flutter app
flutter run -d chrome

# Stop backend
Press Ctrl+C in backend terminal

# Stop Flutter app
Press Ctrl+C in Flutter terminal
```

---

## ✅ Checklist Before Testing

- [ ] MongoDB Atlas account created
- [ ] Mark added you to cluster
- [ ] Repository cloned
- [ ] Backend dependencies installed (`npm install` done)
- [ ] Flutter dependencies installed (`flutter pub get` done)
- [ ] Backend starts without errors
- [ ] Backend shows "MongoDB Connected"
- [ ] Backend listening on port 3002
- [ ] Flutter app starts without errors
- [ ] Can login with test account

---

## 🎯 Testing Objectives

**As a groupmate, you should verify:**

1. ✅ App can start and run
2. ✅ Login works with provided credentials
3. ✅ Admin dashboard loads all features
4. ✅ Employee dashboard shows all tabs
5. ✅ Search/filter works for employees
6. ✅ Geofence map displays correctly
7. ✅ Data persists after restart
8. ✅ No errors in console
9. ✅ App is responsive & fast
10. ✅ All UI looks professional

**Report any issues to Mark!**

---

## 📞 Support

**Questions?**
- Ask Mark Karevin directly
- Check this guide again
- Look in the main project folder for more docs

**Issues?**
- Share the error message with Mark
- Take a screenshot
- Say what you were trying to do

---

## 🎊 What You're Testing

**FieldCheck 2.0** is a GPS-based attendance system with:

- 📱 **Flutter App:** Beautiful 21-screen mobile app
- 🔐 **Secure Auth:** JWT tokens, password hashing
- 📊 **Admin Panel:** Search, filter, bulk operations
- 📍 **Geofencing:** GPS-based location validation
- 👥 **Multi-role:** Admin and employee accounts
- 🔄 **Real-time:** Socket.io for live updates
- ☁️ **Cloud DB:** MongoDB Atlas for data

---

## 🏁 Ready to Test?

1. ✅ Follow setup steps above
2. ✅ Start backend and Flutter app
3. ✅ Login with test account
4. ✅ Test features
5. ✅ Report findings to Mark

**Thank you for testing! Your feedback helps improve the app! 🙏**

---

**Created:** November 13, 2025
**Status:** Ready for groupmates
**Difficulty:** Easy
**Time:** 30 minutes

**Let's test FieldCheck 2.0! 🚀**
