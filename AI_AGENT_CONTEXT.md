# FieldCheck — AI Agent Context (Project Overview)

This document is intended to give an AI coding agent enough *high-signal context* to work effectively in this repository.

It focuses on:
- What the app is
- The major features (admin + employee)
- The core data models and relationships
- The backend API surface and how real-time updates work
- The frontend (Flutter) screens/services architecture
- Notification/message scopes and counters
- Common invariants/pitfalls that often cause regressions

---

## 1) Product Summary

**FieldCheck** is a two-sided system:
- **Employee app (Flutter)**: employees complete tasks, submit task reports, check-in/out attendance, receive notifications/messages, and (optionally) share live location.
- **Admin app (Flutter)**: admins manage employees, tasks, geofences, review/grade reports, see notifications/messages, and monitor employee activity and live locations.

**Backend** is Node.js/Express with MongoDB. The system also uses **Socket.IO** for real-time updates.

---

## 2) Repository Layout (Top-Level)

- `backend/`
  - Express server, controllers, routes, Mongoose models, Socket.IO wiring, notification services
- `field_check/`
  - Flutter application (both admin + employee UIs)
- Many `.md/.txt` documents exist at repo root
  - This file is specifically for AI agents; prefer it as the entry point for context.

---

## 3) Core Concepts & Entities

### 3.1 Users
Two primary roles:
- **Employee**
- **Admin**

(Exact role flags live in backend user model; verify in `backend/models/User.js`.)

### 3.2 Tasks vs UserTasks (Assignment Model)
There is an important split:
- **`Task`**: the base task definition (title, difficulty, due date, checklist, etc.)
- **`UserTask`**: the per-employee assignment record for a task

This is critical for correct UI behavior:
- Archiving, completion state, and “blocked” state are often **per assignment**, not global.
- A task can be globally archived (`Task.isArchived`), while an employee’s assignment can still be current/archived based on **`UserTask.isArchived`**.

### 3.3 Reports
Reports are submitted by employees and reviewed/graded by admins.
- **Task reports** attach to a task (and implicitly to a user-task assignment)
- **Attendance reports** attach to attendance records

### 3.4 Attendance
Employees perform check-in/check-out. Records can be filtered and exported in admin UI.

### 3.5 Geofences
Admins define geofenced areas. Employees can have location-based tasks/attendance behaviors.

---

## 4) Major Features (High-Level)

### 4.1 Employee Features
- **Authentication / Profile**
- **Task list** with tabs/filters (e.g., current, overdue, archived)
- **Task details** (checklist, status, due date)
- **Complete task** (subject to constraints like “blocked”)
- **Block task assignment** (employee flags an assignment as blocked with a reason)
- **Task report submission** (with attachments)
- **Attendance** (check-in/out and history)
- **Notifications** (unread counter)
- **Messages** (chat with admin; unread counter)
- **Live location updates** (if enabled)

### 4.2 Admin Features
- **Dashboard** (stats, notifications inbox, optional world map)
- **Notifications inbox** (grouping, unread counts)
- **Messages** (chat threads with employees)
- **Reports screen**
  - View current/archived
  - Filter/sort
  - View details
  - Grade/update status
  - Export
- **Task management**
  - Create tasks
  - Assign tasks to employees
  - Archive/restore
  - Unblock/reopen per-employee assignments
- **Employees management**
- **Geofence management**
- **World map / live tracking** (shows online employees with GPS; trails)

---

## 5) “Blocked Task” (Important Domain Logic)

### 5.1 What “blocked” means
“Blocked” is a **per-assignment** state (typically stored on `UserTask`).
- Only the employee who is assigned can block *their* assignment.
- While blocked:
  - The employee should see a prominent banner.
  - Completion actions should be disabled.
  - Report submission should be prevented (or clearly disabled).

### 5.2 Block fields (UserTask)
Common fields used for blocked state:
- `blockStatus` (e.g., `blocked` / `unblocked`)
- `blockReasonText`
- `blockedAt`

### 5.3 Admin visibility
Admins should receive notifications about blocked assignments and should see blocked status in reports.

---

## 6) Notifications & Messages (Scopes + Counters)

### 6.1 Notification creation
Backend uses a notification service (commonly `backend/services/appNotificationService.js`) to:
- create notifications
- emit real-time unread counts updates via Socket.IO

### 6.2 Scopes
Notifications are categorized by `scope`. Common scopes used in this project:
- `tasks`
- `messages`
- `report`
- `adminFeed`

Agents should treat scopes as **UI routing/categorization signals**.

### 6.3 Unread counters
There are multiple counters in the UI:
- Admin: unread notifications count
- Admin: unread messages count
- Admin dashboard “top” counter may represent combined unread totals (often capped `999+`)
- Employee bell counter may represent combined unread (notifications + messages)

