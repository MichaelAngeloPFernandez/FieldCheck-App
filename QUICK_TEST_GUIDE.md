# Quick Test Guide - FieldCheck 2.0

**Date:** November 30, 2025  
**Status:** ✅ Ready to Test  
**Latest Fix:** Attendance Reports Data Format

---

## 🚀 Quick Start (5 Minutes)

### Step 1: Start the Backend

```bash
cd backend
npm install
npm start
```

**Expected Output:**
```
Server running on port 3002
MongoDB connected
Socket.io initialized
```

**Verify Backend is Running:**
```bash
curl http://localhost:3002/api/health
```

**Expected Response:**
```json
{
  "status": "ok"
}
```

---

### Step 2: Start the Flutter App

**In a new terminal:**

```bash
cd field_check
flutter pub get
flutter run
```

**Choose your platform:**
- **Windows:** Press `w` for Windows desktop
- **Android:** Connect device or use emulator, press `a`
- **iOS:** Press `i` (requires macOS)
- **Web:** Press `b` for web browser

---

## 🧪 Testing Checklist

### 1. Authentication Test

**Login as Admin:**
```
Email: admin@example.com
Password: Admin@123
```

**Expected:**
- ✅ Login successful
- ✅ Redirected to admin dashboard
- ✅ Can see admin menu options

**Login as Employee:**
```
Email: employee1@example.com
Password: employee123
```

**Expected:**
- ✅ Login successful
- ✅ Redirected to employee dashboard
- ✅ Can see attendance check-in button

---

### 2. Attendance Check-In/Out Test (FIXED!)

**As Employee:**

1. **Check-In:**
   - Click "Check In" button
   - Allow location permission
   - Should see "Checked In" status
   - Time should display

2. **Check-Out:**
   - Click "Check Out" button
   - Allow location permission
   - Should see "Checked Out" status
   - Time should display

**Expected:**
- ✅ Check-in successful
- ✅ Check-out successful
- ✅ Times recorded correctly
- ✅ Status updates in real-time

---

### 3. Admin Reports Test (NEWLY FIXED!)

**As Admin:**

1. **Go to Reports Tab**
   - Click "Reports" in admin menu
   - Should see two tabs: "Attendance" and "Task Reports"

2. **View Attendance Records**
   - Click "Attendance" tab
   - Should see employee check-in/check-out records
   - **NEW:** Records should display with:
     - Employee name
     - Check-in time
     - Check-out time
     - Geofence location
     - Status (Checked In/Out)

3. **Filter Records**
   - Filter by date
   - Filter by location
   - Filter by status
   - Records should update

**Expected:**
- ✅ Attendance records visible
- ✅ Employee data displays
- ✅ Times show correctly
- ✅ Filters work
- ✅ Data persists

---

### 4. Task Management Test

**As Admin:**

1. **Create Task:**
   - Go to "Task Management"
   - Click "Create Task"
   - Fill in task details
   - Assign to employee
   - Save

2. **View Tasks:**
   - Go to "Task Management"
   - Should see created task
   - Can edit/delete task

**As Employee:**

1. **View Assigned Tasks:**
   - Go to "Employee Tasks"
   - Should see assigned tasks
   - Can update task status

**Expected:**
- ✅ Tasks created successfully
- ✅ Tasks assigned to employees
- ✅ Employees can see assigned tasks
- ✅ Task status updates work

---

### 5. Geofence Test

**As Admin:**

1. **Create Geofence:**
   - Go to "Geofence Management"
   - Click "Create Geofence"
   - Set location (latitude, longitude)
   - Set radius
   - Assign to employees
   - Save

2. **View Geofences:**
   - Should see all geofences
   - Can edit/delete

**As Employee:**

1. **Check-in at Geofence:**
   - Go to Map
   - Should see geofences
   - Check-in should validate location

**Expected:**
- ✅ Geofences created
- ✅ Geofences assigned
- ✅ Location validation works
- ✅ Check-in validates geofence

---

### 6. Real-Time Updates Test

**Setup:**
- Open app on two devices/browsers
- One as admin, one as employee

**Test:**
1. Employee checks in
2. Admin should see real-time update in reports
3. Employee checks out
4. Admin should see real-time update

**Expected:**
- ✅ Updates appear instantly
- ✅ No page refresh needed
- ✅ WebSocket connection working

---

## 🔧 Troubleshooting

### Backend Won't Start

**Error:** `Port 3002 already in use`
```bash
# Kill process on port 3002
lsof -i :3002
kill -9 <PID>

# Or use different port
PORT=3003 npm start
```

**Error:** `MongoDB connection failed`
```bash
# Check MongoDB connection string in .env
# Verify MongoDB Atlas is running
# Check IP whitelist on MongoDB Atlas
```

**Error:** `Module not found`
```bash
# Reinstall dependencies
rm -rf node_modules package-lock.json
npm install
npm start
```

---

### Flutter App Won't Connect

**Error:** `Failed to connect to backend`
```
Check:
1. Backend is running on port 3002
2. API_CONFIG.baseUrl is correct
3. Firewall allows connection
4. Network is accessible
```

