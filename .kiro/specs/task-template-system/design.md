# Design Document: Task Template System

## Overview

This document describes the technical design for implementing the Task Template System, including data models, API endpoints, UI components, and system architecture. The design supports service-based task management with automatic template cloning, flexible ad-hoc task addition, and comprehensive task page remastering for both admin and employee interfaces.

## Data Models

### Service Model

```javascript
{
  _id: ObjectId,
  companyId: ObjectId (ref: Company),
  name: String (required, unique per company),
  description: String (optional),
  isActive: Boolean (default: true),
  createdAt: Date,
  updatedAt: Date
}
```

**Indexes:**
- `{ companyId: 1, name: 1 }` - Unique per company
- `{ companyId: 1, isActive: 1 }` - For listing active services

### TaskTemplate Model

```javascript
{
  _id: ObjectId,
  serviceId: ObjectId (ref: Service, required),
  companyId: ObjectId (ref: Company, required),
  title: String (required),
  description: String (optional),
  type: String (enum: ['general', 'inspection', 'maintenance', 'delivery', 'other'], default: 'general'),
  difficulty: String (enum: ['easy', 'medium', 'hard'], default: 'medium'),
  checklist: [
    {
      label: String (required),
      isCompleted: Boolean (default: false),
      completedAt: Date
    }
  ],
  isActive: Boolean (default: true),
  createdAt: Date,
  updatedAt: Date
}
```

**Indexes:**
- `{ serviceId: 1 }` - For listing templates by service
- `{ companyId: 1, isActive: 1 }` - For company-scoped queries

### Task Model Enhancement

Extend existing Task model with:

```javascript
{
  // ... existing fields ...
  taskOrigin: String (enum: ['template', 'ad_hoc'], default: 'ad_hoc'),
  templateId: ObjectId (ref: TaskTemplate, optional),
  ticketId: ObjectId (ref: Ticket, optional),
  assignedTo: ObjectId (ref: User, optional),
  completedBy: ObjectId (ref: User, optional),
  completedAt: Date (optional),
  taskDuration: Number (milliseconds, optional),
  notes: String (optional),
  blockReason: String (optional),
  statusHistory: [
    {
      status: String,
      changedBy: ObjectId (ref: User),
      changedAt: Date,
      reason: String (optional)
    }
  ]
}
```

**Indexes:**
- `{ ticketId: 1, taskOrigin: 1 }` - For filtering by origin
- `{ assignedTo: 1, status: 1 }` - For employee task queries
- `{ companyId: 1, createdAt: 1 }` - For reporting

### Ticket Model (New or Enhanced)

```javascript
{
  _id: ObjectId,
  companyId: ObjectId (ref: Company, required),
  serviceId: ObjectId (ref: Service, optional),
  title: String (required),
  description: String (optional),
  status: String (enum: ['open', 'in_progress', 'completed', 'closed'], default: 'open'),
  createdAt: Date,
  updatedAt: Date
}
```

**Indexes:**
- `{ companyId: 1, status: 1 }` - For listing tickets
- `{ serviceId: 1 }` - For service-based queries

## API Endpoints

### Service Management

**POST /api/services**
- Create a new service
- Auth: Admin
- Body: `{ name, description }`
- Returns: Service object

**GET /api/services**
- List all services for company
- Auth: Admin
- Query: `?isActive=true&sort=name`
- Returns: Array of Service objects

**GET /api/services/:id**
- Get service details with templates
- Auth: Admin
- Returns: Service object with embedded TaskTemplates

**PUT /api/services/:id**
- Update service
- Auth: Admin
- Body: `{ name, description, isActive }`
- Returns: Updated Service object

**DELETE /api/services/:id**
- Delete service and associated templates
- Auth: Admin
- Returns: `{ success: true }`

### Task Template Management

**POST /api/services/:serviceId/templates**
- Create task template for service
- Auth: Admin
- Body: `{ title, description, type, difficulty, checklist }`
- Returns: TaskTemplate object

**GET /api/services/:serviceId/templates**
- List templates for service
- Auth: Admin
- Returns: Array of TaskTemplate objects

**GET /api/templates/:id**
- Get template details
- Auth: Admin
- Returns: TaskTemplate object

**PUT /api/templates/:id**
- Update template
- Auth: Admin
- Body: `{ title, description, type, difficulty, checklist, isActive }`
- Returns: Updated TaskTemplate object

**DELETE /api/templates/:id**
- Delete template (does not affect cloned tasks)
- Auth: Admin
- Returns: `{ success: true }`

### Task Management

