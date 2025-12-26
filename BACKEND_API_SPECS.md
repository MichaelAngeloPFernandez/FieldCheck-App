# FieldCheck Backend API Specifications

## Overview
This document outlines the API endpoints required to support the new features implemented in FieldCheck v2.0.

---

## Task Assignment Endpoints

### 1. Assign Task to Multiple Employees

**Endpoint:** `POST /api/tasks/:taskId/assign-multiple`

**Description:** Assigns a task to multiple employees in a single operation.

**Request:**
```json
{
  "employeeIds": ["employee_id_1", "employee_id_2", "employee_id_3"]
}
```

**Response (Success - 200/201):**
```json
{
  "_id": "task_id",
  "title": "Task Title",
  "description": "Task Description",
  "status": "pending",
  "assignedToMultiple": [
    {
      "id": "employee_id_1",
      "name": "Employee Name 1",
      "email": "employee1@example.com",
      "role": "employee"
    },
    {
      "id": "employee_id_2",
      "name": "Employee Name 2",
      "email": "employee2@example.com",
      "role": "employee"
    }
  ],
  "dueDate": "2025-12-31T23:59:59Z",
  "createdAt": "2025-11-25T00:00:00Z"
}
```

**Response (Error - 400/404/500):**
```json
{
  "message": "Error message describing what went wrong",
  "error": "INVALID_EMPLOYEE_ID | TASK_NOT_FOUND | SERVER_ERROR"
}
```

**Error Codes:**
- `400`: Invalid employee IDs or empty list
- `404`: Task not found
- `500`: Server error

**Notes:**
- Replaces previous single-employee assignment
- Should emit real-time event for connected clients
- Validate all employee IDs exist before assignment
- Clear previous assignments before assigning new ones (or append based on business logic)

---

### 2. Complete Task

**Endpoint:** `PUT /api/tasks/:taskId/complete`

**Description:** Marks a task as completed by a specific user.

**Request:**
```json
{
  "userId": "employee_id"
}
```

**Response (Success - 200):**
```json
{
  "_id": "task_id",
  "title": "Task Title",
  "status": "completed",
  "completedBy": "employee_id",
  "completedAt": "2025-11-25T12:30:45Z",
  "updatedAt": "2025-11-25T12:30:45Z"
}
```

**Response (Error - 400/404/500):**
```json
{
  "message": "Error message",
  "error": "INVALID_USER_ID | TASK_NOT_FOUND | ALREADY_COMPLETED"
}
```

**Error Codes:**
- `400`: Invalid user ID or task already completed
- `404`: Task not found
- `500`: Server error

**Notes:**
- Should emit real-time event for all connected clients
- Update task status to "completed"
- Record completion timestamp
- Record which user completed the task
- Trigger report generation if applicable

---

## Task Retrieval Endpoints

### 3. Get Task with Multiple Assignees

**Endpoint:** `GET /api/tasks/:taskId`

**Description:** Retrieves a task with all assigned employees.

**Response (Success - 200):**
```json
{
  "_id": "task_id",
  "title": "Task Title",
  "description": "Task Description",
  "status": "completed",
  "assignedToMultiple": [
    {
      "id": "employee_id_1",
      "name": "Employee Name 1",
      "email": "employee1@example.com",
      "role": "employee"
    }
  ],
  "assignedTo": {
    "id": "employee_id_1",
    "name": "Employee Name 1",
    "email": "employee1@example.com",
    "role": "employee"
  },
  "dueDate": "2025-12-31T23:59:59Z",
  "createdAt": "2025-11-25T00:00:00Z",
  "completedAt": "2025-11-25T12:30:45Z",
  "completedBy": "employee_id_1"
}
```

**Notes:**
- Include both `assignedTo` (for backward compatibility) and `assignedToMultiple`
- Include completion metadata if task is completed

---

### 4. Get All Tasks (Enhanced)

**Endpoint:** `GET /api/tasks`

**Query Parameters:**
- `status`: Filter by status (pending, in_progress, completed)
- `assignedTo`: Filter by employee ID
- `skip`: Pagination offset
- `limit`: Pagination limit

**Response (Success - 200):**
```json
[
  {
    "_id": "task_id_1",
    "title": "Task 1",
    "status": "completed",
    "assignedToMultiple": [
      {
        "id": "employee_id_1",
        "name": "Employee Name 1",
        "email": "employee1@example.com",
        "role": "employee"
      }
    ],
    "dueDate": "2025-12-31T23:59:59Z",
    "createdAt": "2025-11-25T00:00:00Z"
  }
]
```

---

## Report Endpoints

### 5. Create Task Report (Enhanced)

**Endpoint:** `POST /api/reports`

**Description:** Creates a report for a completed task.

**Request:**
```json
{
  "type": "task",
  "taskId": "task_id",
  "employeeId": "employee_id",
  "content": "Detailed report content here..."
}
```

**Response (Success - 201):**
```json
{
  "_id": "report_id",
  "type": "task",
  "taskId": "task_id",
  "employeeId": "employee_id",
  "content": "Detailed report content here...",
  "status": "submitted",
  "createdAt": "2025-11-25T12:30:45Z"
}
```

**Notes:**
- Should automatically update task status to "completed"
- Emit real-time event to all connected clients
- Archive autosaved data after successful submission

---

### 6. Get Reports with Filters

**Endpoint:** `GET /api/reports`

