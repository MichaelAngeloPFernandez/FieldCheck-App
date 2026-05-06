# Implementation Plan

## Phase 1: Navigation Order and Mobile Menu Fixes

- [x] 1. Write bug condition exploration test for Phase 1
  - **Property 1: Bug Condition** - Navigation Order and Mobile Menu Issues
  - **CRITICAL**: This test MUST FAIL on unfixed code - failure confirms the bugs exist
  - **DO NOT attempt to fix the test or the code when it fails**
  - **NOTE**: This test encodes the expected behavior - it will validate the fixes when it passes after implementation
  - **GOAL**: Surface counterexamples that demonstrate navigation order and mobile menu bugs exist
  - **Scoped PBT Approach**: Test specific navigation interactions on desktop (NavigationRail order) and mobile (BottomNavigationBar vs Drawer)
  - Test that desktop NavigationRail destinations are in incorrect order: current order != [Dashboard, Employees, Admins, Geofences, Reports, Settings, Tasks]
  - Test that mobile devices show BottomNavigationBar instead of hamburger drawer menu
  - Test that keyboard shortcuts (Ctrl+1-7) point to wrong destinations due to incorrect order
  - Run test on UNFIXED code
  - **EXPECTED OUTCOME**: Test FAILS (this is correct - it proves the navigation bugs exist)
  - Document counterexamples found to understand root cause
  - Mark task complete when test is written, run, and failure is documented
  - _Requirements: 1.1, 1.2_

- [x] 2. Write preservation property tests for Phase 1 (BEFORE implementing fix)
  - **Property 2: Preservation** - Navigation Functionality Preservation
  - **IMPORTANT**: Follow observation-first methodology
  - Observe behavior on UNFIXED code for keyboard shortcuts, responsive layout detection, and non-navigation interactions
  - Write property-based tests capturing observed behavior patterns from Preservation Requirements
  - Property-based testing generates many test cases for stronger guarantees
  - Run tests on UNFIXED code
  - **EXPECTED OUTCOME**: Tests PASS (this confirms baseline behavior to preserve)
  - Mark task complete when tests are written, run, and passing on unfixed code
  - _Requirements: 3.1, 3.2_

- [x] 3. Fix Phase 1 - Navigation Order and Mobile Menu Implementation

  - [x] 3.1 Fix NavigationRail destination order in admin_dashboard_screen.dart
    - Locate NavigationRail destinations array (around line 800-900)
    - Reorder destinations to correct sequence: 0: Dashboard | 1: Employees | 2: Admins | 3: Geofences | 4: Reports | 5: Settings | 6: Tasks
    - Update corresponding navigation handlers to match new order
    - Update keyboard shortcut handlers (Ctrl+1-7) to map to correct destinations
    - _Bug_Condition: isBugCondition_Phase1(input) where input.platform == 'desktop' AND destinationOrderIncorrect(input)_
    - _Expected_Behavior: correctNavigationOrder(result) from design_
    - _Preservation: Keyboard shortcuts must continue to respond correctly_
    - _Requirements: 1.1, 2.1, 3.1_

  - [x] 3.2 Implement mobile hamburger drawer menu in admin_dashboard_screen.dart
    - Add responsive layout detection in build method
    - Replace BottomNavigationBar with Drawer widget for mobile screens (width < 600px)
    - Implement drawer with all 7 navigation items plus logout button
    - Add proper drawer header with user info
    - Ensure drawer items map to correct destinations using fixed navigation order
    - _Bug_Condition: isBugCondition_Phase1(input) where input.platform == 'mobile' AND shouldUseHamburgerDrawer(input)_
    - _Expected_Behavior: properMobileMenu(result) from design_
    - _Preservation: Screen size detection for responsive layout must continue to work_
    - _Requirements: 1.2, 2.2, 3.2_

  - [x] 3.3 Verify Phase 1 bug condition exploration test now passes
    - **Property 1: Expected Behavior** - Navigation Order and Mobile Menu Fixed
    - **IMPORTANT**: Re-run the SAME test from task 1 - do NOT write a new test
    - The test from task 1 encodes the expected behavior
    - When this test passes, it confirms the expected behavior is satisfied
    - Run bug condition exploration test from step 1
    - **EXPECTED OUTCOME**: Test PASSES (confirms navigation bugs are fixed)
    - _Requirements: Expected Behavior Properties from design_

  - [x] 3.4 Verify Phase 1 preservation tests still pass
    - **Property 2: Preservation** - Navigation Functionality Preservation
    - **IMPORTANT**: Re-run the SAME tests from task 2 - do NOT write new tests
    - Run preservation property tests from step 2
    - **EXPECTED OUTCOME**: Tests PASS (confirms no regressions)
    - Confirm all tests still pass after fix (no regressions)

