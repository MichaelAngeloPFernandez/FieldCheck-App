# Implementation Tasks: Task Template System

## Phase 1: Backend Models and Database

### 1.1 Create Service Model
- [ ] Create `backend/models/Service.js`
- [ ] Define schema with companyId, name, description, isActive
- [ ] Add indexes for company and active status
- [ ] Add validation for unique name per company
- [ ] Write unit tests for Service model

### 1.2 Create TaskTemplate Model
- [ ] Create `backend/models/TaskTemplate.js`
- [ ] Define schema with serviceId, companyId, title, description, type, difficulty, checklist
- [ ] Add indexes for service and company queries
- [ ] Add validation for required fields
- [ ] Write unit tests for TaskTemplate model

### 1.3 Enhance Task Model
- [ ] Add taskOrigin field (template/ad_hoc)
- [ ] Add templateId reference
- [ ] Add ticketId reference
- [ ] Add assignedTo field
- [ ] Add completedBy and completedAt fields
- [ ] Add taskDuration field
- [ ] Add notes field
- [ ] Add statusHistory array
- [ ] Create migration script for existing tasks
- [ ] Write unit tests for enhanced Task model

### 1.4 Create or Enhance Ticket Model
- [ ] Create `backend/models/Ticket.js` if not exists
- [ ] Define schema with companyId, serviceId, title, description, status
- [ ] Add indexes for company and service queries
- [ ] Add validation for required fields
- [ ] Write unit tests for Ticket model

## Phase 2: Backend API Endpoints

### 2.1 Service Management Endpoints
- [ ] POST /api/services - Create service
- [ ] GET /api/services - List services
- [ ] GET /api/services/:id - Get service details
- [ ] PUT /api/services/:id - Update service
- [ ] DELETE /api/services/:id - Delete service
- [ ] Add authentication middleware
- [ ] Add company scoping middleware
- [ ] Write integration tests for all endpoints

### 2.2 Task Template Endpoints
- [ ] POST /api/services/:serviceId/templates - Create template
- [ ] GET /api/services/:serviceId/templates - List templates
- [ ] GET /api/templates/:id - Get template details
- [ ] PUT /api/templates/:id - Update template
- [ ] DELETE /api/templates/:id - Delete template
- [ ] Add authentication middleware
- [ ] Add company scoping middleware
- [ ] Write integration tests for all endpoints

### 2.3 Task Management Endpoints
- [ ] POST /api/tickets/:ticketId/tasks - Create ad-hoc task
- [ ] GET /api/tickets/:ticketId/tasks - List tasks with filtering
- [ ] GET /api/tasks/:id - Get task details
- [ ] PUT /api/tasks/:id - Update task
- [ ] PUT /api/tasks/:id/assign - Assign task to employee
- [ ] PUT /api/tasks/:id/status - Change task status
- [ ] POST /api/tasks/:id/checklist/:itemIndex/complete - Complete checklist item
- [ ] Add authentication middleware
- [ ] Add authorization checks
- [ ] Write integration tests for all endpoints

### 2.4 Ticket Management Endpoints
- [ ] POST /api/tickets - Create ticket with optional service
- [ ] GET /api/tickets - List tickets with filtering
- [ ] GET /api/tickets/:id - Get ticket with tasks
- [ ] Implement task cloning logic in ticket creation
- [ ] Add authentication middleware
- [ ] Add company scoping middleware
- [ ] Write integration tests for all endpoints

### 2.5 Reporting Endpoints
- [ ] GET /api/reports/tasks - Generate task completion report
- [ ] GET /api/reports/tasks/export - Export report as CSV/PDF
- [ ] Implement report generation logic
- [ ] Add filtering by date range, service, company
- [ ] Add authentication middleware
- [ ] Write integration tests for reporting

## Phase 3: Backend Business Logic

### 3.1 Task Cloning Service
- [ ] Create `backend/services/taskCloningService.js`
- [ ] Implement cloneTemplateTasksForTicket function
- [ ] Handle template not found errors
- [ ] Handle task creation errors
- [ ] Write unit tests for cloning logic
- [ ] Write integration tests for full workflow

