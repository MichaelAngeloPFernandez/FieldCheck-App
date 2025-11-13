# 🚀 RENDER DEPLOYMENT GUIDE - FieldCheck 2.0

**Status:** Phase 6B - Production Deployment
**Time Required:** 15-20 minutes
**Prerequisites:** ✅ MongoDB Atlas Connected

---

## 📋 What You'll Get

After this guide, your app will be:
- 🌍 Accessible from anywhere (not just localhost)
- 🔒 Secured with HTTPS/SSL
- ⚡ Running 24/7 (never sleeps)
- 📊 With monitoring & logs
- 🔄 Auto-restarts if it crashes

---

## 🎯 Deployment Architecture

```
Your Machine (local dev)
         ↓
   Flutter App ← → Render Backend ← → MongoDB Atlas
                    (Production)       (Cloud DB)
```

---

## ✅ PRE-DEPLOYMENT CHECKLIST

Before starting, verify:

- [x] MongoDB Atlas is connected (✅ Done!)
- [x] Backend runs locally with `npm start` (✅ Done!)
- [x] Login works with admin/employee accounts (✅ Done!)
- [x] GitHub repo is up to date
- [ ] GitHub account ready (create if needed)

---

## 🚀 STEP 1: Connect GitHub Repository

### 1.1 Push Code to GitHub

```powershell
cd C:\Users\Mark_Karevin\Desktop\SCHOOL FILES\flutter works\FIELDCHECK_2.0

# Check git status
git status

# Add all files
git add .

# Commit
git commit -m "Phase 6: MongoDB Atlas connected and verified"

# Push to GitHub
git push origin main
```

### 1.2 Verify on GitHub

1. Go to: https://github.com/ShaqmayBalS/capstone_fieldcheck_2.0
2. Refresh the page
3. You should see your latest commits
4. Verify `.env` is NOT included (check .gitignore)

✅ If you see your code, continue to Step 2

---

## 🎯 STEP 2: Create Render Account

### 2.1 Sign Up

1. Go to: https://render.com
2. Click "Get Started Free"
3. Choose "Sign up with GitHub"
4. Authorize Render to access your GitHub
5. Complete sign-up

### 2.2 Verify Account

- Check email for verification link
- Click the link
- Dashboard should load

✅ You now have a Render account

---

## 🔗 STEP 3: Create Web Service on Render

### 3.1 New Web Service

1. **Dashboard:** Click "New +" button (top right)
2. **Select:** "Web Service"
3. **Connect Repository:**
   - Find: `capstone_fieldcheck_2.0`
   - Click "Connect"

### 3.2 Configure Service

**Name:** `fieldcheck-backend`

**Environment:** 
- Node
- Region: Select your region (closest to you)

**Build Command:**
```
npm install --production
```

**Start Command:**
```
node backend/server.js
```

**Click:** "Create Web Service"

⏳ Render will start building your app (2-3 minutes)

---

## 📝 STEP 4: Set Environment Variables

While Render is building, set up environment variables:

### 4.1 In Render Dashboard

1. **Navigate to:** Settings (left menu)
2. **Scroll to:** Environment Variables
3. **Click:** "Add Environment Variable"

### 4.2 Add Each Variable

**Copy and paste these one at a time:**

```
MONGO_URI
mongodb+srv://karevindp_db_user:SCRAM_MASTER_onetwo345@cluster0.qpphvdn.mongodb.net/fieldcheck?retryWrites=true&w=majority
```

```
JWT_SECRET
your_super_secret_jwt_key_change_this_in_production
```

```
PORT
3002
```

```
NODE_ENV
production
```

```
DISABLE_EMAIL
true
```

```
USE_INMEMORY_DB
false
```

**After adding each, scroll down to save**

---

## ⏳ STEP 5: Wait for Deployment

**In Render Dashboard:**

1. **Go to:** Events tab
2. **Watch the build process:**
   - Building
   - Deploying
   - Live ✅

**Expected time: 3-5 minutes**

Look for message:
```
✅ MongoDB Connected: ac-uzkdtz2-shard-00-00.qpphvdn.mongodb.net
✅ Server running on port 3002
```

---

## 🧪 STEP 6: Test Production Backend

### 6.1 Get Your Render URL

1. **On Render Dashboard** → Your service
2. **Top of page** → You should see a URL like:
   ```
   https://fieldcheck-backend.onrender.com
   ```
3. **Copy this URL** - You'll need it!

### 6.2 Test Login Endpoint

```powershell
$body = @{
    email = "admin@example.com"
    password = "Admin@123"
} | ConvertTo-Json

Invoke-RestMethod `
    -Uri "https://fieldcheck-backend.onrender.com/api/users/login" `
    -Method Post `
    -ContentType "application/json" `
    -Body $body
```

**You should see:**
```json
{
    "user": {
        "email": "admin@example.com",
        "role": "admin"
    },
    "token": "eyJhbGciOiJIUzI1NiIs..."
}
```

✅ If you see this, backend is live!

---

