# Requirements Document: Task Template System

## Introduction

The Task Template System enables FieldCheck to support service-based task management for multi-tenant companies. Instead of generic tasks, administrators can define predefined task templates for specific services (e.g., "Aircon Cleaning", "Plumbing Repair"). When a ticket is created for a service, tasks are automatically cloned from the service's template. This system maintains flexibility by allowing ad-hoc tasks to be added without breaking template associations, while tracking the origin of each task.

This specification also includes a comprehensive remastering of the task pages on both the admin and employee sides, improving task assignment workflows, task completion tracking, and reporting capabilities to reflect the new template-based task structure.

## Glossary

- **Service**: A type of work offered by a company (e.g., "Aircon Cleaning", "Plumbing Repair")
- **Service_Profile**: Configuration for a service including metadata and associated task templates
- **Task_Template**: A predefined blueprint of a task linked to a Service (e.g., "Inspect filters", "Clean coils")
- **Ticket**: An instance of work created for a company and service (represents a customer job)
- **Template_Task**: A task created by cloning from a Task_Template when a ticket is created
- **Ad_Hoc_Task**: A task manually added to a ticket after creation, not from a template
- **Task_Origin**: Metadata indicating whether a task came from a template or was added ad-hoc
- **Admin_Dashboard**: The administrative interface for managing services and templates
- **Employee_App**: The mobile/web interface used by field employees to view and complete tasks
- **Company**: A tenant organization using the FieldCheck system
- **Admin_User**: A user with administrative privileges for a company
- **Employee_User**: A field employee assigned to complete tasks

## Requirements

### Requirement 1: Create Service Profiles

**User Story:** As an admin, I want to create service profiles for my company, so that I can define the types of work my company offers.

#### Acceptance Criteria

1. THE Admin_Dashboard SHALL provide a form to create a new Service_Profile
2. WHEN creating a Service_Profile, THE Admin_Dashboard SHALL require a service name
3. WHEN creating a Service_Profile, THE Admin_Dashboard SHALL allow an optional description
4. THE Service_Profile SHALL be scoped to the admin's Company
5. WHEN a Service_Profile is created successfully, THE Admin_Dashboard SHALL display a confirmation message
6. WHEN a Service_Profile creation fails, THE Admin_Dashboard SHALL display an error message with the reason

### Requirement 2: Edit Service Profiles

**User Story:** As an admin, I want to edit existing service profiles, so that I can update service information as my business needs change.

#### Acceptance Criteria

1. THE Admin_Dashboard SHALL display a list of existing Service_Profiles for the company
2. WHEN an admin selects a Service_Profile to edit, THE Admin_Dashboard SHALL load the profile details
3. THE Admin_Dashboard SHALL allow editing of the service name and description
4. WHEN changes are saved, THE Admin_Dashboard SHALL persist the updates
5. WHEN a Service_Profile is updated successfully, THE Admin_Dashboard SHALL display a confirmation message
6. WHEN an update fails, THE Admin_Dashboard SHALL display an error message

### Requirement 3: Delete Service Profiles

**User Story:** As an admin, I want to delete service profiles that are no longer needed, so that I can keep my service list clean.

#### Acceptance Criteria

1. THE Admin_Dashboard SHALL provide a delete option for each Service_Profile
2. WHEN delete is selected, THE Admin_Dashboard SHALL display a confirmation dialog
3. THE Admin_Dashboard SHALL warn if the Service_Profile has associated Task_Templates
4. WHEN deletion is confirmed, THE Admin_Dashboard SHALL remove the Service_Profile
5. WHEN a Service_Profile is deleted, THE Admin_Dashboard SHALL also delete all associated Task_Templates
6. WHEN deletion is successful, THE Admin_Dashboard SHALL display a confirmation message

### Requirement 4: Create Task Templates

**User Story:** As an admin, I want to define task templates for each service, so that tickets created for that service automatically include the predefined tasks.

#### Acceptance Criteria

1. THE Admin_Dashboard SHALL provide a form to create a Task_Template for a selected Service_Profile
2. WHEN creating a Task_Template, THE Admin_Dashboard SHALL require a task title
3. WHEN creating a Task_Template, THE Admin_Dashboard SHALL allow an optional description
4. WHEN creating a Task_Template, THE Admin_Dashboard SHALL allow setting task type (general, inspection, maintenance, delivery, other)
5. WHEN creating a Task_Template, THE Admin_Dashboard SHALL allow setting difficulty level (easy, medium, hard)
6. WHEN creating a Task_Template, THE Admin_Dashboard SHALL allow defining a checklist with multiple items
7. WHEN a Task_Template is created successfully, THE Admin_Dashboard SHALL display a confirmation message

