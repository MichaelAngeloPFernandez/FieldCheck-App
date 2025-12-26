# 📦 MongoDB Atlas Setup Guide - FieldCheck 2.0

**Status:** Step 1 of 2 (MongoDB, then Render)
**Time Required:** 15-20 minutes
**Difficulty:** Easy

---

## 🎯 What You're Setting Up

Moving from **in-memory MongoDB** (local development) to **MongoDB Atlas** (cloud database):

- Your app will persist data to the cloud ☁️
- Data survives if you restart the backend
- Can be accessed from anywhere
- Free tier is plenty for testing/capstone

---

## ⏱️ Timeline

| Step | Task | Time |
|------|------|------|
| 1 | Create MongoDB Account | 2 min |
| 2 | Create Cluster | 5 min |
| 3 | Create Database User | 3 min |
| 4 | Add IP Address | 2 min |
| 5 | Get Connection String | 2 min |
| 6 | Update Backend Code | 1 min |

**Total: ~15 minutes**

---

## 📋 Step-by-Step Setup

### STEP 1: Create MongoDB Atlas Account

1. **Go to:** https://www.mongodb.com/cloud/atlas
2. **Click:** "Try Free" button
3. **Sign up** using:
   - Email: `mark.karevin@schoolemail.com` (or your email)
   - Password: Create a strong password (save it!)
   - Accept terms
4. **Verify email** - Check inbox for verification link
5. **Click link** to activate account

✅ **You now have a MongoDB account!**

---

### STEP 2: Create Your Cluster

**Inside MongoDB Atlas dashboard:**

1. **Click:** "Build a Cluster"
2. **Choose Tier:** Select **"M0 Cluster"** (Free forever ✅)
3. **Select Cloud Provider:** AWS (default)
4. **Select Region:** 
   - If in USA: `us-east-1`
   - If elsewhere: Choose closest region
5. **Cluster Name:** Type: `fieldcheck-prod`
6. **Click:** "Create Cluster"
7. **Wait 2-5 minutes** for cluster to deploy ⏳

You'll see: "Cluster is being provisioned..." → "Cluster ready!"

✅ **You now have a MongoDB Cluster!**

---

### STEP 3: Create Database User

**In MongoDB Atlas:**

1. **Left Menu:** Click "Database Access"
2. **Click:** "Add New Database User" (green button)
3. **Authentication Method:** Choose "Password"
4. **Username:** `fieldcheck_admin`
5. **Password:** Create strong password (16+ characters recommended)
   - Mix: UPPERCASE, lowercase, numbers, symbols
   - Example: `Secure!Pass123@Admin`
   - **⚠️ SAVE THIS PASSWORD - You'll need it!**
6. **Database User Privileges:** Keep as "Read and Write to any database"
7. **Click:** "Add User"

✅ **You now have a database user!**

---

### STEP 4: Add Your IP Address

**Still in MongoDB Atlas:**

1. **Left Menu:** Click "Network Access"
2. **Click:** "Add IP Address" (green button)
3. **Choose Option:** "Add My Current IP Address"
4. **Description:** `My Development Machine` (optional)
5. **Click:** "Confirm"

You should see your IP address added to the list.

✅ **MongoDB will now accept connections from your computer!**

---

### STEP 5: Get Your Connection String

**Back in MongoDB Atlas:**

1. **Go to:** "Database" → "Clusters" (left menu)
2. **Find your cluster:** `fieldcheck-prod`
3. **Click:** "Connect" button
4. **Choose:** "Connect your application"
5. **Select Driver:** Node.js
6. **Select Version:** 5.6 or later
7. **Click:** Copy button 📋

You'll get something like:
```
mongodb+srv://fieldcheck_admin:<password>@fieldcheck-prod.xxxxx.mongodb.net/?retryWrites=true&w=majority&appName=fieldcheck-prod
```

**⚠️ IMPORTANT:** Replace `<password>` with your actual database password from Step 3!

Example after replacement:
```
mongodb+srv://fieldcheck_admin:Secure!Pass123@Admin@fieldcheck-prod.xxxxx.mongodb.net/?retryWrites=true&w=majority&appName=fieldcheck-prod
```

✅ **You now have your connection string!**

---

## 🔧 STEP 6: Update Your Backend Code

### Option A: Using Environment Variables (Recommended)

**1. Open `/backend/.env`**

Add this line at the top:
```env
MONGODB_URI=mongodb+srv://fieldcheck_admin:<your_password>@fieldcheck-prod.xxxxx.mongodb.net/?retryWrites=true&w=majority&appName=fieldcheck-prod
```

Replace:
- `<your_password>` with your actual password
- `fieldcheck-prod` with your cluster name (if different)
- `xxxxx` with your actual connection string parts

**2. Check `/backend/config/db.js`**

Should look like:
```javascript
const mongoose = require('mongoose');

const connectDB = async () => {
  try {
    const mongoURI = process.env.MONGODB_URI || 'mongodb://localhost:27017/fieldcheck';
    
    await mongoose.connect(mongoURI, {
      useNewUrlParser: true,
      useUnifiedTopology: true,
    });

    console.log('✅ MongoDB connected successfully!');
  } catch (error) {
    console.error('❌ MongoDB connection error:', error.message);
    process.exit(1);
  }
};

module.exports = connectDB;
```