## Phase 2: Pending Tickets Inbox Tab Addition

- [x] 4. Write bug condition exploration test for Phase 2
  - **Property 1: Bug Condition** - Missing Pending Tickets Tab
  - **CRITICAL**: This test MUST FAIL on unfixed code - failure confirms the bug exists
  - **DO NOT attempt to fix the test or the code when it fails**
  - **NOTE**: This test encodes the expected behavior - it will validate the fix when it passes after implementation
  - **GOAL**: Surface counterexamples that demonstrate missing pending tickets tab
  - **Scoped PBT Approach**: Test admin dashboard inbox tabs for pending tickets accessibility
  - Test that admin_dashboard_screen inbox tabs count is 3 instead of required 4
  - Test that pending client tickets are NOT accessible through UI tabs
  - Test that no count badge exists for pending tickets
  - Run test on UNFIXED code
  - **EXPECTED OUTCOME**: Test FAILS (this is correct - it proves the missing tab bug exists)
  - Document counterexamples found to understand root cause
  - Mark task complete when test is written, run, and failure is documented
  - _Requirements: 1.3_

- [x] 5. Write preservation property tests for Phase 2 (BEFORE implementing fix)
  - **Property 2: Preservation** - Existing Inbox Functionality Preservation
  - **IMPORTANT**: Follow observation-first methodology
  - Observe behavior on UNFIXED code for existing inbox tabs functionality
  - Write property-based tests capturing observed behavior patterns from Preservation Requirements
  - Property-based testing generates many test cases for stronger guarantees
  - Run tests on UNFIXED code
  - **EXPECTED OUTCOME**: Tests PASS (this confirms baseline behavior to preserve)
  - Mark task complete when tests are written, run, and passing on unfixed code
  - _Requirements: 3.3_

- [x] 6. Fix Phase 2 - Pending Tickets Inbox Tab Implementation

  - [x] 6.1 Add pending tickets tab to admin dashboard inbox
    - Locate existing inbox tabs configuration in admin_dashboard_screen.dart (_buildInboxTabs method)
    - Add 4th tab for "Pending Tickets" with appropriate icon (Icons.pending_actions) and label
    - Implement tab content widget for pending tickets display
    - Add proper tab switching logic to handle 4th tab
    - _Bug_Condition: isBugCondition_Phase2(input) where NOT pendingTicketsTabExists(input.inboxTabs)_
    - _Expected_Behavior: pendingTicketsTabExists(result) AND ticketCountDisplayed(result) from design_
    - _Preservation: Existing inbox tabs must continue to display and function correctly_
    - _Requirements: 1.3, 2.3, 3.3_

  - [x] 6.2 Implement backend integration for pending tickets
    - Add service call to fetch pending client tickets filtered by status: 'pending'
    - Implement count badge showing number of pending tickets
    - Add real-time updates for pending ticket count changes using existing Socket.IO
    - Create pending tickets list widget with ticket details (ID, title, date, client)
    - Add navigation to individual ticket details
    - Implement proper loading and error states for pending tickets tab
    - _Bug_Condition: Backend integration missing for pending tickets access_
    - _Expected_Behavior: Real-time pending ticket count and accessible ticket list_
    - _Preservation: Other realtime features through Socket.IO must continue to work_
    - _Requirements: 2.3, 3.7_

  - [x] 6.3 Verify Phase 2 bug condition exploration test now passes
    - **Property 1: Expected Behavior** - Pending Tickets Tab Available
    - **IMPORTANT**: Re-run the SAME test from task 4 - do NOT write a new test
    - The test from task 4 encodes the expected behavior
    - When this test passes, it confirms the expected behavior is satisfied
    - Run bug condition exploration test from step 4
    - **EXPECTED OUTCOME**: Test PASSES (confirms pending tickets tab bug is fixed)
    - _Requirements: Expected Behavior Properties from design_

  - [x] 6.4 Verify Phase 2 preservation tests still pass
    - **Property 2: Preservation** - Existing Inbox Functionality Preservation
    - **IMPORTANT**: Re-run the SAME tests from task 5 - do NOT write new tests
    - Run preservation property tests from step 5
    - **EXPECTED OUTCOME**: Tests PASS (confirms no regressions)
    - Confirm all tests still pass after fix (no regressions)