## 📱 STEP 7: Update Flutter App

### 7.1 Update API URL

**File:** `/field_check/lib/config/api_config.dart`

Change:
```dart
static const String baseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:3002',
);
```

To:
```dart
static const String baseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://fieldcheck-backend.onrender.com',
);
```

Or run with environment variable:
```powershell
flutter run --dart-define=API_BASE_URL=https://fieldcheck-backend.onrender.com
```

### 7.2 Test in Flutter

1. **Hot reload** your Flutter app
2. **Try login** with admin credentials
3. **Check if data persists** after restart

✅ If login works, you're connected to production!

---

## 🔐 STEP 8: Security Configuration

### 8.1 Enable HTTPS

✅ **Already enabled on Render!** (Free SSL certificate)

Your URL is automatically:
- `https://fieldcheck-backend.onrender.com`
- Protected with SSL/TLS

### 8.2 Update CORS

If you deploy Flutter web, update `/backend/server.js`:

```javascript
const cors = require('cors');

const corsOptions = {
  origin: [
    'http://localhost:3002',
    'https://fieldcheck-backend.onrender.com',
    'YOUR_FLUTTER_WEB_URL_HERE'
  ],
  credentials: true
};

app.use(cors(corsOptions));
```

---

## 📊 STEP 9: Monitor Your Service

### 9.1 View Logs

In Render Dashboard:
1. **Click:** Logs tab
2. **Watch real-time logs** as requests come in

### 9.2 Set Up Alerts (Optional)

1. **Settings** → Notifications
2. **Enable:** Deploy failure alerts
3. **Enable:** Redeploy on push to main

---

## ⚡ STEP 10: Optimize & Scale

### 10.1 Current Setup (Free Tier)

- Instance Type: Standard (0.5 GB RAM)
- Cold boots if inactive > 15 min
- Can upgrade anytime

### 10.2 Upgrade Options (If Needed)

1. **Pro Plan ($7/month):**
   - Always on (no cold starts)
   - More power
   - Better performance

2. **Better yet:** Keep on free tier for capstone!

---

## 🔄 CONTINUOUS DEPLOYMENT

### Auto-Deploy on GitHub Push

Render can auto-deploy when you push to main:

1. **Render Dashboard** → Settings
2. **Auto-Deploy:** "yes"
3. **Deploy branch:** main
4. **Now:** Any git push triggers auto-deploy

---

## 📋 Deployment Checklist

- [ ] Code pushed to GitHub
- [ ] Render account created
- [ ] Web service created on Render
- [ ] Environment variables set
- [ ] Build successful (Events tab shows ✅)
- [ ] Backend responds to API calls
- [ ] MongoDB Atlas data persists
- [ ] Flutter app updated with new URL
- [ ] Flutter app can login to production backend
- [ ] HTTPS working (https:// not http://)

---

## 🚨 Troubleshooting

### Issue: "Build Failed"

**Solution:**
1. Check Events tab for error message
2. Common issues:
   - Missing `package.json` (should be in root or backend/)
   - Wrong start command
   - Missing dependencies

### Issue: "MongoDB Connection Failed"

**Solution:**
1. Verify MONGO_URI in Render Environment Variables
2. Make sure IP is whitelisted in MongoDB Atlas
3. Check connection string has correct password

### Issue: "Port 3002 Already in Use"

**Solution:**
1. In `/backend/server.js`, port will be `process.env.PORT || 3002`
2. Render sets PORT automatically
3. Should work fine

### Issue: "CORS Error from Flutter"

**Solution:**
1. Make sure `/backend/server.js` has:
   ```javascript
   app.use(cors());
   ```
2. Or whitelist Flutter web URL in CORS options

---

## 🎯 URLs Reference

**After Deployment:**

| Service | URL |
|---------|-----|
| Backend API | https://fieldcheck-backend.onrender.com |
| Login Endpoint | https://fieldcheck-backend.onrender.com/api/users/login |
| MongoDB Database | mongodb+srv://... (Atlas) |
| GitHub Repo | https://github.com/ShaqmayBalS/capstone_fieldcheck_2.0 |

---

## 📞 Support

**Render Docs:** https://render.com/docs
**MongoDB Atlas Docs:** https://docs.mongodb.com/atlas/
**Node.js Hosting:** Render guides at https://render.com/docs/deploy-node

---

## 🎉 Congratulations!

Your FieldCheck 2.0 backend is now deployed to production! 🚀

**What's running:**
- ✅ Backend on Render.com (production)
- ✅ Database on MongoDB Atlas (cloud)
- ✅ Available 24/7 with HTTPS
- ✅ Auto-restarts if crashed

**Next Steps:**
1. Test thoroughly with Flutter app
2. Monitor logs for errors
3. Share URL with classmates for testing
4. Deploy Flutter web (optional)

---

**Deployment Date:** November 13, 2025
**Status:** 🟢 PRODUCTION LIVE
**Render URL:** https://fieldcheck-backend.onrender.com

**Your capstone project is now in production! 🎊**
