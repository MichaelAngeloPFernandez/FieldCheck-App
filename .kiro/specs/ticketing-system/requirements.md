# Requirements Document

## Introduction

The FieldCheck App currently has a `Ticket`, `TicketTemplate`, and supporting infrastructure (routes, service, seeds) in place, but the admin-facing ticketing workflow is incomplete. Admins cannot yet create tickets through a guided UI that presents a dropdown of available service templates, pre-populates the form from the chosen template's JSON Schema, and assigns an employee at creation time.

This feature delivers a **proper ticketing system** for the FieldCheck App. It enables admins to create tickets by selecting a service type from a dropdown (populated from `TicketTemplate` records), fill in the dynamic form rendered from the template's `json_schema`, and optionally assign an employee at creation time. Employees can view their assigned tickets, update status, and submit completion data. The system is designed to be extensible beyond aircon cleaning to any field service type.

The existing `Task`/`UserTask` management system is **not modified** — tickets are a parallel, template-driven workflow.

---

## Glossary

- **Admin**: A user with `role: 'admin'` in the system.
- **Employee**: A user with `role: 'employee'` in the system.
- **Ticket**: A single unit of field work created from a `TicketTemplate`, stored in the `Ticket` collection.
- **TicketTemplate**: A document in the `TicketTemplate` collection that defines the service type name, JSON Schema form, workflow transitions, and SLA for a category of work (e.g., Aircon Cleaning).
- **Service_Type**: The human-readable name of a `TicketTemplate` (e.g., "Aircon Cleaning", "Electrical Inspection").
- **Ticket_Form**: The dynamic form rendered on the client from a `TicketTemplate`'s `json_schema`.
- **Assignee**: The `Employee` user linked to a `Ticket` via the `assignee` field.
- **Ticket_Status**: The current lifecycle state of a `Ticket` (e.g., `open`, `in_progress`, `completed`, `verified`, `closed`).
- **SLA_Deadline**: The computed due date/time for a ticket, derived from `TicketTemplate.sla_seconds` at creation time.
- **Ticket_Controller**: The Express route handler module responsible for ticket CRUD operations.
- **Template_Controller**: The Express route handler module responsible for `TicketTemplate` CRUD operations.
- **Ticket_Service**: The backend service layer (`ticketService.js`) that encapsulates ticket business logic.
- **Validation_Service**: The backend service (`validationService.js`) that validates ticket `data` against a template's `json_schema` using AJV.
- **Company**: The multi-tenant organisational unit that scopes templates and tickets.
- **Audit_Log**: An immutable record of every state-changing action on a ticket or template, stored via `auditService`.

---

## Requirements

### Requirement 1: Template Dropdown for Ticket Creation

**User Story:** As an admin, I want to select a service type from a dropdown when creating a ticket, so that the correct form and workflow are applied automatically.

#### Acceptance Criteria

1. WHEN an admin opens the ticket creation screen, THE Ticket_Controller SHALL return all active `TicketTemplate` records scoped to the admin's company (plus any `visibility: 'public'` templates) via `GET /api/templates`.
2. THE Ticket_Form SHALL render a dropdown list populated with the `name` field of each returned `TicketTemplate`.
3. WHEN an admin selects a `Service_Type` from the dropdown, THE Ticket_Form SHALL dynamically render input fields derived from the selected `TicketTemplate`'s `json_schema`.
4. WHEN a `TicketTemplate` has `isActive: false`, THE Template_Controller SHALL exclude it from the dropdown list.
5. IF no active `TicketTemplate` records exist for the admin's company, THEN THE Ticket_Form SHALL display a message indicating that no service types are available and prompt the admin to create a template first.

---

### Requirement 2: Admin Ticket Creation with Employee Assignment

**User Story:** As an admin, I want to create a ticket by filling in a service form and optionally assigning an employee, so that field work is dispatched with all required information.

#### Acceptance Criteria

1. WHEN an admin submits a new ticket, THE Ticket_Controller SHALL require `template_id` in the request body and return HTTP 400 if it is absent.
2. WHEN an admin submits a new ticket, THE Validation_Service SHALL validate the submitted `data` payload against the selected `TicketTemplate`'s `json_schema` and return HTTP 400 with field-level error details if validation fails.
3. WHEN a valid ticket is submitted, THE Ticket_Controller SHALL create a `Ticket` document with `status: 'open'`, a unique `ticket_no` (format: `<COMPANY_CODE>-<NNNN>`), and a computed `sla_deadline` derived from `TicketTemplate.sla_seconds`.
4. WHERE an `assignee_id` is provided in the request body, THE Ticket_Controller SHALL set the `Ticket.assignee` field to the specified employee's `_id` at creation time.
5. WHERE an `assignee_id` is provided, THE Ticket_Controller SHALL verify the referenced user exists and has `role: 'employee'` before saving, returning HTTP 400 if the user is not found or is not an employee.
6. WHEN a ticket is successfully created, THE Ticket_Controller SHALL emit a `ticketCreated` real-time event via Socket.IO containing `ticketId`, `ticket_no`, `templateName`, `status`, and `assignee`.
7. WHEN a ticket is successfully created, THE Audit_Log SHALL record an entry with `action: 'created'`, the `actor_id`, `ticket_no`, `template_name`, and `assignee_id`.

