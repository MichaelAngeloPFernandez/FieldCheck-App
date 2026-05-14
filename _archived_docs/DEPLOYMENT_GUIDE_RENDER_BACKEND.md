# Deploy FieldCheck Backend to Render

## Overview
This guide covers deploying the FieldCheck Node.js backend to Render.com, a PaaS platform with free tier options.

**Deployment Time:** ~10 minutes  
**Downtime:** None (fresh deployment)  
**Cost:** Free tier available ($7/month for production)

---

## Prerequisites

✅ Backend code ready (all services implemented)  
✅ MongoDB Atlas database (already configured)  
✅ Render.com account (free tier available)  
✅ GitHub repo (connected to Render for auto-deploy)

---

## Step 1: Prepare Backend for Production

### 1.1 Verify Package.json Start Script
```bash
cd backend
cat package.json | grep -A 5 '"scripts"'
```

✅ Expected output:
```json
"start": "node server.js"
```

### 1.2 Create `.env.production` Template
```bash
# backend/.env.production (for reference, don't commit!)
NODE_ENV=production
PORT=3002
MONGO_URI=mongodb+srv://karevindp_db_user:Password730123@cluster0.qpphvdn.mongodb.net/fieldcheck?retryWrites=true&w=majority&appName=Cluster0
JWT_SECRET=<generate-a-random-string>
JWT_REFRESH_SECRET=<generate-another-random-string>
EMAIL_HOST=smtp.gmail.com
EMAIL_PORT=587
EMAIL_USERNAME=perfectomark077@gmail.com
EMAIL_PASSWORD=ebwk iesi jfpg qlzh
EMAIL_FROM=perfectomark077@gmail.com
FRONTEND_URL=https://fieldcheck-app.onrender.com
DISABLE_EMAIL=false
USE_INMEMORY_DB=false
```

### 1.3 Generate Secure Secrets
```bash
# Generate random JWT secrets (use one of these in Render dashboard)
node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
```

Save these values for Step 3.

---

## Step 2: Push to GitHub

### 2.1 Commit All Changes
```bash
cd FieldCheck-App
git add -A
git commit -m "chore: prepare backend for Render deployment"
git push origin main
```

### 2.2 Verify GitHub Repo
- Go to https://github.com/YourUsername/FieldCheck-App
- ✅ Verify `backend/` folder exists with all files
- ✅ Verify `backend/render.yaml` exists
- ✅ Verify `backend/package.json` has start script

---

## Step 3: Create Render Deployment

### 3.1 Login to Render
1. Go to https://render.com
2. Sign up or login with GitHub
3. **Click "New +" → "Web Service"**

### 3.2 Connect GitHub Repo
1. **Select repository:** `YourUsername/FieldCheck-App`
2. **Select branch:** `main`
3. **Click "Connect"**

### 3.3 Configure Web Service
Fill in the form with these values:

| Field | Value |
|-------|-------|
| Name | `fieldcheck-backend` |
| Root Directory | `backend` |
| Runtime | `Node` |
| Build Command | `npm install` |
| Start Command | `npm start` |
| Plan | `Free` or `Standard` ($7/mo) |
| Region | `Oregon` (closest to you) |

**⚠️ Important:** Set Root Directory to `backend` so Render deploys from the backend folder.

### 3.4 Add Environment Variables

**Click "Add Environment Variable" for each:**

| Key | Value | Secret |
|-----|-------|--------|
| `NODE_ENV` | `production` | ✓ Copy |
| `PORT` | `3002` | ✓ Copy |
| `MONGO_URI` | `mongodb+srv://karevindp_db_user:Password730123@cluster0.qpphvdn.mongodb.net/fieldcheck?retryWrites=true&w=majority&appName=Cluster0` | ✓ Secret |
| `JWT_SECRET` | `<from Step 2.3 - first random string>` | ✓ Secret |
| `JWT_REFRESH_SECRET` | `<from Step 2.3 - second random string>` | ✓ Secret |
| `EMAIL_HOST` | `smtp.gmail.com` | ✓ Copy |
| `EMAIL_PORT` | `587` | ✓ Copy |
| `EMAIL_USERNAME` | `perfectomark077@gmail.com` | ✓ Secret |
| `EMAIL_PASSWORD` | `ebwk iesi jfpg qlzh` | ✓ Secret |
| `EMAIL_FROM` | `perfectomark077@gmail.com` | ✓ Copy |
| `FRONTEND_URL` | `https://fieldcheck-app.onrender.com` | ✓ Copy |
| `DISABLE_EMAIL` | `false` | ✓ Copy |
| `USE_INMEMORY_DB` | `false` | ✓ Copy |

**🔐 Make sure to mark sensitive values as "Secret"**

### 3.5 Click "Create Web Service"

Render will now:
1. ✅ Clone your GitHub repo
2. ✅ Install dependencies (`npm install`)
3. ✅ Start the server (`npm start`)
4. ✅ Assign a URL like `https://fieldcheck-backend.onrender.com`

**Deployment takes 3-5 minutes.** You'll see logs in real-time.

---

## Step 4: Verify Deployment

### 4.1 Check Health Endpoint
```bash
# Replace with your Render URL
curl https://fieldcheck-backend.onrender.com/api/health

# Expected response:
# {"status":"ok","message":"FieldCheck API v1.0","timestamp":"2026-04-26T..."}
```

