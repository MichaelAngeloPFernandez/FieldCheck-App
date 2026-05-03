# Ticket and Template Functionality Removal - Implementation Tasks

## Overview

This task list implements the systematic removal of ticket and template functionality from the FieldCheck application. The tasks follow the exploratory bugfix workflow:

1. **Explore** - Write tests to verify ticket/template code exists (Bug Condition)
2. **Preserve** - Write tests to verify existing task functionality works (Preservation)
3. **Implement** - Remove all ticket/template code and verify fix
4. **Validate** - Ensure all tests pass and no regressions occur

---

## Phase 1: Exploration Tests

### Bug Condition Verification

- [x] 1. Write bug condition exploration test
  - **Property 1: Bug Condition** - Ticket/Template Code Exists in Codebase
  - **CRITICAL**: This test MUST FAIL on unfixed code - failure confirms the bug exists
  - **GOAL**: Surface evidence that ticket/template functionality is present in the codebase
  - **Scoped PBT Approach**: Scope the property to concrete failing cases - search for specific files and references that should not exist after removal
  - Test that verifies the following files exist in the codebase (Bug Condition from design):
    - Frontend screen files: `admin_template_management_screen.dart`, `admin_ticket_list_screen.dart`, `admin_ticket_detail_screen.dart`, `enhanced_ticket_creation_screen.dart`, `ticket_creation_screen.dart`, `ticket_dashboard_screen.dart`, `employee_ticket_create_screen.dart`, `employee_ticket_list_screen.dart`
    - Backend route files: `backend/routes/ticketRoutes.js`, `backend/routes/templateRoutes.js`
    - Backend model files: `backend/models/Ticket.js`, `backend/models/TicketTemplate.js`
    - Backend service file: `backend/services/ticketService.js`
    - Seed data files: `backend/seeds/ticketTemplates.json`, `backend/seeds/seedAirconTemplate.js`, `backend/seeds/seedElectricalTemplate.js`, `backend/seeds/seedPlumbingTemplate.js`
  - Test that verifies route registrations exist in `backend/server.js` for `/api/tickets` and `/api/templates`
  - Test that verifies ticket/template imports exist in navigation and routing configuration files
  - Run test on UNFIXED code
  - **EXPECTED OUTCOME**: Test FAILS (this is correct - it proves the bug exists)
  - Document counterexamples found (e.g., "Found 8 ticket/template screen files in field_check/lib/screens/", "Found ticketRoutes.js and templateRoutes.js in backend/routes/")
  - Mark task complete when test is written, run, and failure is documented
  - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6_

---

## Phase 2: Preservation Tests

### Existing Functionality Preservation

- [x] 2. Write preservation property tests (BEFORE implementing fix)
  - **Property 2: Preservation** - Task Management and Other Features Work Unchanged
  - **IMPORTANT**: Follow observation-first methodology
  - Observe behavior on UNFIXED code for non-ticket/template features:
    - Task creation works with valid inputs
    - Task assignment completes successfully
    - Task viewing displays correct data
    - Employee task submission processes correctly
    - User management operations succeed
    - Attendance tracking functions properly
    - Chat and notifications work as expected
    - Report generation completes without errors
  - Write property-based tests capturing observed behavior patterns from Preservation Requirements (design section 3.1-3.6):
    - For all valid task creation inputs, task is created successfully
    - For all valid task assignment inputs, task is assigned to employee
    - For all valid task viewing requests, correct task data is returned
    - For all valid user operations, user data is modified correctly
    - For all valid attendance records, attendance is tracked properly
    - For all valid chat messages, messages are stored and retrieved correctly
  - Property-based testing generates many test cases for stronger preservation guarantees
  - Run tests on UNFIXED code
  - **EXPECTED OUTCOME**: Tests PASS (this confirms baseline behavior to preserve)
  - Mark task complete when tests are written, run, and passing on unfixed code
  - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6_

---

## Phase 3: Implementation

### Frontend Removal

- [x] 3. Remove Flutter screen files for ticket and template management
  - Delete 8 screen files from `field_check/lib/screens/`:
    - `admin_template_management_screen.dart`
    - `admin_ticket_list_screen.dart`
    - `admin_ticket_detail_screen.dart`
    - `enhanced_ticket_creation_screen.dart`
    - `ticket_creation_screen.dart`
    - `ticket_dashboard_screen.dart`
    - `employee_ticket_create_screen.dart`
    - `employee_ticket_list_screen.dart`
  - Verify files are deleted using file system check
  - _Bug_Condition: Presence of ticket/template screen files in field_check/lib/screens/_
  - _Expected_Behavior: No ticket/template screen files exist in codebase_
  - _Preservation: All other screen files remain unchanged_
  - _Requirements: 2.1, 2.2, 2.3_