**Query Parameters:**
- `type`: Filter by report type (task, geofence, etc.)
- `taskId`: Filter by task ID
- `employeeId`: Filter by employee ID
- `status`: Filter by status (submitted, reviewed, etc.)
- `startDate`: Filter by date range (ISO 8601)
- `endDate`: Filter by date range (ISO 8601)

**Response (Success - 200):**
```json
[
  {
    "_id": "report_id",
    "type": "task",
    "taskId": "task_id",
    "employeeId": "employee_id",
    "employeeName": "Employee Name",
    "content": "Report content...",
    "status": "submitted",
    "createdAt": "2025-11-25T12:30:45Z"
  }
]
```

---

## Real-Time Events

### WebSocket Events

**Event: taskAssigned**
```json
{
  "taskId": "task_id",
  "employeeIds": ["employee_id_1", "employee_id_2"],
  "taskTitle": "Task Title",
  "timestamp": "2025-11-25T12:30:45Z"
}
```

**Event: taskCompleted**
```json
{
  "taskId": "task_id",
  "employeeId": "employee_id",
  "taskTitle": "Task Title",
  "status": "completed",
  "timestamp": "2025-11-25T12:30:45Z"
}
```

**Event: reportSubmitted**
```json
{
  "reportId": "report_id",
  "taskId": "task_id",
  "employeeId": "employee_id",
  "employeeName": "Employee Name",
  "timestamp": "2025-11-25T12:30:45Z"
}
```

---

## Database Schema Updates

### Task Collection

```javascript
{
  _id: ObjectId,
  title: String,
  description: String,
  status: String, // "pending", "in_progress", "completed"
  
  // Single assignee (backward compatibility)
  assignedTo: {
    id: String,
    name: String,
    email: String,
    role: String
  },
  
  // Multiple assignees (new)
  assignedToMultiple: [
    {
      id: String,
      name: String,
      email: String,
      role: String
    }
  ],
  
  // Completion tracking
  completedAt: Date,
  completedBy: String, // employee ID
  
  dueDate: Date,
  createdAt: Date,
  updatedAt: Date,
  createdBy: String, // admin ID
  
  // Location info
  geofenceId: String,
  latitude: Number,
  longitude: Number,
  
  // Team info
  teamId: String,
  teamMembers: [String]
}
```

### Report Collection

```javascript
{
  _id: ObjectId,
  type: String, // "task", "geofence", etc.
  taskId: String,
  employeeId: String,
  employeeName: String,
  content: String,
  status: String, // "submitted", "reviewed", "approved"
  createdAt: Date,
  updatedAt: Date
}
```

---

## Migration Guide

### For Existing Tasks

1. **Add `assignedToMultiple` field:**
   ```javascript
   db.tasks.updateMany(
     { assignedTo: { $exists: true } },
     [
       {
         $set: {
           assignedToMultiple: {
             $cond: [
               { $eq: ["$assignedTo", null] },
               [],
               ["$assignedTo"]
             ]
           }
         }
       }
     ]
   )
   ```

2. **Add completion tracking fields:**
   ```javascript
   db.tasks.updateMany(
     { status: "completed" },
     {
       $set: {
         completedAt: new Date(),
         completedBy: "$assignedTo.id"
       }
     }
   )
   ```

---

## Rate Limiting

- **Task Assignment:** 100 requests per minute per user
- **Task Completion:** 100 requests per minute per user
- **Report Creation:** 50 requests per minute per user
- **Report Retrieval:** 200 requests per minute per user

---

## Authentication

All endpoints require:
- **Header:** `Authorization: Bearer <token>`
- **Token Type:** JWT
- **Expiration:** 24 hours

---

## Error Handling

### Standard Error Response

```json
{
  "success": false,
  "message": "Human-readable error message",
  "error": "ERROR_CODE",
  "statusCode": 400,
  "timestamp": "2025-11-25T12:30:45Z"
}
```

### Common Error Codes

- `INVALID_REQUEST`: Request validation failed
- `UNAUTHORIZED`: Authentication failed
- `FORBIDDEN`: User doesn't have permission
- `NOT_FOUND`: Resource not found
- `CONFLICT`: Resource already exists
- `SERVER_ERROR`: Internal server error

---

## Testing

### Sample cURL Commands

**Assign Task to Multiple Employees:**
```bash
curl -X POST http://localhost:3000/api/tasks/task_id/assign-multiple \
  -H "Authorization: Bearer token" \
  -H "Content-Type: application/json" \
  -d '{
    "employeeIds": ["emp1", "emp2", "emp3"]
  }'
```

**Complete Task:**
```bash
curl -X PUT http://localhost:3000/api/tasks/task_id/complete \
  -H "Authorization: Bearer token" \
  -H "Content-Type: application/json" \
  -d '{
    "userId": "emp1"
  }'
```

**Get Task:**
```bash
curl -X GET http://localhost:3000/api/tasks/task_id \
  -H "Authorization: Bearer token"
```

---

## Performance Considerations

1. **Indexing:** Create indexes on:
   - `tasks.status`
   - `tasks.assignedToMultiple.id`
   - `tasks.dueDate`
   - `reports.taskId`
   - `reports.employeeId`

2. **Pagination:** Always paginate large result sets
3. **Caching:** Cache employee lists for 5 minutes
4. **Batch Operations:** Support batch task assignment for efficiency

---

## Version History

- **v2.0** (Nov 25, 2025): Added multi-employee assignment and task completion tracking
- **v1.0** (Previous): Single employee assignment only

---

**Last Updated:** November 25, 2025
**Status:** Ready for Implementation ✅