### 4.2 Check Server Logs
1. Go to Render Dashboard
2. **Select "fieldcheck-backend"**
3. **Click "Logs"** tab
4. Look for: `✅ Server running on port 3002`
5. Look for: `✅ MongoDB connected`

### 4.3 Test API Endpoint (Database Connection)
```bash
# Test authentication
curl -X POST https://fieldcheck-backend.onrender.com/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "email":"test@example.com",
    "password":"TestPassword123!",
    "name":"Test User"
  }'

# Expected: 201 Created or validation error (not 500)
```

---

## Step 5: Update Frontend for Production

### 5.1 Update Flutter API Base URL
**File:** `field_check/lib/services/api_client.dart`

Replace:
```dart
static const String baseURL = 'http://localhost:5000';
```

With:
```dart
static const String baseURL = 'https://fieldcheck-backend.onrender.com';
```

### 5.2 Rebuild Flutter App
```bash
cd field_check
flutter clean
flutter pub get
flutter build apk --release
```

---

## Step 6: Enable Auto-Deployment

### 6.1 GitHub Integration (Already Configured)
Render automatically redeploys when you push to `main` branch.

### 6.2 Manual Redeployment (If Needed)
1. Go to Render Dashboard
2. **Select "fieldcheck-backend"**
3. **Click "Manual Deploy"** button (top right)

---

## Troubleshooting

### Issue: "Build Failed"
**Solution:**
1. Check Render logs for error
2. Most common: Missing environment variables
3. Add missing vars and click "Manual Deploy"

### Issue: "MongoDB Connection Failed"
**Solution:**
```
1. Verify MONGO_URI is correct
2. In MongoDB Atlas:
   - Go to Network Access
   - Add IP: 0.0.0.0/0 (allows all - for testing)
   - Or add Render's IP range
```

### Issue: "Port Already in Use"
**Solution:** Render manages ports automatically. Just ensure `PORT` env var is set.

### Issue: "Cannot reach API"
**Solution:**
1. Check server is running: `curl https://fieldcheck-backend.onrender.com`
2. Check CORS settings in backend (currently `*` - all origins allowed)
3. Check firewall isn't blocking

---

## Environment Variables Reference

| Variable | Purpose | Example |
|----------|---------|---------|
| `NODE_ENV` | Production flag | `production` |
| `PORT` | Server port | `3002` |
| `MONGO_URI` | Database URL | MongoDB Atlas connection string |
| `JWT_SECRET` | Token signing key | 64-char random string |
| `JWT_REFRESH_SECRET` | Refresh token key | 64-char random string |
| `EMAIL_HOST` | SMTP server | `smtp.gmail.com` |
| `EMAIL_PORT` | SMTP port | `587` |
| `EMAIL_USERNAME` | SMTP username | Your Gmail |
| `EMAIL_PASSWORD` | SMTP password | App-specific password |
| `EMAIL_FROM` | From address | Your Gmail |
| `FRONTEND_URL` | Client URL | `https://fieldcheck-app.onrender.com` |
| `DISABLE_EMAIL` | Disable emails | `false` |
| `USE_INMEMORY_DB` | Use test DB | `false` |

---

## Performance Optimization (Optional)

### Enable Caching
```bash
# In Render Dashboard: Environment Variables
REDIS_URL=redis://your-redis-url
```

### Upgrade from Free Tier
Free tier: ~100 free hours/month  
Recommended: **Standard** ($7/month) = unlimited hours + better performance

---

## Monitoring

### View Live Logs
```bash
# Real-time log streaming (in Render Dashboard)
Logs tab → Auto-refresh enabled
```

### Set Up Alerts
1. Render Dashboard → Settings
2. Enable email alerts for:
   - Deployment failed
   - Service down
   - Build failed

---

## Security Checklist

- ✅ JWT secrets are randomly generated (32+ chars)
- ✅ Sensitive vars marked as "Secret" in Render
- ✅ MongoDB IP whitelist allows Render (0.0.0.0/0)
- ✅ HTTPS enabled (Render provides free SSL)
- ✅ CORS configured (currently `*` - refine for production)
- ✅ Email credentials are app-specific password

---

## Next Steps

1. ✅ **Backend deployed to Render**
2. ⏳ **Update Flutter app with production API URL**
3. ⏳ **Build and test Flutter APK**
4. ⏳ **Deploy Flutter app to Google Play / Apple App Store**

---

## Deployment Summary

| Step | Status | Time |
|------|--------|------|
| 1. Prepare backend | ✅ | 2 min |
| 2. Push to GitHub | ✅ | 1 min |
| 3. Create Render service | ⏳ | 5 min |
| 4. Verify deployment | ⏳ | 2 min |
| 5. Update Flutter | ⏳ | 5 min |
| 6. Test integration | ⏳ | 5 min |
| **Total** | | **~20 min** |

---

## Render Dashboard URLs

After deployment, you'll have:

- **Backend API:** `https://fieldcheck-backend.onrender.com`
- **Health Check:** `https://fieldcheck-backend.onrender.com/api/health`
- **Render Dashboard:** `https://dashboard.render.com`

---

## References

- Render Docs: https://render.com/docs
- Node.js Deployment: https://render.com/docs/node-js
- MongoDB Atlas: https://docs.atlas.mongodb.com/
- JWT Best Practices: https://tools.ietf.org/html/rfc8725

---

**You're ready to deploy! 🚀**

Questions? Check Render logs for detailed error messages.