- [x] 4. Remove ticket/template navigation routes and menu items
  - Search for and remove all route definitions pointing to removed ticket/template screens
  - Remove ticket/template menu items from admin navigation configuration
  - Remove ticket/template menu items from employee navigation configuration
  - Remove service type selection UI from task assignment screens
  - Update navigation state management to exclude ticket/template routes
  - Search for imports of removed screen files and remove them
  - Verify no broken imports remain in navigation files
  - _Bug_Condition: Navigation routes and menu items reference ticket/template screens_
  - _Expected_Behavior: Navigation contains only task management routes and menu items_
  - _Preservation: All other navigation routes and menu items remain unchanged_
  - _Requirements: 2.1, 2.2, 2.3_

- [x] 5. Clean up Flutter imports and references
  - Search all `.dart` files for imports of removed ticket/template screen files
  - Remove all imports of removed screens
  - Search for any remaining references to Ticket, TicketTemplate, or ticket-related classes
  - Remove any state management code related to tickets or templates
  - Remove any service type dropdown or selection widgets
  - Verify no orphaned imports or dead code remains
  - Run Flutter linter to check for unused imports
  - _Bug_Condition: Orphaned imports and references to removed ticket/template code_
  - _Expected_Behavior: No imports or references to removed ticket/template code_
  - _Preservation: All task-related imports and references remain unchanged_
  - _Requirements: 2.1, 2.2, 2.3_

- [x] 6. Verify Flutter project builds without errors
  - Run `flutter pub get` to ensure dependencies are resolved
  - Run `flutter analyze` to check for analysis issues
  - Run `flutter build` (or equivalent) to verify project compiles
  - Verify no console errors or warnings related to missing screens or routes
  - Verify no broken imports or references to removed files
  - Document build output and verify success
  - _Bug_Condition: Flutter project fails to build due to removed files_
  - _Expected_Behavior: Flutter project builds successfully without errors_
  - _Preservation: All existing Flutter functionality compiles correctly_
  - _Requirements: 2.1, 2.2, 2.3_

### Backend Route and Model Removal

- [x] 7. Remove backend route files for tickets and templates
  - Delete `backend/routes/ticketRoutes.js`
  - Delete `backend/routes/templateRoutes.js`
  - Verify files are deleted using file system check
  - Search for any other route files that might reference tickets or templates
  - _Bug_Condition: Ticket and template route files exist in backend/routes/_
  - _Expected_Behavior: No ticket/template route files exist in backend/routes/_
  - _Preservation: All other route files remain unchanged_
  - _Requirements: 2.5_

- [x] 8. Remove backend model files for tickets and templates
  - Delete `backend/models/Ticket.js`
  - Delete `backend/models/TicketTemplate.js`
  - Verify files are deleted using file system check
  - Search for any other model files that might reference tickets or templates
  - _Bug_Condition: Ticket and template model files exist in backend/models/_
  - _Expected_Behavior: No ticket/template model files exist in backend/models/_
  - _Preservation: All other model files remain unchanged_
  - _Requirements: 2.5_

- [x] 9. Remove backend service file for tickets
  - Delete `backend/services/ticketService.js`
  - Verify file is deleted using file system check
  - Search for any other service files that might reference tickets or templates
  - _Bug_Condition: Ticket service file exists in backend/services/_
  - _Expected_Behavior: No ticket service file exists in backend/services/_
  - _Preservation: All other service files remain unchanged_
  - _Requirements: 2.5_

- [x] 10. Remove ticket/template route registrations from server.js
  - Open `backend/server.js`
  - Search for route registrations like `app.use('/api/tickets', ticketRoutes)` and `app.use('/api/templates', templateRoutes)`
  - Remove all ticket and template route registrations
  - Remove any imports of ticketRoutes or templateRoutes
  - Remove any middleware specific to ticket/template processing
  - Remove any job scheduling related to tickets or templates
  - Verify no references to ticket or template routes remain
  - _Bug_Condition: server.js registers routes for /api/tickets and /api/templates_
  - _Expected_Behavior: server.js contains no ticket/template route registrations_
  - _Preservation: All other route registrations and middleware remain unchanged_
  - _Requirements: 2.5_

### Backend Seed Data Removal

- [x] 11. Remove ticket/template seed data files
  - Delete `backend/seeds/ticketTemplates.json`
  - Delete `backend/seeds/seedAirconTemplate.js`
  - Delete `backend/seeds/seedElectricalTemplate.js`
  - Delete `backend/seeds/seedPlumbingTemplate.js`
  - Verify files are deleted using file system check
  - Search for any other seed files that might reference tickets or templates
  - _Bug_Condition: Ticket/template seed data files exist in backend/seeds/_
  - _Expected_Behavior: No ticket/template seed data files exist in backend/seeds/_
  - _Preservation: All other seed data files remain unchanged_
  - _Requirements: 2.6_

