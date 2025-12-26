# 🔧 MongoDB Connection Setup - FINAL STEP

## ⚠️ IMPORTANT: Add Your Database Password

Your connection string has a placeholder that needs your actual password:

```
mongodb+srv://karevindp_db_user:<db_password>@cluster0.qpphvdn.mongodb.net/
```

### Step 1: Update `.env` with Your Password

**File:** `/backend/.env`

Replace `<db_password>` with your actual MongoDB database password:

```env
MONGO_URI=mongodb+srv://karevindp_db_user:YOUR_PASSWORD_HERE@cluster0.qpphvdn.mongodb.net/fieldcheck?retryWrites=true&w=majority
```

**Example:**
```env
MONGO_URI=mongodb+srv://karevindp_db_user:MySecure123Pass!@cluster0.qpphvdn.mongodb.net/fieldcheck?retryWrites=true&w=majority
```

⚠️ **If your password has special characters:**
- `!` → `%21`
- `@` → `%40`
- `#` → `%23`
- `$` → `%24`
- `%` → `%25`
- `&` → `%26`

For example, if password is `MyPass@123!`:
```env
MONGO_URI=mongodb+srv://karevindp_db_user:MyPass%40123%21@cluster0.qpphvdn.mongodb.net/fieldcheck?retryWrites=true&w=majority
```

### Step 2: Verify Current `.env`

Your `.env` should now look like:
```env
MONGO_URI=mongodb+srv://karevindp_db_user:<YOUR_PASSWORD>@cluster0.qpphvdn.mongodb.net/fieldcheck?retryWrites=true&w=majority
JWT_SECRET=your_super_secret_jwt_key_change_this_in_production
DISABLE_EMAIL=true
SEED_DEV=true
EMAIL_SECURE=false
PORT=3002
USE_INMEMORY_DB=false
```

### Step 3: Start Backend & Test

```powershell
cd backend
npm start
```

You should see:
```
✅ MongoDB Connected: cluster0.mongodb.com
✅ Server running on port 3002
```

### Step 4: Test Login

**In Flutter app or Postman:**
- Email: `admin@example.com`
- Password: `admin123`

If login works → ✅ MongoDB is connected!

---

## 📝 Your Connection Details (Save Securely!)

```
Username: karevindp_db_user
Cluster: cluster0.qpphvdn.mongodb.net
Database: fieldcheck
Connection String: mongodb+srv://karevindp_db_user:<password>@cluster0.qpphvdn.mongodb.net/fieldcheck?retryWrites=true&w=majority
```

---

**Next Step:** Paste your MongoDB password in the `.env` file above and run `npm start`!