---

### Requirement 3: Employee List for Assignment

**User Story:** As an admin, I want to see a list of available employees when assigning a ticket, so that I can choose the right person for the job.

#### Acceptance Criteria

1. WHEN an admin opens the ticket creation or edit screen, THE Ticket_Controller SHALL provide an endpoint that returns all users with `role: 'employee'` and `isActive: true` scoped to the admin's company.
2. THE employee list response SHALL include at minimum each employee's `_id`, `name`, `employeeId`, and `status` fields.
3. WHILE an employee has `isActive: false`, THE Ticket_Controller SHALL exclude that employee from the assignable list.
4. WHEN an admin assigns a ticket to an employee, THE Ticket_Controller SHALL update `Ticket.assignee` and record the change in the Audit_Log with `action: 'assignee_updated'`.

---

### Requirement 4: Ticket List View for Admins

**User Story:** As an admin, I want to view all tickets for my company with filtering options, so that I can monitor field work status at a glance.

#### Acceptance Criteria

1. WHEN an admin requests the ticket list, THE Ticket_Controller SHALL return all non-archived tickets scoped to the admin's company via `GET /api/tickets`.
2. THE ticket list response SHALL include for each ticket: `ticket_no`, `template.name`, `status`, `assignee.name`, `sla_deadline`, `sla_status`, and `createdAt`.
3. WHEN a `status` query parameter is provided, THE Ticket_Controller SHALL filter the returned tickets to only those matching the specified `Ticket_Status`.
4. WHEN a `template` query parameter is provided, THE Ticket_Controller SHALL filter the returned tickets to only those created from the specified `TicketTemplate`.
5. WHEN `archived=true` is passed as a query parameter, THE Ticket_Controller SHALL return only archived tickets; otherwise THE Ticket_Controller SHALL exclude archived tickets from the default list.
6. THE Ticket_Controller SHALL sort the ticket list by `createdAt` descending by default.

---

### Requirement 5: Ticket Detail View

**User Story:** As an admin or employee, I want to view the full details of a ticket, so that I can see all service information and current status.

#### Acceptance Criteria

1. WHEN a user requests a single ticket via `GET /api/tickets/:id`, THE Ticket_Controller SHALL return the full ticket document with populated `template`, `assignee`, `created_by`, `company`, and `geofence` fields.
2. IF the requesting user belongs to a different company than the ticket, THEN THE Ticket_Controller SHALL return HTTP 403.
3. WHILE a ticket has `status: 'open'` or `status: 'in_progress'` and `sla_deadline` is in the past, THE Ticket_Controller SHALL include `sla_status: 'overdue'` in the response.
4. THE Ticket_Controller SHALL return the ticket's `data` payload (the filled-in form fields) as part of the detail response.

---

### Requirement 6: Ticket Status Transitions

**User Story:** As an admin or employee, I want to update the status of a ticket through its defined workflow, so that the lifecycle of each service job is accurately tracked.

#### Acceptance Criteria

1. WHEN a status update is submitted via `PATCH /api/tickets/:id/status`, THE Ticket_Controller SHALL validate the transition against the `TicketTemplate`'s `workflow.transitions` map and return HTTP 400 if the transition is not permitted.
2. WHEN a ticket transitions to `completed`, `verified`, or `closed`, THE Ticket_Controller SHALL set `Ticket.completedAt` to the current timestamp if it is not already set.
3. WHEN a status transition is successful, THE Ticket_Controller SHALL emit a `ticketStatusChanged` real-time event via Socket.IO containing `ticketId`, `ticket_no`, `from`, `to`, and `changedBy`.
4. WHEN a status transition is successful, THE Audit_Log SHALL record an entry with `action: 'status_changed'`, `from` status, and `to` status.
5. IF a ticket has `status: 'closed'`, THEN THE Ticket_Controller SHALL reject any further status transition requests with HTTP 400.

---

### Requirement 7: Employee Ticket View

**User Story:** As an employee, I want to see only the tickets assigned to me, so that I can focus on my own work without seeing other employees' tickets.

#### Acceptance Criteria

1. WHEN an employee requests the ticket list, THE Ticket_Controller SHALL return only tickets where `Ticket.assignee` matches the requesting employee's `_id`.
2. THE employee ticket list SHALL include `ticket_no`, `template.name`, `status`, `sla_deadline`, and `data` fields.
3. WHILE a ticket assigned to an employee has `sla_deadline` in the past and `status` is not `completed`, `verified`, or `closed`, THE Ticket_Controller SHALL include `sla_status: 'overdue'` in the response for that ticket.
4. IF an employee attempts to access a ticket not assigned to them, THEN THE Ticket_Controller SHALL return HTTP 403.