## Phase 3: Hybrid Ticket Linking in Task Form

- [x] 7. Write bug condition exploration test for Phase 3
  - **Property 1: Bug Condition** - Missing Ticket Linking Fields
  - **CRITICAL**: This test MUST FAIL on unfixed code - failure confirms the bug exists
  - **DO NOT attempt to fix the test or the code when it fails**
  - **NOTE**: This test encodes the expected behavior - it will validate the fix when it passes after implementation
  - **GOAL**: Surface counterexamples that demonstrate missing ticket linking functionality
  - **Scoped PBT Approach**: Test task creation form for ticket linking fields availability
  - Test that admin_task_management_screen task creation dialog lacks "Link to Pending Ticket" dropdown
  - Test that task creation form lacks "Client Ticket Number" manual text field
  - Test that task creation succeeds but cannot associate with client tickets
  - Run test on UNFIXED code
  - **EXPECTED OUTCOME**: Test FAILS (this is correct - it proves the ticket linking bug exists)
  - Document counterexamples found to understand root cause
  - Mark task complete when test is written, run, and failure is documented
  - _Requirements: 1.4_

- [x] 8. Write preservation property tests for Phase 3 (BEFORE implementing fix)
  - **Property 2: Preservation** - Task Creation Without Linking Preservation
  - **IMPORTANT**: Follow observation-first methodology
  - Observe behavior on UNFIXED code for task creation without ticket linking
  - Write property-based tests capturing observed behavior patterns from Preservation Requirements
  - Property-based testing generates many test cases for stronger guarantees
  - Run tests on UNFIXED code
  - **EXPECTED OUTCOME**: Tests PASS (this confirms baseline behavior to preserve)
  - Mark task complete when tests are written, run, and passing on unfixed code
  - _Requirements: 3.4_

- [x] 9. Fix Phase 3 - Ticket Linking Implementation in Task Form

  - [x] 9.1 Add ticket linking dropdown to task creation form
    - Locate task creation dialog in admin_task_management_screen.dart (around line 400-600)
    - Add "Link to Pending Ticket" dropdown field after existing fields (after difficulty field)
    - Implement service call to fetch pending tickets for dropdown population
    - Add auto-fill functionality when ticket is selected (populate description with ticket details)
    - Add proper loading state while fetching pending tickets
    - _Bug_Condition: isBugCondition_Phase3(input) where NOT ticketLinkingFieldsExist(input.taskForm)_
    - _Expected_Behavior: ticketLinkingFieldsExist(result) AND ticketValidationWorks(result) from design_
    - _Preservation: Task creation without ticket linking must continue to work normally_
    - _Requirements: 1.4, 2.4, 3.4_

  - [x] 9.2 Add manual ticket number field to task creation form
    - Add "Client Ticket Number" text field as alternative to dropdown
    - Implement validation for ticket number format (RNG-YYYYMMDD-XXXX pattern)
    - Add field clearing when dropdown selection changes and vice versa
    - Add helper text showing expected format
    - Implement backend validation for ticket number existence
    - _Bug_Condition: Manual ticket linking field missing for flexibility_
    - _Expected_Behavior: Both dropdown and manual field available for ticket linking_
    - _Preservation: Existing task creation fields must continue to work_
    - _Requirements: 2.4, 3.4_

  - [x] 9.3 Implement backend integration for ticket linking
    - Modify task creation service call to include ticket linking data
    - Add ticket validation on backend before task creation
    - Implement proper error handling for invalid ticket numbers
    - Add ticket-task association in database
    - Update task model to include linked ticket information
    - _Bug_Condition: Backend integration missing for ticket-task association_
    - _Expected_Behavior: Tasks properly linked to client tickets with validation_
    - _Preservation: Task creation without linking must remain unchanged_
    - _Requirements: 2.4, 3.4_

  - [x] 9.4 Verify Phase 3 bug condition exploration test now passes
    - **Property 1: Expected Behavior** - Ticket Linking Fields Available
    - **IMPORTANT**: Re-run the SAME test from task 7 - do NOT write a new test
    - The test from task 7 encodes the expected behavior
    - When this test passes, it confirms the expected behavior is satisfied
    - Run bug condition exploration test from step 7
    - **EXPECTED OUTCOME**: Test PASSES (confirms ticket linking bug is fixed)
    - _Requirements: Expected Behavior Properties from design_

  - [x] 9.5 Verify Phase 3 preservation tests still pass
    - **Property 2: Preservation** - Task Creation Without Linking Preservation
    - **IMPORTANT**: Re-run the SAME tests from task 8 - do NOT write new tests
    - Run preservation property tests from step 8
    - **EXPECTED OUTCOME**: Tests PASS (confirms no regressions)
    - Confirm all tests still pass after fix (no regressions)

