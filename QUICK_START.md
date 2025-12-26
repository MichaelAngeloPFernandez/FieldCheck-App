# FieldCheck - Quick Start Guide

## Installation

1. **Install Dependencies**
   ```bash
   cd field_check
   flutter pub get
   ```

2. **Run the App**
   ```bash
   flutter run
   ```

---

## New Features Overview

### 1. Location Search on Map
**How to Use:**
- Open the Map screen
- Look for the search bar at the top with "Search location..." placeholder
- Type an address (e.g., "Manila, Philippines")
- Select from the dropdown results
- Map will automatically navigate to the selected location

**Use Case:** Quickly find and set up geofences for new locations

---

### 2. Multi-Employee Task Assignment
**How to Use (Admin):**
1. Go to Admin Task Management
2. Click the assign button (👤 icon) on any task
3. A dialog opens with all employees listed
4. Check the boxes next to employees you want to assign the task to
5. Click "Assign" to assign to multiple employees

**Use Case:** Assign the same task to multiple team members for collaborative work

---

### 3. Task Completion Tracking
**How to Use (Employee):**
1. Go to "My Tasks" screen
2. Find the task you want to complete
3. **Option A:** Click the checkbox next to the task title
4. **Option B:** Click "Complete Task" button
5. Fill in the task report and submit
6. Task status automatically changes to "completed"

**Visual Indicators:**
- ✓ Checkbox: Task is completed
- ~~Strikethrough~~ text: Completed task
- Green chip: Completed status
- Orange chip: In progress status
- Blue chip: Pending status

---

### 4. Real-Time Reports
**How It Works:**
- When an employee completes a task and submits a report
- The system automatically:
  - Updates task status to "completed"
  - Sends real-time notification to admins
  - Updates the reports dashboard
  - Reflects changes across all connected clients

**No Manual Action Required** - Everything happens automatically!

---

## File Changes Summary

| File | Change | Impact |
|------|--------|--------|
| `pubspec.yaml` | Added geocoding dependency | Enables location search |
| `task_model.dart` | Added `assignedToMultiple` field | Supports multiple assignees |
| `task_service.dart` | Added `assignTaskToMultiple()` and `completeTask()` | Backend integration |
| `map_screen.dart` | Added location search UI and methods | Location search feature |
| `admin_task_management_screen.dart` | Updated `_assignTask()` method | Multi-select dialog |
| `employee_task_list_screen.dart` | Enhanced task display and completion | Better UX |

---

## Backend Endpoints Required

Make sure your backend implements these endpoints:

```javascript
// Assign task to multiple employees
POST /api/tasks/:taskId/assign-multiple
{
  "employeeIds": ["id1", "id2", "id3"]
}

// Mark task as completed
PUT /api/tasks/:taskId/complete
{
  "userId": "employee_id"
}
```

---

## Troubleshooting

### Location Search Not Working
- ✓ Ensure internet connection is active
- ✓ Check that geocoding package is installed (`flutter pub get`)
- ✓ Verify location permissions are granted

### Multi-Select Dialog Not Showing
- ✓ Ensure employees are fetched from backend
- ✓ Check user service is working correctly
- ✓ Verify API endpoint returns employee list

### Task Status Not Updating
- ✓ Ensure backend endpoints are implemented
- ✓ Check network connection
- ✓ Verify task IDs are correct

---

## Tips & Best Practices

1. **Location Search:** Use specific addresses for better results (e.g., "123 Main St, Manila" instead of just "Manila")

2. **Task Assignment:** Assign tasks to all relevant team members at once instead of one by one

3. **Task Completion:** Always fill in a detailed report when completing tasks for better tracking

4. **Real-Time Updates:** Keep the app open to receive real-time notifications of task completions

---

## Next Steps

1. Test all new features thoroughly
2. Implement backend endpoints if not already done
3. Configure push notifications for task assignments
4. Set up analytics to track task completion rates
5. Consider adding task templates for frequently assigned tasks

---

## Support

For issues or questions:
1. Check the IMPLEMENTATION_SUMMARY.md for detailed information
2. Review the code comments in modified files
3. Test with sample data first
4. Check backend logs for API errors

---

**Version:** 2.0
**Last Updated:** November 25, 2025
**Status:** Ready for Testing ✅
