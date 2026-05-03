# Ticket and Template Functionality Removal - Bugfix Design

## Overview

This design document outlines the systematic removal of ticket and template functionality from the FieldCheck application. The application currently maintains two parallel workflows for field work management: the task system and the ticket/template system. This duplication creates confusion for users and technical debt for the codebase.

The removal strategy is comprehensive and methodical, addressing:
- Frontend UI pages and navigation (Flutter)
- Backend routes, controllers, and models (Node.js/Express)
- Database schema and seed data
- Service type functionality coupled to templates
- All cross-references and dependencies

The approach prioritizes complete removal while preserving all existing task management functionality, ensuring no regression in core features.

## Glossary

- **Bug_Condition (C)**: The presence of ticket and template functionality in the application creates confusion and technical debt
- **Property (P)**: The application should provide a single, clear workflow for field work management using only the task system
- **Preservation**: All task management functionality, user management, attendance tracking, and other non-ticket features must remain unchanged
- **Frontend (Flutter)**: The mobile application in `field_check/` directory containing UI screens and navigation
- **Backend (Node.js)**: The Express server in `backend/` directory containing routes, controllers, models, and services
- **Service Type**: A feature in task assignment that is tightly coupled to the ticket/template system and must be removed
- **Seed Data**: Initial database records created during application startup (templates, sample data)
- **Navigation Routes**: Flutter routing configuration that directs users to different screens
- **API Routes**: Express route definitions that handle HTTP requests for specific resources

## Bug Details

### Bug Condition

The bug manifests when users interact with the FieldCheck application and encounter ticket and template management options alongside task management options. The application maintains two parallel workflows for field work assignment and tracking, creating confusion about which system to use.

**Formal Specification:**
```
FUNCTION isBugCondition(userAction)
  INPUT: userAction of type UserInteraction
  OUTPUT: boolean
  
  RETURN (userAction.location IN ['admin_dashboard', 'employee_dashboard', 'navigation_menu'])
         AND (ticketOrTemplateOptionsVisible(userAction.location))
         AND (taskSystemAlsoAvailable())
END FUNCTION
```

### Examples

**Example 1: Admin Dashboard Confusion**
- Current behavior: Admin sees both "Task Management" and "Ticket Management" menu items
- Expected behavior: Admin sees only "Task Management" menu item
- Impact: Admin is confused about which workflow to use for field work assignment

**Example 2: Employee Dashboard Confusion**
- Current behavior: Employee sees both task pages and ticket pages in navigation
- Expected behavior: Employee sees only task-related pages
- Impact: Employee is uncertain whether to use tasks or tickets for work assignments

**Example 3: Task Assignment Complexity**
- Current behavior: When assigning a task, admin must select a "service type" (coupled to templates)
- Expected behavior: Task assignment is straightforward without service type selection
- Impact: Admin workflow is unnecessarily complex

**Example 4: Technical Debt**
- Current behavior: Backend maintains unused ticket routes, controllers, models, and services
- Expected behavior: Backend contains only active, used code
- Impact: Maintenance burden and potential for bugs in unused code paths

**Example 5: Database Clutter**
- Current behavior: Database is seeded with ticket templates (Aircon, Electrical, Plumbing)
- Expected behavior: Database contains only necessary seed data
- Impact: Unnecessary data in database, potential confusion during development

## Expected Behavior

### Preservation Requirements

**Unchanged Behaviors:**
- Task creation, assignment, and tracking functionality must work exactly as before
- Employee task viewing, status updates, and task submission must be unchanged
- Admin task management interface must function identically
- User management, authentication, and authorization must be unaffected
- Attendance tracking, geofencing, and location services must continue working
- Chat and notification systems must remain functional
- Report generation and export functionality must be preserved
- All API endpoints for tasks, users, attendance, and other features must respond identically

**Scope:**
All inputs and interactions that do NOT involve ticket or template functionality should be completely unaffected by this removal. This includes:
- Task creation and assignment workflows
- Employee task viewing and submission
- Admin dashboard and settings
- User and company management
- Attendance and location tracking
- Chat and messaging
- Report generation
- All other existing features

## Hypothesized Root Cause

Based on the bug description and codebase analysis, the root causes are:

1. **Parallel Workflow Implementation**: The application was built with both a task system and a ticket/template system, creating two separate workflows for the same purpose (field work assignment and tracking)

2. **Incomplete Feature Deprecation**: The ticket/template system was never fully removed or deprecated, leaving all UI pages, backend routes, controllers, models, and services in place

3. **Tight Coupling of Service Type**: The service type feature in task assignment is coupled to the ticket/template system, making it necessary to remove this feature as well

