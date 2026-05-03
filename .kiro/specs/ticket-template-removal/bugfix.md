# Bugfix Requirements Document: Ticket and Template Functionality Removal

## Introduction

The FieldCheck application currently includes a ticket and template management system that is causing confusion among clients. This system includes dedicated pages for both admin and employee sides, backend controllers, models, routes, and services. The confusion stems from the presence of this parallel workflow alongside the existing task management system. This bugfix removes all ticket and template functionality from the application, including:

- All UI pages and screens related to tickets and templates
- All backend routes, controllers, and models for tickets and templates
- Service type assignment functionality in the admin task management
- All related services and utilities
- Seed data and database references

After removal, the application will rely solely on the task management system for field work assignment and tracking.

---

## Bug Analysis

### Current Behavior (Defect)

1.1 WHEN an admin accesses the admin dashboard or navigation menu THEN the system displays ticket and template management options alongside task management, creating confusion about which workflow to use

1.2 WHEN an admin navigates to the admin panel THEN the system provides access to ticket creation, ticket list, and template management pages that duplicate functionality already present in the task system

1.3 WHEN an employee accesses the employee dashboard THEN the system displays ticket-related pages and options that create confusion about whether to use tickets or tasks for field work

1.4 WHEN an admin attempts to assign tasks to employees THEN the system provides a "service type" selection feature that is tightly coupled to the ticket/template system, adding unnecessary complexity

1.5 WHEN the backend processes requests THEN the system maintains ticket routes, controllers, models, and services that are not being actively used, creating technical debt and maintenance burden

1.6 WHEN the database is initialized THEN the system includes ticket and template seed data that is not needed, cluttering the data model

### Expected Behavior (Correct)

2.1 WHEN an admin accesses the admin dashboard or navigation menu THEN the system displays only task management options without any ticket or template references

2.2 WHEN an admin navigates to the admin panel THEN the system provides access only to task management pages, with no ticket creation, ticket list, or template management pages available

2.3 WHEN an employee accesses the employee dashboard THEN the system displays only task-related pages without any ticket-related options or confusion

2.4 WHEN an admin attempts to assign tasks to employees THEN the system provides a straightforward task assignment interface without service type selection or template-related features

2.5 WHEN the backend processes requests THEN the system contains no ticket routes, controllers, models, or services, reducing technical debt and maintenance burden

2.6 WHEN the database is initialized THEN the system contains no ticket or template seed data, keeping the data model clean and focused

### Unchanged Behavior (Regression Prevention)

3.1 WHEN an admin uses the task management system THEN the system SHALL CONTINUE TO allow task creation, assignment, and tracking without any changes to existing task functionality

3.2 WHEN an employee views their assigned tasks THEN the system SHALL CONTINUE TO display task details, status updates, and task submission capabilities exactly as before

3.3 WHEN the application starts THEN the system SHALL CONTINUE TO initialize all non-ticket/template features (users, companies, geofences, attendance, etc.) without any disruption

3.4 WHEN an admin manages employees and company settings THEN the system SHALL CONTINUE TO provide all existing admin functionality except ticket/template management

3.5 WHEN an employee submits task reports and attachments THEN the system SHALL CONTINUE TO process submissions and store attachments without any changes to the task submission workflow

3.6 WHEN the backend serves API requests for tasks, users, attendance, and other features THEN the system SHALL CONTINUE TO respond with the same data structure and behavior as before

---

## Scope of Removal

### Frontend (Flutter - field_check)

**Admin Pages to Remove:**
- `admin_template_management_screen.dart` - Template CRUD interface
- `admin_ticket_list_screen.dart` - Ticket list view
- `admin_ticket_detail_screen.dart` - Ticket detail view
- `enhanced_ticket_creation_screen.dart` - Enhanced ticket creation interface
- `ticket_creation_screen.dart` - Basic ticket creation interface
- `ticket_dashboard_screen.dart` - Ticket dashboard

**Employee Pages to Remove:**
- `employee_ticket_create_screen.dart` - Employee ticket creation
- `employee_ticket_list_screen.dart` - Employee ticket list view

**Navigation and Menu References:**
- Remove ticket/template menu items from admin navigation
- Remove ticket/template menu items from employee navigation
- Remove service type selection from task assignment UI

### Backend (Node.js/Express)

**Routes to Remove:**
- `backend/routes/ticketRoutes.js` - All ticket endpoints
- `backend/routes/templateRoutes.js` - All template endpoints

**Controllers to Remove:**
- Ticket controller functionality (if separate file exists)
- Template controller functionality (if separate file exists)

**Models to Remove:**
- `backend/models/Ticket.js` - Ticket data model
- `backend/models/TicketTemplate.js` - Template data model

**Services to Remove:**
- `backend/services/ticketService.js` - Ticket business logic

**Seed Data to Remove:**
- `backend/seeds/ticketTemplates.json` - Template seed data
- `backend/seeds/seedAirconTemplate.js` - Aircon template seed
- `backend/seeds/seedElectricalTemplate.js` - Electrical template seed
- `backend/seeds/seedPlumbingTemplate.js` - Plumbing template seed

**Server Configuration:**
- Remove ticket and template route registrations from `backend/server.js`
- Remove ticket-related middleware or job configurations

### Database References

- Remove all references to Ticket collection
- Remove all references to TicketTemplate collection
- Remove service_type field from any task-related models if present
- Remove any foreign key relationships to ticket/template models

---

## Testing Strategy

### Verification of Complete Removal

**Frontend Verification:**
1. Verify no `.dart` files reference `Ticket`, `TicketTemplate`, or `ticket` in imports or class names
2. Verify no navigation routes point to removed ticket/template screens
3. Verify admin dashboard does not display ticket/template menu items
4. Verify employee dashboard does not display ticket-related options
5. Verify task assignment UI does not include service type selection
6. Verify application builds without errors after removal

**Backend Verification:**
1. Verify no routes in `server.js` reference `/api/tickets` or `/api/templates`
2. Verify no controllers handle ticket or template requests
3. Verify no models define Ticket or TicketTemplate schemas
4. Verify no services contain ticket business logic
5. Verify database initialization does not attempt to seed ticket/template data
6. Verify API server starts without errors after removal

**Functional Verification:**
1. Verify admin can create and assign tasks without ticket/template options
2. Verify employees can view and complete assigned tasks
3. Verify task submission and reporting functionality works as before
4. Verify no broken links or 404 errors in navigation
5. Verify no console errors related to missing ticket/template components
6. Verify existing task data is not affected by removal

**Code Quality Verification:**
1. Verify no orphaned imports or references to removed files
2. Verify no dead code or commented-out ticket/template logic remains
3. Verify linting passes without warnings related to removed code
4. Verify no database migration issues or schema conflicts