### 3.2 Task Status Workflow Service
- [ ] Create `backend/services/taskStatusService.js`
- [ ] Implement status transition validation
- [ ] Implement status change recording
- [ ] Implement duration calculation
- [ ] Handle invalid transitions
- [ ] Write unit tests for status workflow
- [ ] Write integration tests for transitions

### 3.3 Task Notification Service
- [ ] Extend existing notification service
- [ ] Implement task assignment notification
- [ ] Implement task completion notification
- [ ] Implement task status change notification
- [ ] Write unit tests for notifications

### 3.4 Task Reporting Service
- [ ] Create `backend/services/taskReportingService.js`
- [ ] Implement task completion report generation
- [ ] Implement template vs ad-hoc breakdown
- [ ] Implement employee performance metrics
- [ ] Implement CSV export
- [ ] Implement PDF export
- [ ] Write unit tests for reporting logic

## Phase 4: Admin UI - Service and Template Management (Enhancements)

### 4.1 Add Service Management Section to Admin Task Management Screen
- [ ] Add new tab or section in `admin_task_management_screen.dart` for services
- [ ] Implement service list display
- [ ] Implement create service form
- [ ] Implement edit service form
- [ ] Implement delete service functionality
- [ ] Add search and sort functionality
- [ ] Add loading and error states
- [ ] Write widget tests

### 4.2 Add Template Management Section to Admin Task Management Screen
- [ ] Add template list display in service section
- [ ] Implement create template form
- [ ] Implement edit template form
- [ ] Implement delete template functionality
- [ ] Add checklist builder
- [ ] Add loading and error states
- [ ] Write widget tests

### 4.3 Enhance Ticket Creation in Admin Task Management Screen
- [ ] Add service dropdown to ticket creation form
- [ ] Add template preview showing tasks that will be created
- [ ] Implement task cloning on ticket creation
- [ ] Add loading state during cloning
- [ ] Add error handling
- [ ] Write widget tests

## Phase 5: Admin UI - Task Assignment Page Enhancements

### 5.1 Enhance Task Display in Admin Task Management Screen
- [ ] Add task origin badge (template/ad-hoc) to task display
- [ ] Add checklist progress indicator (X/Y items completed)
- [ ] Add status history display
- [ ] Add assigned employee display
- [ ] Add task duration display
- [ ] Update task card styling
- [ ] Write widget tests

### 5.2 Enhance Task Assignment Features in Admin Task Management Screen
- [ ] Add assign task to employee functionality
- [ ] Add reassign task functionality
- [ ] Add change task status functionality (pending → in_progress → completed → reviewed → closed)
- [ ] Add block task with reason functionality
- [ ] Add task status history tracking
- [ ] Write widget tests

### 5.3 Add Ad-Hoc Task Creation to Admin Task Management Screen
- [ ] Add "Add Ad-Hoc Task" button to task list
- [ ] Implement ad-hoc task form (title, description, type, difficulty, checklist)
- [ ] Add validation
- [ ] Add submit button
- [ ] Add cancel button
- [ ] Add loading state
- [ ] Add error handling
- [ ] Write widget tests

### 5.4 Enhance Task Filtering in Admin Task Management Screen
- [ ] Add filter by status (pending, in_progress, completed, blocked, reviewed, closed)
- [ ] Add filter by type (general, inspection, maintenance, delivery, other)
- [ ] Add filter by task origin (template, ad-hoc)
- [ ] Add filter by assigned employee
- [ ] Add search by title/description
- [ ] Add filter reset button
- [ ] Add filter persistence
- [ ] Write widget tests

### 5.5 Enhance Task Details Display in Admin Task Management Screen
- [ ] Add side panel or modal for full task details
- [ ] Display full task information
- [ ] Display checklist items with completion status
- [ ] Display status history
- [ ] Display notes and attachments
- [ ] Add action buttons
- [ ] Write widget tests