4. **Seed Data Persistence**: Template seed data (Aircon, Electrical, Plumbing) continues to be created during database initialization, perpetuating the ticket/template system

5. **Navigation Integration**: Ticket and template pages are integrated into the navigation system for both admin and employee roles, making them discoverable and usable

## Correctness Properties

Property 1: Bug Condition - Complete Removal of Ticket/Template Functionality

_For any_ user interaction with the FieldCheck application, the fixed application SHALL NOT display any ticket or template management options, pages, or functionality. The application SHALL provide only task management as the single workflow for field work assignment and tracking.

**Validates: Requirements 2.1, 2.2, 2.3, 2.4**

Property 2: Preservation - Task Management and Other Features Unchanged

_For any_ user interaction that involves task management, user management, attendance tracking, or any other non-ticket/template feature, the fixed application SHALL produce exactly the same behavior as the original application, preserving all existing functionality and data structures.

**Validates: Requirements 3.1, 3.2, 3.3, 3.4, 3.5, 3.6**

## Fix Implementation

### Changes Required

The removal strategy is organized by component layer, ensuring systematic and complete removal while maintaining application stability.

#### Frontend (Flutter) - `field_check/`

**1. Screen Files to Remove**

Remove the following screen files from `field_check/lib/screens/`:
- `admin_template_management_screen.dart` - Admin template CRUD interface
- `admin_ticket_list_screen.dart` - Admin ticket list view
- `admin_ticket_detail_screen.dart` - Admin ticket detail view
- `enhanced_ticket_creation_screen.dart` - Enhanced ticket creation interface
- `ticket_creation_screen.dart` - Basic ticket creation interface
- `ticket_dashboard_screen.dart` - Ticket dashboard
- `employee_ticket_create_screen.dart` - Employee ticket creation
- `employee_ticket_list_screen.dart` - Employee ticket list view

**2. Navigation and Routing Updates**

- Remove all route definitions for ticket and template screens from the main navigation/routing configuration
- Remove ticket and template menu items from admin navigation menu
- Remove ticket and template menu items from employee navigation menu
- Remove service type selection UI from task assignment screens
- Update navigation state management to exclude ticket/template routes

**3. Widget and Component Cleanup**

- Search for and remove any widgets or components that reference tickets or templates
- Remove any service type dropdown or selection widgets from task creation/assignment screens
- Remove any imports of removed ticket/template screen files
- Remove any state management code related to tickets or templates

**4. Build and Compilation Verification**

- Verify Flutter project builds without errors
- Verify no broken imports or references to removed files
- Verify no console warnings related to missing screens or routes

#### Backend (Node.js/Express) - `backend/`

**1. Route Files to Remove**

Remove the following route files:
- `backend/routes/ticketRoutes.js` - All ticket API endpoints
- `backend/routes/templateRoutes.js` - All template API endpoints

**2. Server Configuration Updates**

In `backend/server.js`:
- Remove route registration for ticket routes (e.g., `app.use('/api/tickets', ticketRoutes)`)
- Remove route registration for template routes (e.g., `app.use('/api/templates', templateRoutes)`)
- Remove any middleware specific to ticket/template processing
- Remove any job scheduling related to tickets or templates

**3. Model Files to Remove**

Remove the following model files from `backend/models/`:
- `backend/models/Ticket.js` - Ticket schema and model
- `backend/models/TicketTemplate.js` - Template schema and model

**4. Service Files to Remove**

Remove the following service file:
- `backend/services/ticketService.js` - Ticket business logic and utilities

**5. Seed Data to Remove**

Remove the following seed files from `backend/seeds/`:
- `backend/seeds/ticketTemplates.json` - Template seed data
- `backend/seeds/seedAirconTemplate.js` - Aircon template seeding script
- `backend/seeds/seedElectricalTemplate.js` - Electrical template seeding script
- `backend/seeds/seedPlumbingTemplate.js` - Plumbing template seeding script

**6. Database Initialization Updates**

- Remove calls to ticket/template seed scripts from database initialization code
- Remove any database migration code related to ticket/template collections
- Verify database initialization completes without errors

**7. Controller Updates**

- Review `backend/controllers/taskController.js` to remove any service type handling
- Remove service type field from task creation and assignment logic
- Ensure task controller focuses only on task management

**8. Dependency and Import Cleanup**

- Search for and remove all imports of removed ticket/template files
- Remove any references to Ticket or TicketTemplate models in other controllers or services
- Remove any middleware that processes ticket/template data
- Verify no orphaned imports or dead code remains

**9. Build and Startup Verification**

- Verify Node.js server starts without errors
- Verify no console warnings about missing routes or models
- Verify API endpoints respond correctly for remaining features

#### Database Schema and References