### Requirement 5: Edit Task Templates

**User Story:** As an admin, I want to edit existing task templates, so that I can refine the predefined tasks for a service.

#### Acceptance Criteria

1. THE Admin_Dashboard SHALL display a list of Task_Templates for each Service_Profile
2. WHEN an admin selects a Task_Template to edit, THE Admin_Dashboard SHALL load the template details
3. THE Admin_Dashboard SHALL allow editing of title, description, type, difficulty, and checklist
4. WHEN changes are saved, THE Admin_Dashboard SHALL persist the updates
5. WHEN a Task_Template is updated successfully, THE Admin_Dashboard SHALL display a confirmation message
6. WHEN an update fails, THE Admin_Dashboard SHALL display an error message

### Requirement 6: Delete Task Templates

**User Story:** As an admin, I want to delete task templates that are no longer needed, so that I can keep templates current.

#### Acceptance Criteria

1. THE Admin_Dashboard SHALL provide a delete option for each Task_Template
2. WHEN delete is selected, THE Admin_Dashboard SHALL display a confirmation dialog
3. WHEN deletion is confirmed, THE Admin_Dashboard SHALL remove the Task_Template
4. WHEN a Task_Template is deleted, THE Admin_Dashboard SHALL NOT affect existing tasks already cloned from that template
5. WHEN deletion is successful, THE Admin_Dashboard SHALL display a confirmation message

### Requirement 7: Automatic Task Cloning on Ticket Creation

**User Story:** As an admin, I want tasks to be automatically created when a ticket is created, so that employees immediately see all required work.

#### Acceptance Criteria

1. WHEN a Ticket is created with a selected Service_Profile, THE System SHALL clone all Task_Templates associated with that Service_Profile
2. THE System SHALL create Task instances with the same title, description, type, difficulty, and checklist as the Task_Template
3. EACH cloned Task SHALL be marked with Task_Origin indicating it came from a template
4. EACH cloned Task SHALL reference the original Task_Template for traceability
5. WHEN task cloning completes, THE System SHALL associate all cloned tasks with the Ticket
6. IF task cloning fails, THE System SHALL log the error and notify the admin

### Requirement 8: Track Task Origin

**User Story:** As an admin, I want to know which tasks came from templates and which were added manually, so that I can understand task composition.

#### Acceptance Criteria

1. EACH Task SHALL store a Task_Origin field indicating "template" or "ad_hoc"
2. EACH Task created from a template SHALL store a reference to the original Task_Template
3. THE Admin_Dashboard SHALL display Task_Origin information for each task in a ticket
4. THE Admin_Dashboard SHALL visually distinguish template tasks from ad-hoc tasks
5. WHEN filtering tasks, THE Admin_Dashboard SHALL allow filtering by Task_Origin

### Requirement 9: Add Ad-Hoc Tasks to Tickets

**User Story:** As an admin, I want to add tasks to a ticket after creation, so that I can handle unexpected work without breaking template associations.

#### Acceptance Criteria

1. THE Admin_Dashboard SHALL provide a form to add a new task to an existing Ticket
2. WHEN adding a task, THE Admin_Dashboard SHALL require a task title
3. WHEN adding a task, THE Admin_Dashboard SHALL allow optional description, type, difficulty, and checklist
4. WHEN a task is added, THE System SHALL mark it with Task_Origin as "ad_hoc"
5. WHEN a task is added, THE System SHALL NOT associate it with any Task_Template
6. WHEN an ad-hoc task is added successfully, THE Admin_Dashboard SHALL display a confirmation message

### Requirement 10: Multi-Tenancy Isolation

**User Story:** As an admin, I want my company's services and templates to be isolated from other companies, so that I only see and manage my own data.

#### Acceptance Criteria

1. EACH Service_Profile SHALL be scoped to a specific Company
2. EACH Task_Template SHALL be scoped to a specific Company through its Service_Profile
3. THE Admin_Dashboard SHALL only display Service_Profiles and Task_Templates for the admin's Company
4. THE System SHALL prevent admins from accessing or modifying services from other companies
5. WHEN a Ticket is created, THE System SHALL only show Service_Profiles from the ticket's Company

### Requirement 11: Employee Task Display

**User Story:** As an employee, I want to see all tasks for a ticket, so that I know what work needs to be completed.

#### Acceptance Criteria