**POST /api/tickets/:ticketId/tasks**
- Create ad-hoc task for ticket
- Auth: Admin
- Body: `{ title, description, type, difficulty, checklist }`
- Returns: Task object with `taskOrigin: 'ad_hoc'`

**GET /api/tickets/:ticketId/tasks**
- List all tasks for ticket
- Auth: Admin, Employee (own tasks)
- Query: `?status=pending&taskOrigin=template&sort=createdAt`
- Returns: Array of Task objects

**GET /api/tasks/:id**
- Get task details
- Auth: Admin, assigned Employee
- Returns: Task object with full history

**PUT /api/tasks/:id**
- Update task (status, notes, checklist items)
- Auth: Admin, assigned Employee
- Body: `{ status, notes, checklist, blockReason }`
- Returns: Updated Task object

**PUT /api/tasks/:id/assign**
- Assign task to employee
- Auth: Admin
- Body: `{ assignedTo }`
- Returns: Updated Task object

**PUT /api/tasks/:id/status**
- Change task status
- Auth: Admin, assigned Employee
- Body: `{ status, reason }`
- Returns: Updated Task object with status history entry

**POST /api/tasks/:id/checklist/:itemIndex/complete**
- Mark checklist item as complete
- Auth: Employee assigned to task
- Returns: Updated Task object

### Ticket Management

**POST /api/tickets**
- Create ticket with optional service
- Auth: Admin
- Body: `{ title, description, serviceId }`
- Logic: If serviceId provided, clone all templates
- Returns: Ticket object with cloned tasks

**GET /api/tickets**
- List tickets for company
- Auth: Admin
- Query: `?status=open&serviceId=xxx&sort=createdAt`
- Returns: Array of Ticket objects

**GET /api/tickets/:id**
- Get ticket with all tasks
- Auth: Admin, assigned Employees
- Returns: Ticket object with embedded tasks

### Reporting

**GET /api/reports/tasks**
- Generate task completion report
- Auth: Admin
- Query: `?startDate=xxx&endDate=xxx&serviceId=xxx&companyId=xxx`
- Returns: Report object with metrics

**GET /api/reports/tasks/export**
- Export task report as CSV/PDF
- Auth: Admin
- Query: `?format=csv&startDate=xxx&endDate=xxx`
- Returns: File download

## UI Components

### Admin Dashboard - Service and Template Management

**Service Management Section** (in `admin_task_management_screen.dart`)
- New tab or section for managing services and templates
- Features:
  - List view of services with template count
  - Create/edit/delete service buttons
  - Expandable service items showing associated templates
  - Create/edit/delete template buttons
  - Search and sort functionality

**Service Selection in Ticket Creation** (in `admin_task_management_screen.dart`)
- Enhanced ticket creation form
- Features:
  - Service dropdown selector
  - Template preview showing tasks that will be created
  - Automatic task cloning on ticket creation
  - Loading state during cloning

### Admin Dashboard - Task Assignment Page Enhancement

**Enhanced Task Assignment Section** (in `admin_task_management_screen.dart`)
- Remastered task assignment interface
- Layout:
  - Ticket header with service name and status
  - Task list with columns: title, type, difficulty, status, assigned employee, progress
  - Filters: status, type, taskOrigin, assigned employee
  - Search by title/description
  - Add ad-hoc task button

**Task Display Enhancements**
- Show task origin badge (template/ad-hoc)
- Show checklist progress (X/Y items completed)
- Show status history
- Show assigned employee
- Show task duration

**Task Assignment Features**
- Assign task to employee
- Reassign task to different employee
- Change task status (pending → in_progress → completed → reviewed → closed)
- Block task with reason
- Add ad-hoc task to ticket
- View full task details with notes and attachments

**Filtering and Search**
- Filter by status (pending, in_progress, completed, blocked, reviewed, closed)
- Filter by type (general, inspection, maintenance, delivery, other)
- Filter by task origin (template, ad-hoc)
- Filter by assigned employee
- Search by title or description
- Save filter presets

### Employee App - Task Completion Page Enhancement

**Enhanced Task Completion Section** (in `employee_task_list_screen.dart`)
- Remastered task completion interface
- Layout:
  - Ticket header with service name
  - Task list with columns: title, status, progress
  - Filters: status
  - Search by title/description

**Task Display Enhancements**
- Show task title and description
- Show task type and difficulty badges
- Show current status
- Show checklist items with checkboxes
- Show completion progress
- Show notes section
- Show attachment section

