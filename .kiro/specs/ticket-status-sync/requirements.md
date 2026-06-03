# Requirements Document

## Introduction

This document specifies the requirements for automatic synchronization of client ticket status based on linked task status changes in the FieldCheck application. The feature ensures that when employees update task status through the mobile app, the corresponding client ticket status is automatically updated and clients are notified via email.

## Glossary

- **Client_Ticket**: A support request submitted by a client through the public ticket submission form, tracked by a unique ticket number (format: RNG-YYYYMMDD-XXXX)
- **Linked_Task**: An internal employee task created and linked to a Client_Ticket when the ticket is assigned to one or more employees
- **Task_Status**: The current state of a Linked_Task, with possible values: pending, in_progress, completed, created, assigned, accepted, blocked, reviewed, closed
- **Ticket_Status**: The current state of a Client_Ticket, with possible values: open, in_progress, pending_review, completed, closed, expired
- **Status_Synchronization_Service**: The backend service responsible for monitoring task status changes and updating corresponding ticket status
- **Email_Notification_Service**: The service responsible for sending status update emails to clients
- **UserTask**: A junction entity representing the assignment of a Linked_Task to a specific employee, with its own status tracking
- **Status_Mapping**: The direct 1:1 correspondence between Task_Status values and Ticket_Status values

## Requirements

### Requirement 1

**User Story:** As a client, I want to receive automatic email notifications when my ticket status changes, so that I stay informed about the progress of my support request without having to manually check the tracking page.

#### Acceptance Criteria

1. WHEN a Linked_Task status changes from any value to "in_progress", THE Status_Synchronization_Service SHALL update the corresponding Client_Ticket status to "in_progress"
2. WHEN a Linked_Task status changes from any value to "pending_review", THE Status_Synchronization_Service SHALL update the corresponding Client_Ticket status to "pending_review"
3. WHEN a Linked_Task status changes from any value to "completed", THE Status_Synchronization_Service SHALL update the corresponding Client_Ticket status to "completed"
4. WHEN a Linked_Task status changes from any value to "closed", THE Status_Synchronization_Service SHALL update the corresponding Client_Ticket status to "closed"
5. WHEN a Client_Ticket status is updated by the Status_Synchronization_Service, THE Email_Notification_Service SHALL send a status update email to the client email address within 60 seconds

### Requirement 2

**User Story:** As a system administrator, I want the status synchronization to happen automatically in the background, so that employees can focus on their work without manual status updates and clients receive timely notifications.

#### Acceptance Criteria

1. WHEN a Linked_Task status is modified through any API endpoint, THE Status_Synchronization_Service SHALL detect the change within 5 seconds
2. WHEN the Status_Synchronization_Service detects a task status change, THE service SHALL execute the synchronization logic without requiring manual intervention
3. WHEN the Status_Synchronization_Service updates a Client_Ticket status, THE service SHALL record the timestamp of the update in the Client_Ticket updatedAt field
4. WHEN the Status_Synchronization_Service updates a Client_Ticket status, THE service SHALL preserve all existing Client_Ticket data except the status field and updatedAt timestamp

### Requirement 3

**User Story:** As a system administrator, I want the synchronization service to handle errors gracefully, so that temporary failures do not prevent ticket updates and the system remains stable.

#### Acceptance Criteria

1. IF the Status_Synchronization_Service fails to update a Client_Ticket status due to a database error, THEN THE service SHALL log the error with ticket number, task ID, attempted status change, and error message
2. IF the Email_Notification_Service fails to send a status update email, THEN THE service SHALL log the error with ticket number, client email, and error message
3. IF the Email_Notification_Service fails to send a status update email, THEN THE service SHALL NOT prevent the Client_Ticket status update from being saved
4. IF the Status_Synchronization_Service encounters an error, THEN THE service SHALL NOT throw an exception that interrupts the task status update operation
5. WHEN the Status_Synchronization_Service logs an error, THE log entry SHALL include a severity level of "error" and a timestamp

### Requirement 4

**User Story:** As a developer, I want the status synchronization to use a direct 1:1 mapping between task and ticket statuses, so that the logic is simple, predictable, and easy to maintain.

#### Acceptance Criteria

1. THE Status_Synchronization_Service SHALL map Task_Status "in_progress" to Ticket_Status "in_progress"
2. THE Status_Synchronization_Service SHALL map Task_Status "pending_review" to Ticket_Status "pending_review"
3. THE Status_Synchronization_Service SHALL map Task_Status "completed" to Ticket_Status "completed"
4. THE Status_Synchronization_Service SHALL map Task_Status "closed" to Ticket_Status "closed"
5. WHEN a Linked_Task status changes to a value not in the Status_Mapping (pending, created, assigned, accepted, blocked, reviewed), THE Status_Synchronization_Service SHALL NOT update the Client_Ticket status

### Requirement 5

