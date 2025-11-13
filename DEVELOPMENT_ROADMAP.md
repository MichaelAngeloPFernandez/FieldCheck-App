# FieldCheck 2.0 - Complete Development Roadmap

## 🎓 Capstone Project Overview
**"Self-Hosted GPS and Geofencing Attendance Verification System for Field-Based Workforce Management"**

### Current Status: ✅ FOUNDATION COMPLETE
- ✅ Backend API Running (localhost:3002)
- ✅ MongoDB In-Memory Setup (Dev)
- ✅ All Auth Endpoints Tested & Working
- ✅ Flutter Linting 100% Fixed (0 errors)
- ⏳ Next: Automate & Enhance

---

## 📋 Development Phases

### **PHASE 1: Automate Email Verification (THIS WEEK)**
**Goal:** Ensure users must verify email before login, auto-clean unverified accounts

#### Tasks:
1. ✅ Review current `userController.js` (Done - email verification working)
2. ⏳ Add `node-cron` to auto-delete unverified users after 24 hours
3. ⏳ Test verification flow end-to-end
4. ⏳ Create verification email enhancement

**Backend Files to Modify:**
- `backend/utils/seedDev.js` - Add cron job initialization
- `backend/server.js` - Initialize cron jobs on startup

**Why This First:** Email verification is the security foundation. Must be solid before adding Google OAuth.

---

### **PHASE 2: Password Recovery Flow (WEEK 2)**
**Goal:** Users can request password reset via email, reset with token

#### Tasks:
1. ✅ Backend endpoints exist (`/forgot-password`, `/reset-password/:token`)
2. ⏳ Create Flutter "Forgot Password Screen"
3. ⏳ Create Flutter "Reset Password Screen"
4. ⏳ Test end-to-end with email tokens
5. ⏳ Add password strength validation

**Flutter Files to Create:**
- `lib/screens/forgot_password_screen.dart`
- `lib/screens/reset_password_screen.dart`

**Backend Files:**
- Review: `userController.js` - forgotPassword & resetPassword functions

---

### **PHASE 3: Google OAuth2 Integration (WEEK 3)**
**Goal:** Add "Sign in with Google" for both admin and employees

#### Prerequisites:
- Google Cloud Project created
- OAuth2 credentials obtained (Client ID + Secret)
- Credentials added to `.env`

#### Tasks:
1. ⏳ Create `backend/utils/googleAuth.js` - Passport configuration
2. ⏳ Create OAuth routes in `backend/routes/authRoutes.js`
3. ⏳ Integrate `flutter_google_signin` package
4. ⏳ Create Google login UI button in Flutter
5. ⏳ Test Google authentication flow

**Backend Files to Create:**
- `backend/utils/googleAuth.js` - Passport Google OAuth setup
- New routes: `/api/auth/google/callback`, `/api/auth/google/verify`

**Flutter Files to Create:**
- Google Sign-In integration in `lib/services/user_service.dart`
- Google login button in `lib/screens/login_screen.dart`

---

### **PHASE 4: Admin User Management (WEEK 4)**
**Goal:** Admins can view, manage, delete, deactivate users

#### Tasks:
1. ✅ Backend endpoints exist (all tested)
2. ⏳ Create `lib/screens/admin_users_list_screen.dart`
3. ⏳ Create `lib/screens/admin_user_detail_screen.dart`
4. ⏳ Create user search/filter functionality
5. ⏳ Create bulk user import feature
6. ⏳ Add role change functionality

**Flutter Files to Create:**
- `lib/screens/admin_users_list_screen.dart`
- `lib/screens/admin_user_detail_screen.dart`
- `lib/screens/admin_import_users_screen.dart`

---

### **PHASE 5: Auth State Management (WEEK 5)**
**Goal:** Users stay logged in across app restarts, automatic token refresh

#### Tasks:
1. ⏳ Add `provider` package to `pubspec.yaml`
2. ⏳ Create `lib/providers/auth_provider.dart` - Manages login state
3. ⏳ Create `lib/screens/splash_screen.dart` - Check auth on app start
4. ⏳ Implement secure token storage (`flutter_secure_storage`)
5. ⏳ Add JWT token refresh mechanism

**Flutter Files to Create:**
- `lib/providers/auth_provider.dart`
- `lib/screens/splash_screen.dart`

**Flutter Files to Modify:**
- `lib/main.dart` - Use auth provider at app root
- `lib/screens/login_screen.dart` - Use provider for login state

---

### **PHASE 6: Production Deployment (WEEK 6)**
**Goal:** Deploy to Render or Railway with MongoDB Atlas

#### Tasks:
1. ⏳ Create MongoDB Atlas account + cluster
2. ⏳ Create Render/Railway account
3. ⏳ Set up environment variables on hosting platform
4. ⏳ Deploy backend to Render/Railway
5. ⏳ Configure GitHub auto-deploy
6. ⏳ Update Flutter API config to production URL
7. ⏳ Test production endpoints

**Configuration:**
- Create `.env.production` template
- Document all required environment variables
- Create deployment guide

---

### **PHASE 7: Production Testing & Hardening (WEEK 7)**
**Goal:** Ensure everything works in production

