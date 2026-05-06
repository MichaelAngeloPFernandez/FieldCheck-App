# Bugfix Requirements Document

## Introduction

This document addresses critical production issues in the Flutter application affecting navigation, ticket management, and form submissions. The bugs impact both admin and employee interfaces, causing navigation confusion, missing functionality, and failed ticket submissions. These issues require immediate attention as they affect core user workflows and data integrity.

## Bug Analysis

### Current Behavior (Defect)

1.1 WHEN users navigate on desktop THEN the NavigationRail destinations are in incorrect order causing confusion between expected and actual navigation indices

1.2 WHEN users access the app on mobile devices THEN the BottomNavigationBar is displayed instead of a proper mobile-friendly hamburger drawer menu

1.3 WHEN admins view the inbox tabs in admin_dashboard_screen.dart THEN there is no tab for pending client tickets, making them inaccessible

1.4 WHEN admins try to create tasks linked to client tickets THEN there is no dropdown or manual field to link tickets to tasks in the task form

1.5 WHEN clients submit tickets through client_ticket_form.dart THEN red error dialogs appear and tickets fail to submit due to Socket.IO async errors

1.6 WHEN the Socket.IO connection fails during ticket submission THEN the system does not separate Socket.IO errors from HTTP request errors, causing confusion

1.7 WHEN ticket submission fails THEN there is no retry mechanism or proper error logging to identify the failure point

### Expected Behavior (Correct)

2.1 WHEN users navigate on desktop THEN the NavigationRail destinations SHALL be in correct order: 0: Dashboard | 1: Employees | 2: Admins | 3: Geofences | 4: Reports | 5: Settings | 6: Tasks

2.2 WHEN users access the app on mobile devices THEN the system SHALL display a hamburger drawer menu with all 7 navigation items plus logout button instead of BottomNavigationBar

2.3 WHEN admins view the inbox tabs THEN the system SHALL display a 4th tab for pending client tickets with a count badge showing pending tickets filtered by status: 'pending'

2.4 WHEN admins create tasks THEN the system SHALL provide both a dropdown for "Link to Pending Ticket" that fetches from backend and auto-fills, plus a manual "Client Ticket Number" text field for flexibility

2.5 WHEN clients submit tickets THEN the system SHALL check Socket.IO connection before submission and handle errors gracefully without displaying red error dialogs

2.6 WHEN Socket.IO connection issues occur THEN the system SHALL separate Socket.IO errors from HTTP request errors and provide clear error messaging

2.7 WHEN ticket submission fails THEN the system SHALL provide a retry button in error dialog and add console logging to identify the specific failure point

### Unchanged Behavior (Regression Prevention)

3.1 WHEN users navigate using existing keyboard shortcuts (Ctrl+1 through Ctrl+7) THEN the system SHALL CONTINUE TO respond to these shortcuts correctly

3.2 WHEN the app determines screen size for responsive layout THEN the system SHALL CONTINUE TO properly detect desktop vs mobile layouts

3.3 WHEN admins view existing inbox tabs (current functionality) THEN the system SHALL CONTINUE TO display and function correctly

3.4 WHEN tasks are created without ticket linking THEN the system SHALL CONTINUE TO create tasks normally as before

3.5 WHEN Socket.IO connection is stable THEN ticket submission SHALL CONTINUE TO work without any changes to the success flow

3.6 WHEN users interact with other parts of the client ticket form (validation, file uploads, etc.) THEN these features SHALL CONTINUE TO function as expected

3.7 WHEN the app handles other realtime features through Socket.IO THEN these SHALL CONTINUE TO work without disruption