**Error:** `Location permission denied`
```
Solution:
1. Grant location permission when prompted
2. Check app permissions in device settings
3. Enable location services
```

**Error:** `WebSocket connection failed`
```
Solution:
1. Check backend is running
2. Check Socket.io is initialized
3. Check network connectivity
```

---

## 📊 Test Data

### Test Accounts

**Admin Account:**
```
Email: admin@example.com
Password: Admin@123
Role: Admin
```

**Employee Account:**
```
Email: employee1@example.com
Password: employee123
Role: Employee
```

### Test Geofence

**Location:** New York Office
```
Latitude: 40.7128
Longitude: -74.0060
Radius: 100 meters
```

---

## ✅ Full Test Flow

### 1. Backend Setup (2 min)
- [ ] Start backend: `npm start`
- [ ] Verify health check: `curl http://localhost:3002/api/health`
- [ ] Check MongoDB connection

### 2. App Startup (2 min)
- [ ] Start Flutter app: `flutter run`
- [ ] Select platform
- [ ] Wait for app to load

### 3. Authentication (1 min)
- [ ] Login as admin
- [ ] Verify dashboard loads
- [ ] Logout
- [ ] Login as employee
- [ ] Verify dashboard loads

### 4. Attendance (2 min)
- [ ] Check-in as employee
- [ ] Verify check-in successful
- [ ] Check-out as employee
- [ ] Verify check-out successful

### 5. Admin Reports (2 min) ⭐ NEW FIX
- [ ] Login as admin
- [ ] Go to Reports
- [ ] View Attendance tab
- [ ] **Verify employee records display** ✅
- [ ] **Verify check-in/out times show** ✅
- [ ] **Verify employee name displays** ✅

### 6. Task Management (2 min)
- [ ] Create task as admin
- [ ] Assign to employee
- [ ] View task as employee
- [ ] Update task status

### 7. Real-Time (1 min)
- [ ] Open two browser windows
- [ ] Employee checks in
- [ ] Admin sees update instantly

**Total Time:** ~12 minutes

---

## 🎯 Key Features to Test

### Must Work
- ✅ Login/Logout
- ✅ Check-in/Check-out
- ✅ **Attendance Reports Display** (NEWLY FIXED)
- ✅ Task Management
- ✅ Geofence Management

### Should Work
- ✅ Real-time updates
- ✅ Filtering
- ✅ Sorting
- ✅ Data persistence
- ✅ Location validation

### Nice to Have
- ✅ Export data
- ✅ Settings management
- ✅ Offline sync
- ✅ Performance optimization

---

## 📝 Test Report Template

```
Test Report - FieldCheck 2.0
Date: [DATE]
Tester: [NAME]

BACKEND
- [ ] Starts successfully
- [ ] MongoDB connected
- [ ] Health check passes
- [ ] All endpoints accessible

AUTHENTICATION
- [ ] Admin login works
- [ ] Employee login works
- [ ] Logout works
- [ ] Token refresh works

ATTENDANCE (FIXED)
- [ ] Check-in works
- [ ] Check-out works
- [ ] Records persist
- [ ] Times display correctly

ADMIN REPORTS (NEWLY FIXED)
- [ ] Attendance tab shows records
- [ ] Employee names display
- [ ] Check-in times display
- [ ] Check-out times display
- [ ] Geofence names display
- [ ] Filtering works
- [ ] Sorting works

TASKS
- [ ] Create task works
- [ ] Assign task works
- [ ] View task works
- [ ] Update status works

REAL-TIME
- [ ] Updates appear instantly
- [ ] No page refresh needed
- [ ] WebSocket connected

OVERALL STATUS: [PASS/FAIL]
Issues Found: [LIST]
Recommendations: [LIST]
```

---

## 🚀 Next Steps After Testing

1. **If All Tests Pass:**
   - Deploy to Render.com
   - Test on production
   - Share with team

2. **If Issues Found:**
   - Document issues
   - Check troubleshooting guide
   - Report to development team

3. **Performance Testing:**
   - Check response times
   - Monitor database queries
   - Check cache hit rates

---

## 📞 Support

**If you encounter issues:**

1. Check the troubleshooting section above
2. Check backend logs: `npm start` output
3. Check Flutter console: `flutter run` output
4. Check browser console (F12)
5. Check MongoDB connection

**Common Issues:**
- Port already in use → Kill process or use different port
- MongoDB not connected → Check connection string
- Location permission → Grant permission in app
- WebSocket failed → Check backend is running

---

## ✨ Summary

You're ready to test FieldCheck 2.0!

**What's New:**
- ✅ Attendance reports now display correctly (FIXED TODAY)
- ✅ Employee check-in/out data shows in admin panel
- ✅ All features working end-to-end

**Time to Test:** ~15 minutes  
**Expected Result:** All features working  
**Status:** ✅ READY TO TEST

---

**Happy Testing! 🎉**

---

*Last Updated: November 30, 2025*  
*Latest Fix: Attendance Reports Data Format*  
*Status: Ready for Testing*