1. THE Employee_App SHALL display all tasks associated with a Ticket
2. THE Employee_App SHALL show task title, description, type, and difficulty
3. THE Employee_App SHALL display the checklist items for each task
4. THE Employee_App SHALL show task status (pending, in_progress, completed, etc.)
5. THE Employee_App SHALL display tasks in a clear, organized list format

### Requirement 12: Employee Task Completion

**User Story:** As an employee, I want to mark tasks as complete and update checklist items, so that I can track my progress on a ticket.

#### Acceptance Criteria

1. THE Employee_App SHALL allow marking a task as "in_progress"
2. THE Employee_App SHALL allow marking a task as "completed"
3. THE Employee_App SHALL allow checking off individual checklist items
4. WHEN a checklist item is checked, THE System SHALL record the completion timestamp
5. WHEN all checklist items are checked, THE Employee_App SHALL suggest marking the task as completed
6. WHEN a task status changes, THE System SHALL update the task record immediately

### Requirement 13: Preserve Existing Task Functionality

**User Story:** As a system, I want to maintain backward compatibility with existing tasks, so that current operations are not disrupted.

#### Acceptance Criteria

1. THE System SHALL continue to support creating tasks without a Service_Profile
2. EXISTING Tasks without Task_Origin SHALL default to "ad_hoc" when queried
3. THE System SHALL NOT require Task_Origin for existing tasks
4. WHEN querying tasks, THE System SHALL handle both tasks with and without Task_Origin
5. THE System SHALL maintain all existing task fields and functionality

### Requirement 14: Service and Template Listing

**User Story:** As an admin, I want to view all services and their templates in an organized way, so that I can manage them efficiently.

#### Acceptance Criteria

1. THE Admin_Dashboard SHALL display a list of all Service_Profiles for the company
2. FOR each Service_Profile, THE Admin_Dashboard SHALL display the count of associated Task_Templates
3. WHEN a Service_Profile is expanded, THE Admin_Dashboard SHALL display all associated Task_Templates
4. THE Admin_Dashboard SHALL allow sorting services by name or creation date
5. THE Admin_Dashboard SHALL provide search functionality to find services by name

### Requirement 15: Ticket Service Selection

**User Story:** As an admin, I want to select a service when creating a ticket, so that the appropriate tasks are automatically loaded.

#### Acceptance Criteria

1. WHEN creating a Ticket, THE Admin_Dashboard SHALL display a dropdown of available Service_Profiles
2. WHEN a Service_Profile is selected, THE Admin_Dashboard SHALL display a preview of tasks that will be created
3. WHEN a Ticket is created with a selected Service_Profile, THE System SHALL automatically clone all associated Task_Templates
4. IF no Service_Profile is selected, THE System SHALL allow creating a ticket without predefined tasks
5. WHEN a Ticket is created, THE Admin_Dashboard SHALL display the created tasks immediately

### Requirement 16: Admin Task Assignment Page Redesign

**User Story:** As an admin, I want an improved task assignment interface, so that I can efficiently assign tasks to employees and track their progress.

#### Acceptance Criteria

1. THE Admin_Dashboard SHALL display a dedicated task assignment page showing all tasks for a ticket
2. THE Admin_Dashboard SHALL display task details including title, description, type, difficulty, and checklist items
3. THE Admin_Dashboard SHALL show Task_Origin (template or ad-hoc) for each task
4. THE Admin_Dashboard SHALL display the current status of each task (pending, in_progress, completed, etc.)
5. THE Admin_Dashboard SHALL show which employee is assigned to each task
6. THE Admin_Dashboard SHALL allow assigning tasks to employees directly from the page
7. THE Admin_Dashboard SHALL allow reassigning tasks to different employees
8. THE Admin_Dashboard SHALL display task completion progress including checklist item status
9. WHEN a task status changes, THE Admin_Dashboard SHALL update the display in real-time
10. THE Admin_Dashboard SHALL allow filtering tasks by status, type, or assignment status

### Requirement 17: Employee Task Completion Page Redesign

**User Story:** As an employee, I want an improved task completion interface, so that I can efficiently complete tasks and track my progress on a ticket.

#### Acceptance Criteria