- [x] 12. Remove ticket/template seed data initialization calls
  - Search database initialization code for calls to ticket/template seed scripts
  - Remove any calls to seedAirconTemplate, seedElectricalTemplate, seedPlumbingTemplate
  - Remove any code that loads ticketTemplates.json
  - Remove any database migration code related to ticket/template collections
  - Verify database initialization completes without errors
  - Document changes made to initialization code
  - _Bug_Condition: Database initialization includes ticket/template seed data_
  - _Expected_Behavior: Database initialization excludes ticket/template seed data_
  - _Preservation: All other database initialization code remains unchanged_
  - _Requirements: 2.6_

### Backend Controller and Service Cleanup

- [x] 13. Remove service type handling from task controller
  - Open `backend/controllers/taskController.js`
  - Search for any references to service_type field or service type handling
  - Remove service type field from task creation logic
  - Remove service type field from task assignment logic
  - Remove service type filtering or grouping from task list endpoints
  - Remove any service type-related validation or constraints
  - Ensure task controller focuses only on task management
  - Verify no orphaned service type references remain
  - _Bug_Condition: Task controller includes service type handling coupled to templates_
  - _Expected_Behavior: Task controller manages only task-related fields_
  - _Preservation: All other task controller functionality remains unchanged_
  - _Requirements: 2.4_

- [x] 14. Clean up imports and references in backend files
  - Search all backend files for imports of removed Ticket, TicketTemplate, or ticketService
  - Remove all imports of removed ticket/template files
  - Search all controllers for references to Ticket or TicketTemplate models
  - Remove any middleware that processes ticket/template data
  - Search all services for references to ticket functionality
  - Remove any utility functions specific to tickets or templates
  - Verify no orphaned imports or dead code remains
  - Run linter to check for unused imports and variables
  - _Bug_Condition: Backend files contain imports and references to removed ticket/template code_
  - _Expected_Behavior: No imports or references to removed ticket/template code_
  - _Preservation: All task-related imports and references remain unchanged_
  - _Requirements: 2.5_

### Database and Reference Cleanup

- [x] 15. Remove database references to tickets and templates
  - Search all remaining models for foreign key references to Ticket or TicketTemplate
  - Remove any service_type field from Task model if present
  - Remove any template_id references from other models
  - Remove any ticket_id references from other models
  - Verify no orphaned references remain in any model
  - Document any data migration considerations if production data exists
  - _Bug_Condition: Models contain references to removed Ticket/TicketTemplate models_
  - _Expected_Behavior: No references to removed ticket/template models exist_
  - _Preservation: All other model relationships remain unchanged_
  - _Requirements: 2.5, 2.6_

### Backend Verification

- [x] 16. Verify Node.js server starts without errors
  - Run `npm install` to ensure dependencies are resolved
  - Run `npm run lint` or equivalent to check for linting issues
  - Start the Node.js server with `npm start` or equivalent
  - Verify server starts without errors or warnings
  - Verify no console errors about missing routes or models
  - Verify no console errors about missing seed data
  - Check that all expected routes are registered (non-ticket/template routes)
  - Document server startup output and verify success
  - _Bug_Condition: Node.js server fails to start due to removed files_
  - _Expected_Behavior: Node.js server starts successfully without errors_
  - _Preservation: All existing backend functionality works correctly_
  - _Requirements: 2.5, 2.6_

---

## Phase 4: Verification and Testing

### Bug Condition Verification

- [x] 17. Verify bug condition exploration test now passes
  - **Property 1: Expected Behavior** - Ticket/Template Code Removed from Codebase
  - **IMPORTANT**: Re-run the SAME test from task 1 - do NOT write a new test
  - The test from task 1 encodes the expected behavior (no ticket/template code)
  - When this test passes, it confirms all ticket/template code has been removed
  - Run bug condition exploration test from step 1
  - Verify that all file existence checks now FAIL (files no longer exist)
  - Verify that all route registration checks now FAIL (routes no longer registered)
  - Verify that all import checks now FAIL (imports no longer present)
  - **EXPECTED OUTCOME**: Test PASSES (confirms bug is fixed - all ticket/template code removed)
  - Document test results and verify complete removal
  - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6_

### Preservation Verification

