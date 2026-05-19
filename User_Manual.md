# 📖 FieldCheck 2.0 - System User Manual

Welcome to the **FieldCheck 2.0** User Manual. This manual provides instructions on how to use the web, desktop, and mobile portals of the GPS-Based Geofencing Attendance Verification and Workforce Management System.

---

## 📋 Table of Contents
1. [Overview & Access Credentials](#1-overview--access-credentials)
2. [Client Support Ticket Portal (Public Access)](#2-client-support-ticket-portal-public-access)
3. [Employee Portal (Mobile App)](#3-employee-portal-mobile-app)
4. [Administrator Portal (Desktop App)](#4-administrator-portal-desktop-app)
5. [Client Installation & Access Guide (APK & EXE)](#5-client-installation--access-guide-apk--exe)

---

## 1. Overview & Access Credentials

FieldCheck 2.0 is divided into three access levels:
*   **Public Clients**: Access the public page to file support tickets and trace ticket status.
*   **Field Employees**: Log in via mobile app to perform GPS-verified check-ins/check-outs, submit field comments, and complete tasks.
*   **Administrators**: Log in via desktop/web application to manage geofences, track attendance, assign tasks, review reports, and handle client support tickets.

### Default Login Accounts for Testing:
*   **Administrator Account:**
    *   **Email:** `admin@example.com`
    *   **Password:** `Admin@123`
*   **Employee Account:**
    *   **Email:** `employee1@example.com`
    *   **Password:** `employee123`

---

## 2. Client Support Ticket Portal (Public Access)

Clients can request services (e.g., equipment check, maintenance, or cleaning) and monitor ticket progression.

### A. Submitting a Support Ticket
1.  Open the application landing page.
2.  Click on the **Submit Support Ticket** button.
3.  Fill in the required information:
    *   **Full Name**
    *   **Email Address**
    *   **Service Type** (select from dropdown: e.g., Maintenance, Cleaning, IT Support)
    *   **Description** (details of the request)
4.  Click **Submit Ticket**.
5.  An email will be sent containing your unique **Ticket Number** (e.g., `TK-10023`) and a tracking token.

### B. Tracking & Feedback
1.  On the landing page, enter your **Ticket Number** into the tracking field.
2.  You will see the live status of your ticket (e.g., `Pending`, `In Progress`, `Completed`), along with notes from the technician.
3.  Once the technician marks the ticket as **Completed**, you can write a follow-up comment and select a rating (1 to 5 stars) to submit feedback directly from the page.

---

## 3. Employee Portal (Mobile App)

Field employees use the mobile client to log attendance and task completion.

### A. Logging In
1.  Launch the FieldCheck mobile app.
2.  Select **Employee Login** on the login portal.
3.  Enter your employee credentials and log in.

### B. Checking In / Checking Out
Attendance is strictly verified using server-side GPS geofencing (Haversine formula calculation).

1.  Upon logging in, the home dashboard shows your **Assigned Geofence** (e.g., *Headquarters*, *Branch Office A*).
2.  The application displays your **live distance** in meters from the geofence boundary.
3.  **To Check In:**
    *   Walk inside the assigned geofence zone (within the radius boundary).
    *   Once you are inside the boundary, the **Check In** button will activate (turn green). Click it.
    *   Your status changes to "Checked In", and your check-in timestamp is securely saved.
4.  **To Check Out:**
    *   At the end of your shift, click the **Check Out** button.
    *   Your checkout timestamp is logged, and the application calculates your total duration.

### C. Viewing and Completing Tasks
1.  Go to the **My Tasks** tab in the bottom navigation.
2.  You will see a list of tasks assigned to you by the Admin (e.g., *Inspect air conditioning*, *Verify stock inventory*).
3.  Tap a task to view the details (description, due date, target geofence).
4.  To update progress:
    *   Click **Start Task** (changes status to *In Progress*).
    *   Once the task is complete, click **Mark Completed**. You can optionally attach photos or type a progress report comment before completing.

---

## 4. Administrator Portal (Desktop App)

Administrators use the desktop or web client to oversee field activity and manage database records.

### A. Dashboard KPIs
Upon logging in, the Admin Home Page displays critical metrics:
*   **Total Employee Registrations**
*   **Active Geofences Map**
*   **Active Field Check-Ins Today**
*   **Completed/Pending Tasks Ratio**
*   **Recent Activity Log** (real-time WebSocket updates)

### B. Geofence Management
1.  Navigate to the **Geofences** tab.
2.  **Creating a Geofence:**
    *   Click **Create Geofence**.
    *   Enter a **Name** and **Address**.
    *   Enter the exact **Latitude** and **Longitude** coordinates.
    *   Specify a **Radius** in meters (e.g., `50` for a fifty-meter circle).
    *   Assign specific employees to this geofence from the checklist.
    *   Click **Save**.
3.  **Modifying/Deactivating:** Select any geofence from the list to update its boundary details, reassign employees, or toggle its status to *Inactive* (deactivated geofences will prevent check-ins).

### C. Employee Management
1.  Go to the **Employees** tab.
2.  Here, you can review the list of registered users.
3.  Click on a user profile to:
    *   **Edit User Details** (Name, email, user role: Admin/Employee).
    *   **Deactivate/Activate Account** (deactivated accounts cannot log in).
    *   **Delete Account** (permanently deletes from database).
4.  **Bulk Import**: Click **Import CSV** to upload a list of employees to instantly generate user accounts.

### D. Task Assignment
1.  Go to the **Tasks** tab.
2.  Click **Create Task**.
3.  Fill in the **Title**, **Description**, **Due Date**, and link the task to a specific **Geofence**.
4.  Assign the task to one or more employees.
5.  Click **Assign**.
6.  The task will instantly appear on the assigned employee's mobile device via Socket.io.

### E. Client Tickets Management
1.  Navigate to the **Client Tickets** tab.
2.  Here you can see requests submitted by public clients.
3.  Select a ticket to:
    *   Assign a technician (Employee) to resolve it.
    *   Add progress remarks.
    *   Mark it as *In Progress* or *Completed*.
4.  You can view client-submitted comments and star ratings on resolved tickets.

### F. Attendance & Task Reports
1.  Navigate to the **Reports** tab.
2.  Filter records by **Date Range**, **Employee**, or **Geofence**.
3.  Preview the attendance duration logs or task completion rates.
4.  Click **Export PDF** or **Export Excel** to save the formatted sheets to your local desktop for capstone record submissions.

---

## 5. Client Installation & Access Guide (APK & EXE)

This guide walks clients and evaluators through installing the mobile application on Android and launching the desktop application on Windows.

### A. Accessing the System Landing Page (Web Browser)
The public portal is accessible to clients to submit tickets and track statuses:
*   **Production URL:** Open `https://fieldcheck-app-mwk3.onrender.com` in any modern web browser.
*   **Local Development:** Navigate to `http://localhost:5000` (or the configured local backend port) once the local servers are running.

---

### B. Installing the Mobile App (.APK) on Android
To install the client/employee mobile app on any Android device:

1.  **Transfer the APK File:**
    *   Locate the file `app-release.apk` (found in the root `build/app/outputs/flutter-apk/` directory or downloaded from your Google Drive submission).
    *   Transfer this file to your phone via USB cable, Google Drive, email, or direct download.
2.  **Enable Unknown Sources:**
    *   Because this app is compiled locally for your capstone defense and not downloaded from the Google Play Store, Android requires security permission.
    *   Go to **Settings** > **Apps** > **Special App Access** > **Install Unknown Apps** (or search "Unknown Sources").
    *   Toggle **Allow** for the application you are using to open the file (e.g., *My Files*, *Files by Google*, or *Google Drive*).
3.  **Install the APK:**
    *   Open your phone's File Manager app and locate the `app-release.apk` file.
    *   Tap the file.
    *   A prompt will appear asking: *"Do you want to install this application?"*. Click **Install**.
    *   Android Play Protect may show a warning: *"Blocked by Play Protect - Unknown Developer"*. Click **Install Anyway**.
4.  **Launch the App:**
    *   Once installed, tap **Open** or locate the **FieldCheck** icon on your home screen or app drawer.
    *   Grant the location permission when prompted.

---

### C. Launching the Administrator App (.EXE) on Windows (Optional)

> [!NOTE]
> Compiling or running the Windows `.exe` application is **completely optional**. The web version of the application contains the exact same Admin Dashboard. You can access it directly via browser (either locally or on your production Render URL) without compiling any Windows files.

To run the Desktop Administrator Portal on any Windows computer:

1.  **Prepare the Release Directory:**
    *   Locate the `Release/` folder (either built under `field_check/build/windows/x64/runner/Release/` or extracted from your zipped submission file).
2.  **Run the Executable:**
    *   Double-click the `field_check.exe` file inside that folder.
    *   *Note: Do not move `field_check.exe` out of its folder, as it relies on the surrounding `.dll` and data files in that same directory. If you want a cleaner launch, right-click `field_check.exe`, select **Show more options** > **Create shortcut**, and drag that shortcut to your Desktop.*
3.  **Log in:**
    *   The app will open. Click **Admin Login** and enter the credentials (`admin@example.com` / `Admin@123`).