If it doesn't have the `process.env.MONGODB_URI` line, update it to match above. ✅

**3. Check `/backend/server.js`**

Look for where it connects:
```javascript
const connectDB = require('./config/db');
connectDB();
```

It should call `connectDB()` early in the file. ✅

---

### Option B: Direct Connection String (Quick Test)

If you want to test quickly without `.env`:

**Edit `/backend/config/db.js`:**

Replace the `mongoURI` line with:
```javascript
const mongoURI = 'mongodb+srv://fieldcheck_admin:YOUR_PASSWORD@fieldcheck-prod.xxxxx.mongodb.net/?retryWrites=true&w=majority&appName=fieldcheck-prod';
```

**⚠️ Not recommended for production** - passwords exposed in code!

---

## ✅ Testing Your Connection

### Start Your Backend

**Open terminal in `/backend` folder:**

```powershell
npm start
```

You should see:
```
✅ Server running on port 3002
✅ MongoDB connected successfully!
```

If you see ❌ errors, check:
1. MongoDB connection string is correct
2. Password is correct (no special characters escaped wrong)
3. IP address is added to Network Access
4. Cluster is ready (check MongoDB Atlas dashboard)

### Test in Flutter App

**Update `/field_check/lib/config/api_config.dart`:**

Verify it's using `localhost:3002`:
```dart
const String API_BASE_URL = 'http://localhost:3002/api';
```

(This stays the same - backend hasn't moved yet)

**Run Flutter app:**
```powershell
flutter run
```

Try logging in with demo account:
- Email: `admin@example.com`
- Password: `admin123`

✅ If you can log in, MongoDB connection works!

---

## 🔍 Verify Everything

**In MongoDB Atlas dashboard:**

1. **Go to:** Clusters → fieldcheck-prod
2. **Click:** "Collections"
3. **You should see collections like:**
   - users
   - attendance
   - geofences
   - tasks
   - reports
   - etc.

**If you see data here after login/usage:**
- ✅ Backend is writing to MongoDB Atlas
- ✅ Connection string is correct
- ✅ Everything is working!

---

## 🎉 Next Steps

Once MongoDB is connected and working:

1. **Test all features:**
   - Register new user
   - Login
   - Check-in/out
   - View attendance
   - Admin features
   - etc.

2. **When ready for Render:**
   - We'll use this same connection string
   - Render backend will connect to MongoDB Atlas
   - Your Flutter app will talk to Render backend (instead of localhost)

---

## ⚠️ Troubleshooting

### "Connection refused"
- ✅ Check IP address is added to Network Access
- ✅ Verify password is correct (no typos)
- ✅ Wait 5 minutes after creating user

### "Authentication failed"
- ✅ Password has special characters? Make sure they're URL encoded
- ✅ Username is `fieldcheck_admin`? (not email)
- ✅ User has "Read and Write to any database" permission?

### "ENOTFOUND cluster..."
- ✅ Check internet connection
- ✅ Cluster name is correct?
- ✅ MongoDB Atlas dashboard shows "Cluster Ready"?

### "MongoNetworkError"
- ✅ May be network issue - try again in 1 minute
- ✅ Check MongoDB Atlas status page
- ✅ Verify Firewall allows outbound HTTPS (port 443)

---

## 📝 Save These Credentials

**Create a safe file** (don't share!):

```
MONGODB CREDENTIALS
==================
Account Email: [your email]
Account Password: [saved securely]

Database Username: fieldcheck_admin
Database Password: [SAVE THIS SECURELY!]

Connection String: 
mongodb+srv://fieldcheck_admin:[PASSWORD]@fieldcheck-prod.xxxxx.mongodb.net/?retryWrites=true&w=majority&appName=fieldcheck-prod

Cluster Name: fieldcheck-prod
Region: us-east-1
```

**Store securely:**
- ❌ NOT in version control
- ❌ NOT in code files
- ❌ NOT in chat history
- ✅ In `.env` file
- ✅ In a password manager
- ✅ In a secure note

---

## 🎯 Checkpoint

Before moving to Render, confirm:

- [ ] MongoDB Atlas account created
- [ ] Cluster `fieldcheck-prod` ready
- [ ] Database user `fieldcheck_admin` created
- [ ] IP address added to Network Access
- [ ] Connection string obtained
- [ ] Backend `.env` updated with connection string
- [ ] Backend starts without errors (`npm start`)
- [ ] MongoDB shows collections in dashboard
- [ ] Flutter app can login (data persists to MongoDB)
- [ ] All data survives backend restart

**Once all ✅, you're ready for Render!**

---

## 📚 Reference

**MongoDB Atlas Resources:**
- Dashboard: https://cloud.mongodb.com
- Documentation: https://docs.mongodb.com/atlas/
- Pricing: Free M0 cluster forever

**Your Setup:**
- Backend repo: GitHub (connected to Render later)
- Database: MongoDB Atlas (cloud)
- Frontend: Local Flutter (on your machine for now)

---

**Status:** Ready for MongoDB setup! 
**Next:** Once MongoDB works → Move to Render Backend Hosting Guide
**Time until production:** ~45 minutes after this step

Good luck! 🚀