- [x] 18. Verify preservation tests still pass
  - **Property 2: Preservation** - Task Management and Other Features Work Unchanged
  - **IMPORTANT**: Re-run the SAME tests from task 2 - do NOT write new tests
  - Run preservation property tests from step 2
  - Verify all task creation tests pass
  - Verify all task assignment tests pass
  - Verify all task viewing tests pass
  - Verify all user management tests pass
  - Verify all attendance tracking tests pass
  - Verify all chat and notification tests pass
  - Verify all report generation tests pass
  - **EXPECTED OUTCOME**: Tests PASS (confirms no regressions)
  - Confirm all tests still pass after removal (no regressions)
  - Document test results and verify preservation of existing functionality
  - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6_

### Comprehensive Testing

- [x] 19. Run comprehensive code search verification
  - Search entire codebase for remaining references to "ticket" (case-insensitive)
  - Search entire codebase for remaining references to "template" (case-insensitive)
  - Search entire codebase for remaining references to "Ticket" or "TicketTemplate" classes
  - Search entire codebase for remaining references to "service_type" field
  - Document any remaining references found
  - Verify no unexpected references remain (some may be in comments or documentation)
  - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6_

- [x] 20. Run full test suite
  - Run all unit tests for backend controllers and services
  - Run all unit tests for frontend widgets and screens
  - Run all integration tests for API endpoints
  - Run all end-to-end tests for user workflows
  - Verify all tests pass without failures
  - Verify no tests reference removed ticket/template functionality
  - Document test results and coverage
  - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6_

- [x] 21. Verify admin dashboard functionality
  - Test admin login and dashboard access
  - Verify admin dashboard displays only task management options
  - Verify no ticket/template menu items appear
  - Verify all admin task management features work correctly
  - Verify admin can create tasks without service type selection
  - Verify admin can assign tasks to employees
  - Verify admin can view task status and reports
  - Document admin workflow verification
  - _Requirements: 2.1, 2.2, 2.4_

- [x] 22. Verify employee dashboard functionality
  - Test employee login and dashboard access
  - Verify employee dashboard displays only task-related pages
  - Verify no ticket-related options or pages appear
  - Verify employee can view assigned tasks
  - Verify employee can submit task reports
  - Verify employee can upload attachments
  - Verify employee can view task history
  - Document employee workflow verification
  - _Requirements: 2.1, 2.3_

- [x] 23. Verify API endpoints
  - Test that `/api/tickets` endpoint returns 404 error
  - Test that `/api/templates` endpoint returns 404 error
  - Test that all task-related endpoints work correctly
  - Test that all user-related endpoints work correctly
  - Test that all attendance-related endpoints work correctly
  - Test that all chat-related endpoints work correctly
  - Test that all report-related endpoints work correctly
  - Document API endpoint verification
  - _Requirements: 2.5_

- [x] 24. Verify database state
  - Verify Ticket collection does not exist in MongoDB
  - Verify TicketTemplate collection does not exist in MongoDB
  - Verify no orphaned references to ticket/template collections exist
  - Verify all task data is intact and accessible
  - Verify all user data is intact and accessible
  - Verify all attendance data is intact and accessible
  - Document database verification
  - _Requirements: 2.6_

### Final Checkpoint

- [x] 25. Checkpoint - Ensure all tests pass and no regressions
  - Verify all exploration tests pass (bug condition fixed)
  - Verify all preservation tests pass (no regressions)
  - Verify all unit tests pass
  - Verify all integration tests pass
  - Verify all end-to-end tests pass
  - Verify Flutter project builds without errors
  - Verify Node.js server starts without errors
  - Verify no console errors or warnings
  - Verify no broken links in navigation
  - Verify admin and employee workflows work correctly
  - Verify all API endpoints respond correctly
  - Verify database is clean and consistent
  - Ask the user if questions arise or if any issues are discovered
  - Document final verification results
  - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 3.1, 3.2, 3.3, 3.4, 3.5, 3.6_

---

## Task Annotations Reference

### Bug Condition References
- **Bug_Condition**: Presence of ticket/template functionality in application creates confusion and technical debt
- **isBugCondition(input)**: User interaction with admin/employee dashboard OR navigation menu AND ticket/template options visible AND task system also available

### Expected Behavior References
- **Expected_Behavior**: Application provides single, clear workflow using only task system
- **expectedBehavior(result)**: No ticket/template options visible AND only task management options available

### Preservation References
- **Preservation**: All task management, user management, attendance tracking, chat, notifications, and report functionality must remain unchanged
- **Preserved_Features**: Task creation, assignment, viewing, submission; User management; Attendance tracking; Chat and notifications; Report generation; All other non-ticket/template features

### Requirements Mapping
- **1.1-1.6**: Current defective behavior (bug condition)
- **2.1-2.6**: Expected correct behavior (fix checking)
- **3.1-3.6**: Unchanged behavior (preservation checking)