#### Tasks:
1. ⏳ Test all auth flows with production backend
2. ⏳ Verify email verification works (Nodemailer + Gmail)
3. ⏳ Test Google OAuth in production
4. ⏳ Verify admin functions work
5. ⏳ Load testing & performance optimization
6. ⏳ Security audit

---

## 🛠️ Current Backend Structure

```
backend/
├── server.js ........................ Express + Socket.io setup
├── package.json ..................... Dependencies
├── .env .............................. Environment config
│
├── config/
│   └── db.js ........................ MongoDB connection
│
├── models/
│   └── User.js ...................... User schema (verified, role-based)
│
├── controllers/
│   └── userController.js ............ 13 auth functions (TESTED ✅)
│
├── routes/
│   └── userRoutes.js ................ Auth endpoints (TESTED ✅)
│
├── middleware/
│   ├── authMiddleware.js ............ JWT protection + role checks
│   └── errorMiddleware.js ........... Error handling
│
├── utils/
│   ├── emailService.js ............. Nodemailer configuration
│   ├── generateToken.js ............ JWT generation
│   ├── seedDev.js .................. Demo data seeding
│   └── templates/
│       ├── accountActivationEmail.js
│       └── passwordResetEmail.js
│
└── services/
    └── (to be implemented)
```

---

## 🧪 Tested API Endpoints

### ✅ User Authentication
- `POST /api/users/login` - Login by email/username/identifier
- `POST /api/users` - Register new user
- `GET /api/users/verify/:token` - Verify email with token
- `POST /api/users/forgot-password` - Request password reset
- `POST /api/users/reset-password/:token` - Reset password with token

### ✅ User Profile
- `GET /api/users/profile` - Get current user profile (protected)
- `PUT /api/users/profile` - Update user profile (protected)

### ✅ Admin Functions
- `GET /api/users` - Get all users (admin only)
- `PUT /api/users/:id` - Update user by admin (admin only)
- `PUT /api/users/:id/deactivate` - Deactivate user (admin only)
- `PUT /api/users/:id/reactivate` - Reactivate user (admin only)
- `DELETE /api/users/:id` - Delete user (admin only)
- `POST /api/users/import` - Bulk import users (admin only)

---

## 📦 Demo Accounts (Current)

| Role | Username/Email | Password | Purpose |
|------|---|---|---|
| Admin | admin@example.com | Admin@123 | Test admin features |
| Employee | employee1 | employee123 | Test employee features |
| Employee | employee2 | employee1234 | Additional test account |
| Employee | employee3 | employee12345 | Additional test account |
| Employee | employee4 | employee123456 | Additional test account |
| Employee | employee5 | employee1234567 | Additional test account |

---

## 🚀 Quick Reference: Terminal Commands

### Backend Startup
```bash
cd backend
npm install              # Install dependencies
npm start                # Start server (localhost:3002)
```

### Backend Testing (PowerShell)
```powershell
# Test admin login
$body = @{identifier='admin@example.com'; password='Admin@123'} | ConvertTo-Json
Invoke-WebRequest -Uri 'http://localhost:3002/api/users/login' -Method POST `
  -Headers @{'Content-Type'='application/json'} -Body $body -ErrorAction Stop
```

### Flutter Testing
```bash
cd field_check
flutter pub get          # Install packages
flutter run -d android   # Android
flutter run -d chrome    # Web browser
flutter run -d windows   # Windows (requires VS)
```

---

## 🎯 NEXT IMMEDIATE ACTIONS

### Right Now (Next 30 mins):
1. ✅ Review this roadmap
2. ⏳ Decide: Automate email verification OR password recovery flow first?
3. ⏳ Get confirmation on Google OAuth timeline (when you have GCP credentials)

### Today:
- [ ] Implement Phase 1: Auto-delete unverified users after 24h
- [ ] Implement Phase 2: Password recovery Flutter screens
- [ ] Test both flows end-to-end

### This Week:
- [ ] Complete Phases 1-3
- [ ] Have Google OAuth ready
- [ ] Admin management screens functional

### Production Ready:
- [ ] All phases complete
- [ ] Deployed to Render/Railway
- [ ] MongoDB Atlas connected
- [ ] Email verification working with real Gmail
- [ ] Google OAuth integrated and tested

---

## 📝 Notes & Dependencies

### Already Installed ✅
- express, mongoose, dotenv
- bcryptjs, jsonwebtoken
- nodemailer, express-async-handler
- socket.io, uuid, helmet, cors
- express-rate-limit, compression, morgan

### Need to Install ⏳
- `node-cron` - Auto-delete unverified users
- `passport`, `passport-google-oauth20` - Google OAuth

### Flutter Packages ⏳
- `provider` - State management
- `flutter_secure_storage` - Secure token storage
- `google_sign_in` - Google authentication

---

## 🤝 Communication Format

When I say **"Continue"**, I will:
1. Pick up from the last completed task
2. Ask which file/folder you're in
3. Provide exact code to paste
4. Give terminal commands to test
5. Wait for your confirmation before moving on

You say **"Continue"** when:
1. ✅ Current task is working
2. ✅ Tests pass
3. ✅ Ready for next phase

---

**Let's Build This! 🚀**