If adjusting counters, verify:
- what the backend emits
- how the Flutter app merges counts
- whether unread message counts are grouped per conversation

---

## 7) Real-time (Socket.IO) Model

Socket.IO is used for:
- unread count updates (notifications/messages)
- new message events
- location updates (employee tracking)

When adding features that must feel real-time, verify:
- the backend emits an event
- the frontend subscribes once, unsubscribes on dispose
- event payload includes enough identifiers for deep-link navigation

---

## 8) Backend: Where to Look

### 8.1 Controllers
Typical backend implementation uses controllers such as:
- `backend/controllers/taskController.js`
  - assignment fetching (`getAssignedTasks`, etc.)
  - blocking/unblocking per-assignment
- `backend/controllers/reportController.js`
  - create/list reports
  - status/grade updates
- Other controllers for auth/users/geofences/attendance/messages

### 8.2 Services
- `backend/services/appNotificationService.js`
  - creates notifications
  - emits unread counts

### 8.3 Models
Mongoose models are in `backend/models/`.
Key ones:
- `Task`
- `UserTask`
- `Report`
- `User`
- `Notification` (or app notification model)
- `Attendance`
- `Geofence`

### 8.4 Common backend invariants
- Avoid filtering employee task lists using `Task.isArchived` if the UI depends on `UserTask.isArchived`.
- “Blocked” state should be tied to the assignment (`UserTask`) not the base `Task`.
- When adding a notification type, ensure:
  - payload contains identifiers needed by the UI
  - scope is correct for the screen/counters
  - events are emitted if real-time UI is expected

---

## 9) Flutter App: Where to Look

### 9.1 Screens
Screens live in `field_check/lib/screens/`.
Notable ones:
- Employee:
  - `employee_task_list_screen.dart`
  - `employee_task_details_screen.dart`
  - `task_report_screen.dart`
  - `employee_reports_screen.dart`
- Admin:
  - `admin_dashboard_screen.dart`
  - `admin_reports_screen.dart`
  - admin messages screen(s)
  - admin employee management screens
  - admin geofence screens

### 9.2 Models
- `field_check/lib/models/`
  - `report_model.dart`
  - `task_model.dart`
  - others

### 9.3 Services
- `field_check/lib/services/`
  - `report_service.dart`
  - `task_service.dart`
  - `attendance_service.dart`
  - `user_service.dart`
  - realtime/socket service (if present)

### 9.4 Common Flutter invariants
- Keep parsing logic in models (`fromJson`) robust; backend fields may be missing.
- Avoid double-subscribing to sockets (memory leaks + duplicate events).
- If you add a new server field, you often must:
  - update model parsing
  - update list UI and details UI
  - update filtering logic if it’s filterable

---

## 10) Reports Pipeline (Employee → Admin)

1. Employee opens task and submits a report.
2. Backend persists the report and (optionally) emits:
   - notifications to admins
   - unread counts updates
3. Admin lists reports in `AdminReportsScreen`.
4. Admin views details, grades, marks reviewed, and may reopen for resubmission.

If “blocked” state is important for admins:
- backend should join `UserTask` when listing reports and include `taskBlockStatus` fields
- Flutter model must parse those fields
- admin report UI should display it prominently

---

## 11) Attachments (Important Deployment Note)

Some deployments (e.g., Render free tier) have **ephemeral disk**. If attachments are stored as file paths on the app server, they may 404 after restarts.

If you see attachment URLs like `/uploads/...` causing 404s, consider a durable storage approach (e.g., GridFS or object storage).

---

## 12) How to Work Safely as an AI Agent

When implementing changes:
- Prefer minimal targeted patches.
- Verify the UI change has backend support (fields, routes, payload IDs).
- For anything that impacts unread counts:
  - identify the authoritative backend source of truth
  - ensure all counters display consistent totals

Before concluding:
- run `flutter analyze`
- do a quick backend syntax check (`node --check <file>`)

---

## 13) Quick “Where is X?” Index

- **Task assignment logic**: `backend/controllers/taskController.js`
- **Report creation/listing**: `backend/controllers/reportController.js`
- **Notifications creation/emission**: `backend/services/appNotificationService.js`
- **Admin report UI**: `field_check/lib/screens/admin_reports_screen.dart`
- **Employee report UI**: `field_check/lib/screens/employee_reports_screen.dart`
- **Employee task list/details**:
  - `field_check/lib/screens/employee_task_list_screen.dart`
  - `field_check/lib/screens/employee_task_details_screen.dart`

---

## 14) Open Items / Likely Future Work (UI/UX)

Common improvement targets in this project:
- Real-time new message identifiers in admin Messages tab (deep-link to employee chat)
- Correct unread counters (notifications vs messages) and combined dashboard counter (cap `999+`)
- Employee bell counter showing combined unread notifications + messages
- Ensuring blocked task reporting/notifications appear consistently across admin feed, messages scope, and reports UI