## Phase 4: Client Ticket Submission Error Fixes

- [x] 10. Write bug condition exploration test for Phase 4
  - **Property 1: Bug Condition** - Socket.IO Submission Error Issues
  - **CRITICAL**: This test MUST FAIL on unfixed code - failure confirms the bug exists
  - **DO NOT attempt to fix the test or the code when it fails**
  - **NOTE**: This test encodes the expected behavior - it will validate the fix when it passes after implementation
  - **GOAL**: Surface counterexamples that demonstrate Socket.IO error handling problems
  - **Scoped PBT Approach**: Test client ticket submission with Socket.IO connection issues
  - Test that client_ticket_form.dart shows red error dialogs on Socket.IO failures
  - Test that Socket.IO errors are mixed with HTTP request errors causing confusion
  - Test that no retry mechanism exists when submission fails
  - Test that no console logging identifies specific failure points
  - Run test on UNFIXED code
  - **EXPECTED OUTCOME**: Test FAILS (this is correct - it proves the error handling bugs exist)
  - Document counterexamples found to understand root cause
  - Mark task complete when test is written, run, and failure is documented
  - _Requirements: 1.5, 1.6, 1.7_

- [x] 11. Write preservation property tests for Phase 4 (BEFORE implementing fix)
  - **Property 2: Preservation** - Stable Socket.IO Success Flow Preservation
  - **IMPORTANT**: Follow observation-first methodology
  - Observe behavior on UNFIXED code for successful ticket submissions and other Socket.IO features
  - Write property-based tests capturing observed behavior patterns from Preservation Requirements
  - Property-based testing generates many test cases for stronger guarantees
  - Run tests on UNFIXED code
  - **EXPECTED OUTCOME**: Tests PASS (this confirms baseline behavior to preserve)
  - Mark task complete when tests are written, run, and passing on unfixed code
  - _Requirements: 3.5, 3.6, 3.7_

