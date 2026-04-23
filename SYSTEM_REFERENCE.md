# 📑 FieldCheck — Complete System Reference Guide

This document serves as the authoritative, highly accurate reference for the **FieldCheck** application. It is designed to provide AI agents and developers with a comprehensive understanding of the app's structure, functions, features, and technical architecture.

---

## 1. Product Summary
**FieldCheck** is a dual-platform workforce management system designed for field-based operations.
- **Employee App (Flutter)**: Allows employees to check in/out at geofences, complete assigned tasks, submit detailed reports, and communicate with admins.
- **Admin App (Flutter)**: Enables admins to manage employees, define geofences, assign and track tasks, review/grade reports, and monitor live location activity.
- **Backend (Node.js/Express)**: A robust REST API coupled with MongoDB for persistence and Socket.IO for real-time synchronization.

---

## 2. Technical Stack
- **Frontend**: Flutter (supporting Android, iOS, and Web).
- **Backend**: Node.js + Express.js.
- **Database**: MongoDB Atlas (with GridFS for persistent file storage).
- **Real-time**: Socket.io (WebSockets) for notifications, messages, and live tracking.
- **Authentication**: JWT (JSON Web Tokens) + Email Verification (Nodemailer).
- **Maps**: Google Maps Flutter for location tracking and geofence visualization.

---

## 3. Core Domain Models & Logic

### 3.1 User Model (`backend/models/User.js`)
- Roles: `admin` or `employee`.
- Contains profile data, authentication credentials, and (for employees) assigned geofences/tasks.

### 3.2 Task Assignment Model (Critical)
There is a decoupling between a task definition and its assignment:
- **`Task`**: The blueprint of a task (title, description, difficulty, due date, checklist).
- **`UserTask`**: The specific record of a task assigned to an employee.
  - **Invariant**: Statuses like `isArchived`, `blockStatus`, and `completionStatus` are typically managed at the `UserTask` level to allow per-employee progress tracking for the same base task.

### 3.3 Geofencing
- Circular geofences defined by latitude, longitude, and radius.
- Employees can only check in/out when within the radius (server-side validation using Haversine distance).

### 3.4 Reports & Grading
- Employees submit reports (text + image/file attachments).
- Admins can **Grade** reports (e.g., numeric score or status) and add **Comment Threads** for feedback.

---

## 4. Repository Structure

### 4.1 Backend (`/backend`)
- `controllers/`: Logic for tasks, reports, users, attendance, chat, etc.
- `models/`: Mongoose schemas (Task, User, UserTask, Report, Attendance, Geofence, Notification).
- `services/`: Specialized logic like `appNotificationService.js` (notification creation and socket emission).
- `routes/`: API endpoint definitions.
- `uploads/`: Local storage for files (though migrating/migrated to GridFS for production).
- `server.js`: Main entry point, socket initialization, and middleware setup.

### 4.2 Frontend (`/field_check/lib`)
- `screens/`: UI implementations (organized into Admin and Employee views).
- `models/`: Dart classes for data parsing (`fromJson`/`toJson`).
- `services/`: API client wrappers and Socket.IO handlers.
- `providers/`: State management (ChangeNotifier/Provider).
- `widgets/`: Reusable UI components.

---

## 5. Major Features

### 5.1 Admin Features
- **Enhanced Dashboard**: Real-time stats, interactive charts, and a "Top Counters" bar for notifications/messages.
- **Task Management**: Create tasks, assign to multiple employees, monitor "Blocked" assignments, and archive/restore.
- **Report Hub**: Centralized view of all submissions. Admins can grade, comment, and export reports to Excel/PDF.
- **Analytics Suite**: Calendar-based history view (`AdminCalendarAnalyticsScreen`) showing daily activity and performance metrics.
- **World Map**: Live tracking of online employees with GPS trails and geofence status.
- **User Management**: Approve registrations, manage roles, and bulk import/export employees.
- **Chat**: Group and individual chat management with employees.

### 5.2 Employee Features
- **Task List**: Tabbed view of Pending, Completed, Overdue, and Archived assignments.
- **Task Execution**: Checklist completion, "Block" task with reason, and photo-report submission.
- **Attendance**: GPS-verified Check-in/Check-out with duration tracking.
- **Notifications**: Real-time alerts for new tasks, messages, and grading feedback.
- **Profile**: Performance stats (tasks completed, attendance rate).

---

## 6. Real-time & Synchronization (Socket.IO)

The system uses `Socket.IO` for immediate UI updates without polling:
- **`unreadCountUpdate`**: Emitted when notifications/messages are created or read.
- **`newMessage`**: Triggers chat UI updates.
- **`locationUpdate`**: Feeds the admin world map with employee GPS data.
- **`taskUpdate` / `reportUpdate`**: Updates dashboard stats and lists.

---

## 7. AI Agent Guidelines & Invariants

### 7.1 Working with Tasks
- **Never** filter a user's task list using `Task.isArchived` alone; check `UserTask.isArchived` for the specific assignment status.
- When an employee "Blocks" a task, update the `UserTask` record and emit a notification to the `adminFeed` scope.

### 7.2 Notifications & Unread Counts
- Notifications have `scopes`: `tasks`, `messages`, `report`, `adminFeed`.
- The `AdminDashboard` unread counter is often a combination of multiple scopes.
- When marking a notification as read, ensure the `unreadCountUpdate` event is emitted so the UI updates globally.

### 7.3 Data Parsing (Flutter)
- **Robustness**: Always use `try-catch` or null-safe parsing in `fromJson` models. Backend updates may introduce fields that older client versions or local mocks don't expect.
- **Enums**: Map backend strings (e.g., "pending", "completed") to Flutter Enums for type safety.

### 7.4 Common Gotchas
- **Ephemeral Storage**: On platforms like Render, local `/uploads` are lost on restart. Use the GridFS-backed service for persistent file handling.
- **Socket Leaks**: In Flutter, always dispose of socket listeners in `dispose()` to prevent memory leaks and duplicate UI updates.
- **Admin "Nearby" Logic**: Admin visibility into nearby employees/geofences uses a specialized location service; verify the `locationController.js` logic if maps are behaving unexpectedly.

---

## 8. Recently Implemented / "Enhanced" Screens
- `EnhancedReportsScreen`: Includes advanced filtering and aggregation.
- `AdminCalendarAnalyticsScreen`: Provides a visual "Heatmap" of activity.
- `ReportExportPreviewScreen`: Allows admins to customize and preview exports before downloading.
- `EnhancedAttendanceScreen`: More robust check-in/out logic with better error handling.

---

**Last Updated**: April 23, 2026
**Status**: 🟢 Production-Ready Documentation for AI Agents.