**Task Completion Features**
- Mark task as "in_progress"
- Mark task as "completed"
- Check off individual checklist items with timestamps
- Add notes to tasks
- Attach images or documents
- View task details and history

**Filtering and Search**
- Filter by status
- Search by title or description
- Remember last used filters

## Business Logic

### Task Cloning Logic

When a ticket is created with a serviceId:

1. Query all active TaskTemplates for the service
2. For each template:
   - Create new Task with:
     - title, description, type, difficulty from template
     - checklist items copied from template
     - taskOrigin: 'template'
     - templateId: reference to template
     - ticketId: reference to ticket
     - status: 'pending'
3. Associate all created tasks with the ticket
4. Return ticket with cloned tasks

### Task Status Workflow

Valid transitions:
- pending → in_progress
- pending → blocked
- in_progress → completed
- in_progress → blocked
- blocked → in_progress
- completed → reviewed
- reviewed → closed
- Any status → blocked (with reason)

When status changes:
1. Validate transition is allowed
2. Record status change in statusHistory with timestamp and user
3. If completed: record completedAt and completedBy
4. If blocked: require blockReason
5. Update task record
6. Trigger notifications if needed

### Task Duration Calculation

When task is marked completed:
1. Calculate duration = completedAt - createdAt
2. Store in taskDuration field
3. Use for reporting and analytics

### Reporting Logic

Task completion report includes:
- Total tasks created
- Tasks completed (count and percentage)
- Tasks by origin (template vs ad-hoc)
- Completion rate by task type
- Completion rate by service
- Average completion time by task type
- Employee performance metrics
- Checklist completion rates
- Template effectiveness (ad-hoc tasks added per service)

## Data Flow Diagrams

### Ticket Creation with Template Cloning

```
Admin creates Ticket with Service
    ↓
System queries Service and TaskTemplates
    ↓
For each TaskTemplate:
  - Create Task with taskOrigin='template'
  - Link to template and ticket
    ↓
Return Ticket with cloned tasks
    ↓
Admin sees tasks ready for assignment
```

### Task Completion Workflow

```
Employee views Task Completion Page
    ↓
Employee marks task "in_progress"
    ↓
Employee checks off checklist items
    ↓
Employee adds notes/attachments
    ↓
Employee marks task "completed"
    ↓
System records completion details
    ↓
Admin sees updated task status
    ↓
Admin reviews and marks "reviewed"
    ↓
Admin marks "closed"
```

## Integration Points

### With Existing Systems

1. **User Model**: No changes needed, use existing user references
2. **Company Model**: No changes needed, use existing company scoping
3. **Notification System**: Integrate for task assignment notifications
4. **Report System**: Extend to include template and task origin data
5. **Audit System**: Log all service, template, and task changes

### External Dependencies

- None - uses existing MongoDB, Express, and Node.js stack

## Performance Considerations

1. **Indexes**: Create indexes on frequently queried fields (companyId, serviceId, ticketId, status)
2. **Query Optimization**: Use lean() for read-only queries, populate() for related data
3. **Caching**: Cache service and template lists per company
4. **Pagination**: Implement pagination for large task lists
5. **Batch Operations**: Support bulk task status updates

## Security Considerations

1. **Multi-Tenancy**: All queries must filter by companyId
2. **Authorization**: Verify user belongs to company before accessing data
3. **Admin-Only Operations**: Service/template management restricted to admins
4. **Employee Restrictions**: Employees can only view/update their assigned tasks
5. **Audit Logging**: Log all create/update/delete operations

## Backward Compatibility

1. **Existing Tasks**: Tasks without taskOrigin default to 'ad_hoc'
2. **Existing Tickets**: Tickets without serviceId work as before
3. **Optional Fields**: All new fields are optional
4. **Migration**: No data migration needed, system handles both old and new data

## Testing Strategy

### Unit Tests
- Service CRUD operations
- Template CRUD operations
- Task cloning logic
- Status transition validation
- Duration calculation

### Integration Tests
- Ticket creation with template cloning
- Task assignment workflow
- Task completion workflow
- Multi-company isolation
- Reporting accuracy

### E2E Tests
- Admin creates service and templates
- Admin creates ticket and assigns tasks
- Employee completes tasks
- Admin views reports

## Deployment Considerations

1. **Database Migrations**: Create new collections for Service and TaskTemplate
2. **API Deployment**: Deploy new endpoints with backward compatibility
3. **UI Deployment**: Deploy admin and employee UI updates
4. **Testing**: Run full test suite before production deployment
5. **Rollback Plan**: Keep old task assignment logic available if needed