**1. Collection Removal**

- Remove Ticket collection from MongoDB (if it exists)
- Remove TicketTemplate collection from MongoDB (if it exists)

**2. Reference Cleanup**

- Search all remaining models for any foreign key references to Ticket or TicketTemplate
- Remove any service_type field from Task model if present
- Remove any template_id references from other models
- Verify no orphaned references remain

**3. Data Migration Considerations**

- If production data exists, plan for safe removal of ticket/template data
- Document any data that needs to be archived before removal
- Ensure no active tickets or templates are in use before removal

#### Service Type Functionality Removal

**1. Task Model Updates**

- Remove service_type field from Task model if present
- Remove any validation or constraints related to service types
- Update task creation and update logic to not expect service_type

**2. Task Controller Updates**

- Remove service type selection from task creation endpoint
- Remove service type filtering or grouping from task list endpoints
- Remove any service type-related business logic

**3. Frontend Task Assignment Updates**

- Remove service type dropdown from task creation/assignment screens
- Remove any UI that displays or selects service types
- Simplify task assignment workflow

## Testing Strategy

### Validation Approach

The testing strategy follows a systematic approach to verify complete removal while ensuring no regression in existing functionality:

1. **Exploratory Removal Verification** - Confirm all ticket/template code is removed
2. **Functional Preservation Testing** - Verify existing features work unchanged
3. **Integration Testing** - Verify application works end-to-end without ticket/template features
4. **Regression Testing** - Verify no broken links, missing imports, or orphaned code

### Exploratory Removal Verification

**Goal**: Surface evidence that all ticket/template functionality has been removed from the codebase.

**Test Plan**: Perform comprehensive code searches to verify removal of all ticket/template references.

**Test Cases**:
1. **Frontend Screen Removal**: Search `field_check/lib/screens/` for any remaining `.dart` files with "ticket" or "template" in the name (will fail if files still exist)
2. **Frontend Import Cleanup**: Search all `.dart` files for imports of removed ticket/template screens (will fail if imports remain)
3. **Frontend Route Removal**: Search navigation configuration for any routes pointing to removed screens (will fail if routes remain)
4. **Backend Route Removal**: Search `backend/server.js` for any references to `/api/tickets` or `/api/templates` (will fail if routes are registered)
5. **Backend Model Removal**: Search `backend/models/` for `Ticket.js` or `TicketTemplate.js` files (will fail if files exist)
6. **Backend Service Removal**: Search `backend/services/` for `ticketService.js` (will fail if file exists)
7. **Backend Seed Removal**: Search `backend/seeds/` for ticket template seed files (will fail if files exist)
8. **Database Reference Cleanup**: Search all remaining models for references to Ticket or TicketTemplate (will fail if references exist)

**Expected Counterexamples**:
- Remaining ticket/template screen files in Flutter
- Remaining imports of removed files
- Remaining route registrations in server.js
- Remaining model or service files
- Remaining seed data files
- Remaining references in other code

### Fix Checking

**Goal**: Verify that the application no longer displays or provides access to ticket/template functionality.

**Pseudocode:**
```
FOR ALL userInteraction IN [admin_dashboard, employee_dashboard, task_assignment] DO
  result := renderUI(userInteraction)
  ASSERT NOT containsTicketOrTemplateOptions(result)
  ASSERT containsOnlyTaskManagementOptions(result)
END FOR
```

**Test Cases**:
1. **Admin Dashboard**: Verify admin dashboard displays only task management options
2. **Employee Dashboard**: Verify employee dashboard displays only task-related pages
3. **Navigation Menu**: Verify navigation menu does not include ticket/template items
4. **Task Assignment**: Verify task assignment UI does not include service type selection
5. **API Endpoints**: Verify `/api/tickets` and `/api/templates` endpoints return 404 errors

### Preservation Checking

**Goal**: Verify that all existing task management and other features continue to work exactly as before.

**Pseudocode:**
```
FOR ALL feature IN [task_management, user_management, attendance, chat, reports] DO
  result_original := feature_original(testInput)
  result_fixed := feature_fixed(testInput)
  ASSERT result_original = result_fixed
END FOR
```

**Testing Approach**: Property-based testing is recommended for preservation checking because:
- It generates many test cases automatically across the input domain
- It catches edge cases that manual unit tests might miss
- It provides strong guarantees that behavior is unchanged for all non-ticket/template features

**Test Plan**: Observe behavior on original code for task management and other features, then write property-based tests capturing that behavior to verify it continues after removal.