---

### Requirement 8: Ticket Data Update

**User Story:** As an employee, I want to update the form data on my assigned ticket, so that I can record service findings and completion details.

#### Acceptance Criteria

1. WHEN an employee submits updated `data` via `PATCH /api/tickets/:id`, THE Validation_Service SHALL re-validate the payload against the `TicketTemplate`'s `json_schema` and return HTTP 400 with field-level errors if validation fails.
2. WHEN valid updated `data` is submitted, THE Ticket_Controller SHALL persist the changes to `Ticket.data` and return the updated ticket document.
3. IF a ticket has `status: 'closed'` or `status: 'verified'`, THEN THE Ticket_Controller SHALL reject data update requests with HTTP 400.
4. WHEN ticket data is successfully updated, THE Audit_Log SHALL record an entry with `action: 'data_updated'` and the list of updated fields.

---

### Requirement 9: Template Management by Admins

**User Story:** As an admin, I want to create, update, and deactivate service templates, so that the available service types stay current and accurate.

#### Acceptance Criteria

1. WHEN an admin creates a template via `POST /api/templates`, THE Template_Controller SHALL require `name` and `json_schema` fields and return HTTP 400 if either is absent.
2. WHEN an admin creates a template, THE Template_Controller SHALL associate the template with the admin's company and set `isActive: true` by default.
3. WHEN an admin updates a template's `json_schema` via `PUT /api/templates/:id`, THE Template_Controller SHALL increment `TicketTemplate.version` by 1.
4. WHEN an admin deactivates a template via `DELETE /api/templates/:id`, THE Template_Controller SHALL set `isActive: false` (soft delete) rather than removing the document, so that existing tickets referencing the template remain intact.
5. WHEN a template is created or updated, THE Audit_Log SHALL record the action with `actor_id`, `template_name`, and the list of updated fields.
6. IF a non-admin user attempts to create, update, or deactivate a template, THEN THE Template_Controller SHALL return HTTP 403.

---

### Requirement 10: SLA Tracking

**User Story:** As an admin, I want tickets to automatically track SLA deadlines, so that I can identify overdue jobs and take corrective action.

#### Acceptance Criteria

1. WHEN a ticket is created from a template with `sla_seconds > 0`, THE Ticket_Controller SHALL compute `sla_deadline` as `createdAt + sla_seconds` and persist it on the `Ticket` document.
2. WHEN a ticket is created from a template with `sla_seconds` equal to `null` or `0`, THE Ticket_Controller SHALL set `sla_deadline` to `null` and `sla_status` to `null`.
3. WHEN the SLA check job runs, THE Ticket_Controller SHALL update `sla_status` to `'overdue'` for all non-closed tickets where `sla_deadline` is in the past.
4. WHEN a ticket transitions to `closed` or `verified`, THE Ticket_Controller SHALL set `sla_status` to `'on_time'` if `completedAt` is before `sla_deadline`, or retain `'overdue'` if `completedAt` is after `sla_deadline`.

---

### Requirement 11: Extensibility for Multiple Service Types

**User Story:** As a system administrator, I want the ticketing system to support multiple service types beyond aircon cleaning, so that the platform can be used by different field service companies.

#### Acceptance Criteria

1. THE Ticket_Controller SHALL accept any `TicketTemplate` regardless of service category, with no hardcoded service-type logic in the ticket creation or update paths.
2. WHEN a new `TicketTemplate` is created with a valid `json_schema`, THE Validation_Service SHALL be able to validate ticket data against it without requiring code changes.
3. THE Template_Controller SHALL allow admins to define custom `workflow.statuses` and `workflow.transitions` per template, overriding the default workflow.
4. WHERE a `TicketTemplate` has `visibility: 'public'`, THE Template_Controller SHALL make it available to users of any company without requiring company-specific configuration.

---

### Requirement 12: Attachment Support for Tickets

**User Story:** As an employee, I want to attach photos or documents to a ticket, so that I can provide visual evidence of the service performed.

#### Acceptance Criteria

1. WHEN an employee uploads a file via `POST /api/tickets/:id/attachments`, THE Ticket_Controller SHALL accept files up to 10 MB and store them using the storage service.
2. WHEN a file is successfully uploaded, THE Ticket_Controller SHALL append the resulting URL to `Ticket.attachments` and return the file metadata including `path`, `fileId`, and `checksum`.
3. IF no file is included in the upload request, THEN THE Ticket_Controller SHALL return HTTP 400 with a descriptive error message.
4. WHEN an attachment is added, THE Audit_Log SHALL record an entry with `action: 'attachment_added'`, `filename`, and `checksum`.
5. WHEN a user requests a ticket attachment via `GET /api/tickets/attachments/:fileId`, THE Ticket_Controller SHALL stream the file with the correct `Content-Type` and `Content-Disposition` headers.
