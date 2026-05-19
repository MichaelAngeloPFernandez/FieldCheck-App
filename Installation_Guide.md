# 🛠️ FieldCheck 2.0 - Complete Installation & Deployment Guide

This guide provides step-by-step instructions to install, configure, run, and compile the **FieldCheck 2.0** GPS-based geofencing attendance verification system.

---

## 📋 Table of Contents
1. [Prerequisites](#1-prerequisites)
2. [Database Setup (MongoDB Atlas)](#2-database-setup-mongodb-atlas)
3. [Backend Setup (Node.js)](#3-backend-setup-nodejs)
4. [Frontend Setup (Flutter)](#4-frontend-setup-flutter)
5. [Compiling the App (EXE and APK)](#5-compiling-the-app-exe-and-apk)
6. [Troubleshooting](#6-troubleshooting)

---

## 1. Prerequisites

Ensure the following tools are installed on your development machine:

*   **Node.js**: Version `20.x` or higher (includes `npm`).
*   **Flutter SDK**: Version `3.9` or higher.
*   **Dart SDK**: Included with the Flutter SDK.
*   **Java Development Kit (JDK)**: Version `17` or higher (required for Android builds).
*   **Android Studio / Android SDK**: Required for compilation of the Android client (`.apk`).
*   **Visual Studio 2022**: With the "Desktop development with C++" workload installed (required for compiling the Windows client `.exe`).
*   **Git**: For version control and cloning.

---

## 2. Database Setup (MongoDB Atlas)

FieldCheck 2.0 uses **MongoDB Atlas** (cloud-hosted database) for secure data persistence.

1.  Sign in to [MongoDB Atlas](https://cloud.mongodb.com).
2.  Create a new shared database cluster (Free Tier is sufficient).
3.  Under **Database Access**, create a database user with read/write permissions. Keep the username and password handy.
4.  Under **Network Access**, add an IP address rule to allow access (use `0.0.0.0/0` to allow connection from anywhere during development/testing).
5.  Click on your Database Cluster and choose **Connect** -> **Drivers**. Copy the connection string (URI). It will look similar to this:
    ```
    mongodb+srv://<username>:<password>@cluster0.abcde.mongodb.net/fieldcheck?retryWrites=true&w=majority
    ```
6.  Replace `<username>` and `<password>` with the credentials of the database user you created in Step 3.

---

## 3. Backend Setup (Node.js)

The backend provides the API endpoints for user authentication, geofencing coordinates verification, real-time sync via WebSockets, email notifications, and task assignments.

### Step 1: Install Dependencies
Open a terminal in the root project directory and navigate to the backend folder:
```powershell
cd backend
npm install
```

### Step 2: Configure Environment Variables
Create a file named `.env` in the `backend` directory (you can copy the contents of `.env.example` as a template):
```powershell
# Copy template
cp .env.example .env
```

Open `.env` in a text editor and configure the keys:
```env
# MongoDB connection string from MongoDB Atlas
MONGO_URI=mongodb+srv://<username>:<password>@cluster0.abcde.mongodb.net/fieldcheck?retryWrites=true&w=majority

# Secret key for signing JSON Web Tokens (JWT) - use a strong random string
JWT_SECRET=your_super_secret_jwt_key_here

# Mode environment (development or production)
NODE_ENV=development

# Server port configuration
PORT=3002

# Email client settings (Nodemailer)
DISABLE_EMAIL=false
EMAIL_SECURE=false

# Optional database features
USE_INMEMORY_DB=false
SEED_DEV=false
```

### Step 3: Run the Backend
You can run the backend in development mode (which automatically restarts on code changes using `nodemon`) or in standard production mode:

*   **Development Mode:**
    ```powershell
    npm run dev
    ```
*   **Production/Standard Mode:**
    ```powershell
    npm start
    ```

The backend server will start and listen on the configured port (default is `3002`). You should see a message indicating a successful connection to MongoDB.

---

## 4. Frontend Setup (Flutter)

The frontend is a cross-platform client built using Flutter. It contains both the **Administrator Dashboard** and the **Employee Mobile Portal**.

### Step 1: Install Dependencies
Open a terminal in the project root and navigate to the `field_check` directory:
```powershell
cd field_check
flutter pub get
```

### Step 2: Local Run / Testing
To run the Flutter app locally on an emulator, connected physical device, or browser, run the following:

*   **Run on Local Backend (Development):**
    ```powershell
    flutter run --dart-define=USE_LOCAL_BACKEND=true
    ```
*   **Run on Production Cloud Backend:**
    ```powershell
    flutter run
    ```
    *(Note: By default, the application connects to the deployed Render endpoint if `USE_LOCAL_BACKEND` is not set.)*

---

## 5. Compiling the App (EXE and APK)

Because the system is designed to serve two roles, building separate target executables makes deployment easier:

1.  **For Administrators (EXE/Web)**: Admins work on desktops to manage geofences, view maps, and download reports. Building a **Windows Desktop Executable (`.exe`)** is recommended for admin usage.
2.  **For Employees (APK)**: Employees use mobile devices on-site to check in/out and view tasks. Building an **Android Package (`.apk`)** is recommended for employee usage.

### A. Compile Windows Executable (.exe) for Admins

To compile the Windows desktop client:

1.  Ensure you have Visual Studio 2022 with C++ desktop tools installed.
2.  In the `field_check` directory, run the compile command:
    *   **Connecting to Local Backend:**
        ```powershell
        flutter build windows --release --dart-define=USE_LOCAL_BACKEND=true
        ```
    *   **Connecting to Production Cloud Backend:**
        ```powershell
        flutter build windows --release --dart-define=API_BASE_URL=https://fieldcheck-app-mwk3.onrender.com
        ```
3.  Once the build completes, your desktop executable (`field_check.exe`) and its supporting files will be located in:
    ```
    field_check/build/windows/x64/runner/Release/
    ```
    *To distribute the Windows app, zip the entire `Release` folder. The application requires all `.dll` and data files in that folder to run.*

### B. Compile Android APK (.apk) for Employees

To compile the Android mobile client:

1.  Ensure you have the Android SDK and JDK 17 installed.
2.  In the `field_check` directory, run the compile command:
    *   **Connecting to Local Backend:**
        ```powershell
        flutter build apk --release --dart-define=USE_LOCAL_BACKEND=true
        ```
    *   **Connecting to Production Cloud Backend:**
        ```powershell
        flutter build apk --release --dart-define=API_BASE_URL=https://fieldcheck-app-mwk3.onrender.com
        ```
3.  Once the build completes, the compiled installable APK (`app-release.apk`) will be located in:
    ```
    field_check/build/app/outputs/flutter-apk/app-release.apk
    ```
    *This APK file can be transferred to and installed directly on any Android device.*

---

## 6. Troubleshooting

### 1. Flutter Build Windows fails
*   **Cause**: Visual Studio C++ build tools are missing or outdated.
*   **Fix**: Open the **Visual Studio Installer**, click **Modify** on Visual Studio 2022, and verify that **Desktop development with C++** is checked. Run `flutter doctor` to confirm Flutter detects the tools.

### 2. MongoDB connection timeout on Backend start
*   **Cause**: The current IP address is not whitelisted in MongoDB Atlas.
*   **Fix**: Log into MongoDB Atlas, go to **Network Access**, and add `0.0.0.0/0` (allow access from anywhere) or whitelist your current public IP address.

### 3. Emulator cannot connect to localhost backend (`127.0.0.1`)
*   **Cause**: Android emulators refer to the host machine's localhost as `10.0.2.2`, not `127.0.0.1`.
*   **Fix**: Run the build with a custom define pointing to `10.0.2.2`:
    ```powershell
    flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3002
    ```