- [x] 12. Fix Phase 4 - Socket.IO Error Handling Enhancement

  - [x] 12.1 Add Socket.IO connection validation in client_ticket_form.dart
    - Locate _submitForm method in client_ticket_form.dart
    - Add Socket.IO connection check before form submission
    - Import and use RealtimeService to verify connection status
    - Show appropriate message if Socket.IO is disconnected
    - Prevent submission if connection is not available
    - _Bug_Condition: isBugCondition_Phase4(input) where socketIOConnectionFails(input)_
    - _Expected_Behavior: properErrorHandling(result) AND retryMechanismExists(result) from design_
    - _Preservation: Socket.IO connection stability for successful submissions must remain unchanged_
    - _Requirements: 1.5, 2.5, 3.5_

  - [x] 12.2 Implement error type separation and enhanced messaging
    - Modify error handling in _submitForm method to distinguish error types
    - Create separate error messages for Socket.IO vs HTTP errors
    - Remove red error dialogs for Socket.IO connection issues
    - Implement user-friendly error messages with clear next steps
    - Add error type classification in error response structure
    - _Bug_Condition: Socket.IO errors mixed with HTTP request errors causing confusion_
    - _Expected_Behavior: Clear error messaging separating Socket.IO from HTTP errors_
    - _Preservation: Other client ticket form features must continue to function_
    - _Requirements: 1.6, 2.6, 3.6_

  - [x] 12.3 Add retry mechanism with exponential backoff
    - Add retry button in error dialog for failed submissions
    - Implement exponential backoff for retry attempts (1s, 2s, 4s delays)
    - Add maximum retry limit (3 attempts)
    - Show retry attempt counter in error dialog
    - Disable form during retry attempts to prevent duplicate submissions
    - _Bug_Condition: No retry mechanism available when submission fails_
    - _Expected_Behavior: Retry button available with proper backoff strategy_
    - _Preservation: Successful submission flow must remain unchanged_
    - _Requirements: 1.7, 2.7, 3.5_

  - [x] 12.4 Implement enhanced logging and debugging
    - Add console logging at key points in submission process
    - Log Socket.IO connection status, HTTP request details, and error specifics
    - Include timestamp and error context in logs
    - Add submission attempt tracking for debugging
    - Implement structured logging format for easier debugging
    - _Bug_Condition: No console logging to identify specific failure points_
    - _Expected_Behavior: Comprehensive logging for debugging submission issues_
    - _Preservation: Other realtime features logging must not be affected_
    - _Requirements: 2.7, 3.7_

  - [x] 12.5 Enhance client_ticket_service.dart for better error handling
    - Add RealtimeService dependency for connection validation
    - Check Socket.IO connection before HTTP request
    - Return specific error codes for different failure types
    - Add retry-ability flag to error responses
    - Include specific error codes for different failure scenarios
    - _Bug_Condition: Backend service lacks proper error classification_
    - _Expected_Behavior: Service provides detailed error information for proper handling_
    - _Preservation: Existing service functionality must remain unchanged_
    - _Requirements: 2.5, 2.6, 3.5_

  - [x] 12.6 Enhance realtime_service.dart connection management
    - Add public getter for connection status validation
    - Implement connection health check method
    - Add connection retry with exponential backoff
    - Enhance error event listeners for better error classification
    - Add specific handlers for connection timeout vs network errors
    - Implement connection recovery notifications
    - _Bug_Condition: RealtimeService lacks connection validation methods_
    - _Expected_Behavior: Service provides reliable connection status and recovery_
    - _Preservation: Other realtime features must continue to work without disruption_
    - _Requirements: 2.5, 3.7_

  - [x] 12.7 Verify Phase 4 bug condition exploration test now passes
    - **Property 1: Expected Behavior** - Socket.IO Error Handling Fixed
    - **IMPORTANT**: Re-run the SAME test from task 10 - do NOT write a new test
    - The test from task 10 encodes the expected behavior
    - When this test passes, it confirms the expected behavior is satisfied
    - Run bug condition exploration test from step 10
    - **EXPECTED OUTCOME**: Test PASSES (confirms Socket.IO error handling bugs are fixed)
    - _Requirements: Expected Behavior Properties from design_

  - [x] 12.8 Verify Phase 4 preservation tests still pass
    - **Property 2: Preservation** - Stable Socket.IO Success Flow Preservation
    - **IMPORTANT**: Re-run the SAME tests from task 11 - do NOT write new tests
    - Run preservation property tests from step 11
    - **EXPECTED OUTCOME**: Tests PASS (confirms no regressions)
    - Confirm all tests still pass after fix (no regressions)

## Integration and Final Validation

- [ ] 13. Cross-phase integration testing
  - Test navigation fixes work correctly with new pending tickets tab
  - Test mobile hamburger drawer includes access to pending tickets
  - Test task creation with ticket linking works from pending tickets tab
  - Test complete workflow: client ticket submission → pending tickets tab → task creation with linking
  - Verify all keyboard shortcuts work correctly across all phases
  - Test responsive behavior across all implemented features

- [ ] 14. End-to-end workflow validation
  - Test complete admin workflow: login → navigation → pending tickets → task creation with linking
  - Test complete client workflow: login → ticket submission → error handling → retry mechanism
  - Test mobile and desktop experiences across all phases
  - Verify Socket.IO connection handling doesn't affect other realtime features
  - Test error scenarios across all phases to ensure proper error handling

- [ ] 15. Performance and stability testing
  - Test navigation performance with new mobile drawer implementation
  - Test pending tickets tab performance with large numbers of tickets
  - Test task creation performance with ticket linking dropdown population
  - Test Socket.IO error handling performance under various network conditions
  - Verify memory usage and connection management across all phases

- [ ] 16. Final checkpoint - Ensure all tests pass
  - Run all Phase 1 exploration and preservation tests
  - Run all Phase 2 exploration and preservation tests  
  - Run all Phase 3 exploration and preservation tests
  - Run all Phase 4 exploration and preservation tests
  - Verify no regressions in existing functionality
  - Confirm all requirements are met across all phases
  - Ask the user if questions arise or additional testing is needed