## Phase 6: Employee UI - Task Completion Page Enhancements

### 6.1 Enhance Task Display in Employee Task List Screen
- [ ] Add task type and difficulty badges
- [ ] Add checklist progress indicator
- [ ] Add task origin display (if visible to employees)
- [ ] Update task card styling
- [ ] Write widget tests

### 6.2 Enhance Task Completion Features in Employee Task List Screen
- [ ] Add "Mark as In Progress" button
- [ ] Add "Mark as Completed" button
- [ ] Add interactive checklist with checkboxes
- [ ] Record completion timestamp for each checklist item
- [ ] Add loading state during status updates
- [ ] Add error handling
- [ ] Write widget tests

### 6.3 Add Notes Section to Employee Task Details
- [ ] Add notes section to task details view
- [ ] Implement text input for new notes
- [ ] Display list of existing notes with timestamps
- [ ] Add edit/delete actions for own notes
- [ ] Write widget tests

### 6.4 Add Attachment Section to Employee Task Details
- [ ] Add attachment section to task details view
- [ ] Implement camera button to take photos
- [ ] Implement file picker for documents
- [ ] Display gallery of attached images
- [ ] Display list of attached documents
- [ ] Add delete actions
- [ ] Write widget tests

### 6.5 Enhance Task Filtering in Employee Task List Screen
- [ ] Add filter by status
- [ ] Add search by title/description
- [ ] Add filter reset button
- [ ] Add filter persistence
- [ ] Write widget tests

### 6.6 Add Task Completion Tracking to Employee Task Details
- [ ] Display task status clearly
- [ ] Display overall task completion progress
- [ ] Display checklist completion progress
- [ ] Display task duration (if applicable)
- [ ] Write widget tests

## Phase 7: Integration and Testing

### 7.1 End-to-End Testing
- [ ] Test admin creates service
- [ ] Test admin creates templates
- [ ] Test admin creates ticket with service
- [ ] Test tasks are cloned correctly
- [ ] Test admin assigns tasks to employees
- [ ] Test employee completes tasks
- [ ] Test task status workflow
- [ ] Test checklist completion
- [ ] Test ad-hoc task addition
- [ ] Test multi-company isolation

### 7.2 Performance Testing
- [ ] Test task cloning performance with large templates
- [ ] Test task list loading with many tasks
- [ ] Test report generation performance
- [ ] Test query performance with indexes
- [ ] Optimize slow queries

### 7.3 Security Testing
- [ ] Test multi-company isolation
- [ ] Test authorization checks
- [ ] Test employee can only access own tasks
- [ ] Test admin can access all company tasks
- [ ] Test input validation

### 7.4 Reporting Testing
- [ ] Test report generation accuracy
- [ ] Test template vs ad-hoc breakdown
- [ ] Test employee performance metrics
- [ ] Test CSV export
- [ ] Test PDF export

## Phase 8: Documentation and Deployment

### 8.1 API Documentation
- [ ] Document all new endpoints
- [ ] Document request/response formats
- [ ] Document error codes
- [ ] Document authentication requirements
- [ ] Create API examples

### 8.2 User Documentation
- [ ] Create admin guide for service management
- [ ] Create admin guide for template management
- [ ] Create admin guide for task assignment
- [ ] Create employee guide for task completion
- [ ] Create reporting guide

### 8.3 Deployment
- [ ] Create database migration scripts
- [ ] Test migrations on staging
- [ ] Deploy backend changes
- [ ] Deploy admin UI changes
- [ ] Deploy employee UI changes
- [ ] Monitor for errors
- [ ] Gather user feedback

## Acceptance Criteria for Completion

- [ ] All 22 requirements from requirements.md are implemented
- [ ] All unit tests pass (>80% coverage)
- [ ] All integration tests pass
- [ ] All E2E tests pass
- [ ] No breaking changes to existing functionality
- [ ] Multi-company isolation verified
- [ ] Performance meets requirements
- [ ] Security review completed
- [ ] Documentation complete
- [ ] User acceptance testing passed