**User Story:** As a system administrator, I want the synchronization to work correctly with multi-employee assignments, so that ticket status reflects the overall progress when multiple employees are working on the same ticket.

#### Acceptance Criteria

1. WHEN a Client_Ticket has multiple assigned employees through separate UserTask records, THE Status_Synchronization_Service SHALL update the Client_Ticket status based on the Linked_Task status
2. WHEN a Linked_Task has multiple UserTask assignments with different individual statuses, THE Status_Synchronization_Service SHALL use the Linked_Task status as the authoritative source for Client_Ticket status updates
3. WHEN the Status_Synchronization_Service updates a Client_Ticket status, THE service SHALL NOT modify the assignedEmployeeIds array or assignedEmployeeId field

### Requirement 6

**User Story:** As a client, I want to receive clear and informative email notifications, so that I understand what the status change means and what to expect next.

#### Acceptance Criteria

1. WHEN the Email_Notification_Service sends a status update email, THE email SHALL include the ticket number in the subject line
2. WHEN the Email_Notification_Service sends a status update email, THE email SHALL include the new status value in human-readable format in the email body
3. WHEN the Email_Notification_Service sends a status update email, THE email SHALL include a direct link to the ticket tracking page with the authentication token
4. WHEN the Email_Notification_Service sends a status update email for status "completed", THE email SHALL include instructions for submitting a rating
5. WHEN the Email_Notification_Service sends a status update email, THE email SHALL be sent to the clientEmail address stored in the Client_Ticket record

### Requirement 7

**User Story:** As a developer, I want the synchronization service to be implemented as a reusable module, so that it can be easily integrated into existing task update workflows without duplicating code.

#### Acceptance Criteria

1. THE Status_Synchronization_Service SHALL be implemented as a standalone JavaScript module that exports a synchronization function
2. WHEN the synchronization function is called with a task ID parameter, THE function SHALL retrieve the Linked_Task and associated Client_Ticket
3. WHEN the synchronization function is called with a task ID that has no linked Client_Ticket, THE function SHALL return without error
4. THE synchronization function SHALL accept a task ID as a required parameter and return a Promise that resolves when synchronization is complete
5. THE synchronization function SHALL be callable from any task update controller or service without requiring additional configuration

### Requirement 8

**User Story:** As a system administrator, I want comprehensive logging of all synchronization operations, so that I can monitor system health, troubleshoot issues, and audit status changes.

#### Acceptance Criteria

1. WHEN the Status_Synchronization_Service successfully updates a Client_Ticket status, THE service SHALL log an info-level message with ticket number, old status, new status, and task ID
2. WHEN the Email_Notification_Service successfully sends a status update email, THE service SHALL log an info-level message with ticket number, client email, and new status
3. WHEN the Status_Synchronization_Service begins processing a task status change, THE service SHALL log a debug-level message with task ID and new task status
4. WHEN the synchronization function is called with a task ID that has no linked Client_Ticket, THE service SHALL log a debug-level message indicating no synchronization is needed
5. THE Status_Synchronization_Service SHALL use the console.log function for info-level logs and console.error function for error-level logs

### Requirement 9

**User Story:** As a system administrator, I want the synchronization to respect existing ticket status constraints, so that tickets cannot be moved to invalid states and business rules are enforced.

#### Acceptance Criteria

1. WHEN the Status_Synchronization_Service attempts to update a Client_Ticket status to a value not in the Ticket_Status enum (open, in_progress, pending_review, completed, closed, expired), THE service SHALL log an error and not update the ticket
2. WHEN a Client_Ticket status is "closed" or "expired", THE Status_Synchronization_Service SHALL NOT update the status to any other value
3. WHEN the Status_Synchronization_Service updates a Client_Ticket status, THE service SHALL trigger the Mongoose pre-save hook to update the updatedAt timestamp
4. THE Status_Synchronization_Service SHALL use the Mongoose save method to persist Client_Ticket status changes to ensure all model validations and hooks are executed

### Requirement 10

**User Story:** As a developer, I want the synchronization service to be integrated into existing task update endpoints, so that status synchronization happens automatically whenever tasks are updated through the API.

#### Acceptance Criteria

1. WHEN the task status update API endpoint successfully updates a Linked_Task status, THE endpoint SHALL call the Status_Synchronization_Service synchronization function with the task ID
2. WHEN the UserTask status update API endpoint successfully updates a UserTask status, THE endpoint SHALL call the Status_Synchronization_Service synchronization function with the parent task ID
3. WHEN the synchronization function is called from an API endpoint, THE API endpoint SHALL NOT wait for the synchronization to complete before sending the HTTP response
4. WHEN the synchronization function is called from an API endpoint, THE function SHALL execute asynchronously using setImmediate or process.nextTick
5. IF the synchronization function throws an error, THE error SHALL NOT cause the API endpoint to return an error response to the client