1. THE Employee_App SHALL display a dedicated task completion page showing all tasks for a ticket
2. THE Employee_App SHALL display task details including title, description, type, difficulty, and checklist items
3. THE Employee_App SHALL show task status clearly (pending, in_progress, completed, etc.)
4. THE Employee_App SHALL allow marking a task as "in_progress" with a single action
5. THE Employee_App SHALL allow marking a task as "completed" with a single action
6. THE Employee_App SHALL display an interactive checklist for each task
7. WHEN a checklist item is checked, THE Employee_App SHALL record the completion timestamp
8. THE Employee_App SHALL show overall task completion progress for the ticket
9. THE Employee_App SHALL allow adding notes or comments to tasks
10. THE Employee_App SHALL allow attaching images or documents to tasks

### Requirement 18: Task Completion Tracking

**User Story:** As an admin, I want to track task completion details, so that I can monitor work progress and identify bottlenecks.

#### Acceptance Criteria

1. THE System SHALL record the timestamp when a task status changes
2. THE System SHALL record the employee who completed each task
3. THE System SHALL record the timestamp when each checklist item is completed
4. THE System SHALL track task duration (time from assignment to completion)
5. THE System SHALL store task notes and attachments added by employees
6. WHEN querying task history, THE System SHALL return all completion details

### Requirement 19: Task Reports with Template Information

**User Story:** As an admin, I want reports that show task completion metrics including template vs ad-hoc breakdown, so that I can analyze work patterns and template effectiveness.

#### Acceptance Criteria

1. THE Report_System SHALL generate task completion reports showing all tasks for a ticket
2. THE Report_System SHALL display Task_Origin (template or ad-hoc) for each task in reports
3. THE Report_System SHALL show completion rates for template tasks vs ad-hoc tasks
4. THE Report_System SHALL display average task completion time by task type
5. THE Report_System SHALL show which tasks are frequently added as ad-hoc (indicating template gaps)
6. THE Report_System SHALL allow filtering reports by Service_Profile
7. THE Report_System SHALL allow filtering reports by date range
8. THE Report_System SHALL display employee performance metrics including tasks completed and average completion time
9. THE Report_System SHALL show checklist completion rates for each task
10. WHEN exporting reports, THE Report_System SHALL include all template and completion information

### Requirement 20: Task Status Workflow

**User Story:** As an admin, I want a clear task status workflow, so that tasks progress through defined states from creation to completion.

#### Acceptance Criteria

1. THE System SHALL support the following task statuses: pending, in_progress, completed, blocked, reviewed, closed
2. WHEN a task is created, THE System SHALL set its status to "pending"
3. WHEN an employee starts work on a task, THE System SHALL allow changing status to "in_progress"
4. WHEN an employee finishes work on a task, THE System SHALL allow changing status to "completed"
5. IF a task cannot be completed, THE System SHALL allow changing status to "blocked" with a reason
6. WHEN a task is blocked, THE Admin_Dashboard SHALL display the block reason
7. WHEN a task is completed, THE Admin_Dashboard SHALL allow reviewing and changing status to "reviewed"
8. WHEN a task is reviewed, THE Admin_Dashboard SHALL allow changing status to "closed"
9. THE System SHALL prevent invalid status transitions
10. THE System SHALL record the timestamp and user for each status change

### Requirement 21: Task Assignment Notifications

**User Story:** As an employee, I want to be notified when tasks are assigned to me, so that I can start work promptly.

#### Acceptance Criteria

1. WHEN a task is assigned to an employee, THE System SHALL send a notification to the employee
2. THE Notification SHALL include the task title, description, and ticket information
3. THE Notification SHALL indicate whether the task is from a template or ad-hoc
4. THE Employee_App SHALL display the notification in the notification center
5. WHEN the employee taps the notification, THE Employee_App SHALL navigate to the task completion page
6. THE System SHALL track whether the employee has viewed the notification

### Requirement 22: Task Filtering and Search

**User Story:** As an admin or employee, I want to filter and search tasks, so that I can quickly find specific tasks.

#### Acceptance Criteria

1. THE Admin_Dashboard SHALL allow filtering tasks by status (pending, in_progress, completed, blocked, reviewed, closed)
2. THE Admin_Dashboard SHALL allow filtering tasks by type (general, inspection, maintenance, delivery, other)
3. THE Admin_Dashboard SHALL allow filtering tasks by Task_Origin (template, ad-hoc)
4. THE Admin_Dashboard SHALL allow filtering tasks by assigned employee
5. THE Admin_Dashboard SHALL allow searching tasks by title or description
6. THE Employee_App SHALL allow filtering tasks by status
7. THE Employee_App SHALL allow searching tasks by title or description
8. WHEN filters are applied, THE System SHALL update the task list in real-time
9. THE System SHALL allow saving filter presets for quick access
10. THE System SHALL remember the last used filters for the user