**Test Cases**:
1. **Task Creation Preservation**: Verify task creation works identically before and after removal
2. **Task Assignment Preservation**: Verify task assignment (without service type) works as before
3. **Task Viewing Preservation**: Verify employees can view assigned tasks exactly as before
4. **Task Submission Preservation**: Verify task submission and reporting works unchanged
5. **User Management Preservation**: Verify user creation, editing, and deletion works unchanged
6. **Attendance Tracking Preservation**: Verify attendance tracking continues to work
7. **Chat and Notifications Preservation**: Verify messaging and notifications work unchanged
8. **Report Generation Preservation**: Verify report creation and export works unchanged

### Unit Tests

- Test that removed screen files are not imported anywhere
- Test that removed route files are not registered in server.js
- Test that removed model files are not referenced in controllers or services
- Test that task creation works without service type field
- Test that task assignment works without service type selection
- Test that admin dashboard renders without ticket/template menu items
- Test that employee dashboard renders without ticket-related pages

### Property-Based Tests

- Generate random task creation inputs and verify they work identically before and after removal
- Generate random user interactions and verify no ticket/template options appear
- Generate random task assignments and verify they complete successfully without service type
- Generate random navigation paths and verify no broken links to removed screens
- Generate random API requests and verify no 404 errors for non-ticket/template endpoints

### Integration Tests

- Test full admin workflow: login → create task → assign task → verify task appears for employee
- Test full employee workflow: login → view assigned tasks → submit task → verify submission recorded
- Test admin dashboard: verify all menu items work and no ticket/template options appear
- Test employee dashboard: verify all pages load and no ticket-related options appear
- Test application startup: verify database initializes without ticket/template seed data
- Test API server startup: verify all routes load and no ticket/template routes are registered

## Rollback Considerations

### Rollback Strategy

If issues are discovered after removal that require reverting the changes:

**1. Version Control Rollback**
- Use git to revert commits that removed ticket/template functionality
- Restore all removed files from version control
- Restore all modified files to their previous state

**2. Database Rollback**
- If production data was affected, restore from backup
- Re-seed ticket/template data if necessary
- Verify data integrity after restoration

**3. Deployment Rollback**
- If deployed to production, redeploy previous version
- Notify users of the rollback
- Investigate root cause of issues before attempting removal again

### Risk Mitigation

**1. Backup Strategy**
- Create full backup of codebase before starting removal
- Create database backup before removing collections
- Document all changes made during removal

**2. Testing Before Deployment**
- Run full test suite before deploying to production
- Perform manual testing of all major workflows
- Verify no broken links or missing functionality

**3. Staged Rollout**
- Deploy to development environment first
- Deploy to staging environment for user acceptance testing
- Deploy to production only after successful staging verification

**4. Monitoring and Alerts**
- Monitor application logs for errors after deployment
- Set up alerts for API errors or missing endpoints
- Monitor user feedback for issues

### Recovery Procedures

**If Critical Issues Discovered:**
1. Immediately rollback to previous version using git
2. Restore database from backup if necessary
3. Investigate root cause of issues
4. Document findings and plan corrective actions
5. Attempt removal again with fixes to address issues

**If Minor Issues Discovered:**
1. Create hotfix branch to address specific issues
2. Test hotfix thoroughly before merging
3. Deploy hotfix to production
4. Continue with removal process

## Verification Checklist

### Pre-Removal Verification
- [ ] All ticket/template files identified and documented
- [ ] All references to ticket/template functionality identified
- [ ] Backup of codebase created
- [ ] Database backup created
- [ ] Test suite passes on original code
- [ ] All team members notified of removal plan

### Removal Verification
- [ ] All screen files removed from Flutter
- [ ] All route files removed from backend
- [ ] All model files removed from backend
- [ ] All service files removed from backend
- [ ] All seed data files removed from backend
- [ ] All references cleaned up from remaining code
- [ ] No orphaned imports or dead code remains
- [ ] Flutter project builds without errors
- [ ] Node.js server starts without errors

### Post-Removal Verification
- [ ] All exploratory removal tests pass
- [ ] All fix checking tests pass
- [ ] All preservation checking tests pass
- [ ] All unit tests pass
- [ ] All property-based tests pass
- [ ] All integration tests pass
- [ ] No console errors or warnings
- [ ] No broken links in navigation
- [ ] Admin dashboard displays correctly
- [ ] Employee dashboard displays correctly
- [ ] Task creation and assignment work
- [ ] Task submission and reporting work
- [ ] All other features work unchanged

### Deployment Verification
- [ ] Code review completed
- [ ] All tests pass in CI/CD pipeline
- [ ] Staging environment testing completed
- [ ] User acceptance testing completed
- [ ] Rollback plan documented and tested
- [ ] Monitoring and alerts configured
- [ ] Team trained on new workflow
- [ ] Documentation updated
- [ ] Release notes prepared
