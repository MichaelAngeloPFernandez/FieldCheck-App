# Implementation Plan: Ticket Status Synchronization

## Overview

This implementation plan breaks down the ticket status synchronization feature into discrete coding tasks. The feature automatically synchronizes client ticket status based on linked task status changes and sends email notifications to clients. The implementation follows a modular approach with three main components: the status synchronization service, email notification enhancements, and API integration.

## Tasks

- [x] 1. Create the Status Synchronization Service module
  - Create `backend/services/ticketStatusSyncService.js` file
  - Implement the `syncTicketStatus(taskId)` function with Promise return type
  - Add task and ticket retrieval logic with null checks
  - Implement the 1:1 status mapping object (in_progress, pending_review, completed, closed)
  - Add terminal status protection (closed, expired)
  - Implement ticket status update with Mongoose save() method
  - Add comprehensive logging (debug, info, error levels)
  - Ensure all errors are caught and logged without throwing
  - _Requirements: 1.1, 1.2, 1.3, 1.4, 2.1, 2.2, 2.3, 2.4, 3.1, 3.4, 3.5, 4.1, 4.2, 4.3, 4.4, 4.5, 5.1, 5.2, 5.3, 7.1, 7.2, 7.3, 7.4, 8.1, 8.3, 8.4, 8.5, 9.1, 9.2, 9.3, 9.4_

- [ ]* 1.1 Write property test for Status Mapping Correctness
  - **Property 1: Status Mapping Correctness**
  - Generate random tasks with mapped statuses (in_progress, pending_review, completed, closed)
  - Create linked tickets with various initial statuses
  - Call syncTicketStatus and verify ticket status matches mapped value
  - Run with at least 100 iterations
  - **Validates: Requirements 1.1, 1.2, 1.3, 1.4, 4.1, 4.2, 4.3, 4.4**

- [ ]* 1.2 Write property test for Unmapped Status Preservation
  - **Property 2: Unmapped Status Preservation**
  - Generate random tasks with unmapped statuses (pending, created, assigned, accepted, blocked, reviewed)
  - Create linked tickets with various initial statuses
  - Call syncTicketStatus and verify ticket status remains unchanged
  - Run with at least 100 iterations
  - **Validates: Requirements 4.5**

- [ ]* 1.3 Write property test for Timestamp Update
  - **Property 3: Timestamp Update**
  - Generate random tasks with mapped statuses
  - Record timestamp before calling syncTicketStatus
  - Verify ticket updatedAt is equal to or after the recorded timestamp
  - Run with at least 100 iterations
  - **Validates: Requirements 2.3, 9.3**

- [ ]* 1.4 Write property test for Data Preservation
  - **Property 4: Data Preservation**
  - Generate random tickets with various field values
  - Record all ticket fields before synchronization
  - Call syncTicketStatus and verify all fields except status and updatedAt are unchanged
  - Run with at least 100 iterations
  - **Validates: Requirements 2.4, 5.3**

- [ ]* 1.5 Write property test for Terminal Status Protection
  - **Property 11: Terminal Status Protection**
  - Generate random tickets with terminal statuses (closed, expired)
  - Generate random tasks with mapped statuses
  - Call syncTicketStatus and verify ticket status remains in terminal state
  - Run with at least 100 iterations
  - **Validates: Requirements 9.2**

- [ ]* 1.6 Write unit tests for Status Synchronization Service
  - Test task not found scenario (returns without error)
  - Test ticket not found scenario (returns without error)
  - Test no linked ticket scenario (returns without error)
  - Test database error handling (logs error, doesn't throw)
  - Test unmapped status handling (no ticket update)
  - Test successful synchronization with logging
  - _Requirements: 3.1, 3.4, 7.3, 8.4_

- [x] 2. Create the Email Status Update Template
  - Create `backend/utils/templates/ticketStatusUpdateEmail.js` file
  - Implement `ticketStatusUpdateEmail(clientName, ticketNumber, newStatus, trackingLink)` function
  - Add status-specific messages and icons for each status (in_progress, pending_review, completed, closed)
  - Include rating prompt for completed status
  - Add responsive HTML email template with gradient header
  - Include ticket number display box
  - Add "View Ticket Details" button with tracking link
  - Add footer with automated notification message
  - _Requirements: 6.1, 6.2, 6.3, 6.4_

- [ ]* 2.1 Write property test for Email Recipient Correctness
  - **Property 8: Email Recipient Correctness**
  - Generate random tickets with various clientEmail values
  - Mock the email service to capture sent emails
  - Call sendStatusUpdateEmail and verify recipient matches ticket.clientEmail
  - Run with at least 100 iterations
  - **Validates: Requirements 6.5**

- [ ]* 2.2 Write unit tests for Email Template
  - Test template output contains ticket number
  - Test template output contains status message
  - Test template output contains tracking link
  - Test completed status includes rating prompt
  - Test all status types render correctly
  - _Requirements: 6.1, 6.2, 6.3, 6.4_

- [x] 3. Extend Email Service with Status Update Function
  - Open `backend/utils/emailService.js`
  - Import the ticketStatusUpdateEmail template
  - Import generateEmailToken utility (or reuse existing token logic)
  - Implement `sendStatusUpdateEmail(ticket, newStatus)` function
  - Generate tracking link with token and FRONTEND_URL
  - Call ticketStatusUpdateEmail template with ticket data
  - Call existing sendEmail function with formatted email
  - Export the new function
  - _Requirements: 1.5, 6.1, 6.2, 6.3, 6.4, 6.5_

- [ ]* 3.1 Write property test for Email Failure Isolation
  - **Property 5: Email Failure Isolation**
  - Generate random tickets and statuses
  - Mock email service to throw errors
  - Call syncTicketStatus and verify ticket status is still updated in database
  - Run with at least 100 iterations
  - **Validates: Requirements 3.3**

- [ ]* 3.2 Write unit tests for Email Service Extension
  - Test sendStatusUpdateEmail generates correct tracking link
  - Test sendStatusUpdateEmail calls template with correct parameters
  - Test sendStatusUpdateEmail calls sendEmail with correct data
  - Test email failure is logged but doesn't throw
  - _Requirements: 1.5, 3.2, 3.3_

- [x] 4. Integrate Email Notification into Synchronization Service
  - Open `backend/services/ticketStatusSyncService.js`
  - Import sendStatusUpdateEmail from emailService
  - After successful ticket.save(), add setImmediate block for email sending
  - Call sendStatusUpdateEmail with ticket and newStatus
  - Add try-catch for email errors with logging
  - Ensure email errors don't affect ticket update
  - Add success log for email sending
  - _Requirements: 1.5, 3.2, 3.3, 8.2_

- [ ]* 4.1 Write property test for Error Isolation
  - **Property 6: Error Isolation**
  - Generate random synchronization scenarios that trigger errors
  - Mock database and email services to throw errors
  - Call syncTicketStatus from a mock task update operation
  - Verify errors don't propagate to the calling operation
  - Run with at least 100 iterations
  - **Validates: Requirements 3.4, 10.5**

- [x] 5. Checkpoint - Ensure synchronization service tests pass
  - Run all property tests for the synchronization service
  - Run all unit tests for the synchronization service
  - Verify all tests pass
  - Ask the user if questions arise

- [x] 6. Integrate Synchronization into Task Controller
  - Open `backend/controllers/taskController.js`
  - Import syncTicketStatus from ticketStatusSyncService
  - Create helper function `triggerTicketSync(taskId)` that uses setImmediate
  - Add try-catch in helper with error logging
  - Ensure helper doesn't throw errors
  - _Requirements: 7.5, 10.1, 10.3, 10.4, 10.5_

- [ ]* 6.1 Write property test for Multi-Employee Task Authority
  - **Property 7: Multi-Employee Task Authority**
  - Generate random tasks with multiple UserTask assignments
  - Set different statuses on individual UserTask records
  - Call syncTicketStatus and verify ticket status matches parent Task status (not UserTask status)
  - Run with at least 100 iterations
  - **Validates: Requirements 5.1, 5.2**

- [ ]* 6.2 Write property test for Task Retrieval
  - **Property 9: Task Retrieval**
  - Generate random valid task IDs with linked tickets
  - Call syncTicketStatus and verify both task and ticket are retrieved successfully
  - Run with at least 100 iterations
  - **Validates: Requirements 7.2**

- [ ]* 6.3 Write property test for Graceful No-Op
  - **Property 10: Graceful No-Op**
  - Generate random task IDs with no linked tickets
  - Call syncTicketStatus and verify it returns successfully without throwing
  - Run with at least 100 iterations
  - **Validates: Requirements 7.3**

- [x] 7. Add synchronization to updateTask endpoint
  - Locate the `updateTask` function in taskController.js
  - After successful task.save() and before/after res.json() response
  - Call triggerTicketSync(task._id)
  - Ensure synchronization is non-blocking
  - _Requirements: 10.1, 10.3, 10.4_

- [x] 8. Add synchronization to updateUserTaskStatus endpoint
  - Locate the `updateUserTaskStatus` function in taskController.js
  - After successful userTask.save() and syncAggregateTaskStatus()
  - Call triggerTicketSync(userTask.taskId) with parent task ID
  - Ensure synchronization is non-blocking
  - _Requirements: 10.2, 10.3, 10.4_

- [ ] 9. Add synchronization to other task status endpoints
  - [x] 9.1 Add triggerTicketSync to acceptUserTask endpoint
    - After successful acceptance
    - Call triggerTicketSync with task ID
    - _Requirements: 10.3, 10.4_
  
  - [x] 9.2 Add triggerTicketSync to submitUserTaskForReview endpoint
    - After successful submission
    - Call triggerTicketSync with task ID
    - _Requirements: 10.3, 10.4_
  
  - [x] 9.3 Add triggerTicketSync to approveUserTask endpoint
    - After successful approval
    - Call triggerTicketSync with task ID
    - _Requirements: 10.3, 10.4_
  
  - [x] 9.4 Add triggerTicketSync to rejectUserTask endpoint
    - After successful rejection
    - Call triggerTicketSync with task ID
    - _Requirements: 10.3, 10.4_
  
  - [ ] 9.5 Add triggerTicketSync to blockUserTask endpoint
    - After successful blocking
    - Call triggerTicketSync with task ID
    - _Requirements: 10.3, 10.4_
  
  - [ ] 9.6 Add triggerTicketSync to unblockUserTask endpoint
    - After successful unblocking
    - Call triggerTicketSync with task ID
    - _Requirements: 10.3, 10.4_
  
  - [ ] 9.7 Add triggerTicketSync to closeBlockedUserTask endpoint
    - After successful closing
    - Call triggerTicketSync with task ID
    - _Requirements: 10.3, 10.4_

- [ ]* 9.8 Write integration tests for API endpoints
  - Test updateTask endpoint triggers synchronization
  - Test updateUserTaskStatus endpoint triggers synchronization
  - Test synchronization is non-blocking (response sent before sync completes)
  - Test synchronization errors don't affect API response
  - Mock database and email services
  - _Requirements: 10.1, 10.2, 10.3, 10.4, 10.5_

- [ ] 10. Final checkpoint - Ensure all tests pass
  - Run all property tests (minimum 100 iterations each)
  - Run all unit tests
  - Run all integration tests
  - Verify all tests pass
  - Verify logging output is correct
  - Ask the user if questions arise

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- The synchronization service is designed to be non-blocking and fail-safe
- All errors are logged but never thrown to prevent interrupting task updates
- Property tests validate universal correctness properties with at least 100 iterations
- Unit tests validate specific examples and edge cases
- Integration tests validate API endpoints with mocked services
- The implementation uses existing infrastructure (Mongoose, email service, logging)

## Task Dependency Graph

```
1. Create the Status Synchronization Service module
  ├─ 1.1 Write property test for Status Mapping Correctness (optional)
  ├─ 1.2 Write property test for Unmapped Status Preservation (optional)
  ├─ 1.3 Write property test for Timestamp Update (optional)
  ├─ 1.4 Write property test for Data Preservation (optional)
  ├─ 1.5 Write property test for Terminal Status Protection (optional)
  └─ 1.6 Write unit tests for Status Synchronization Service (optional)

2. Create the Email Status Update Template
  ├─ 2.1 Write property test for Email Recipient Correctness (optional)
  └─ 2.2 Write unit tests for Email Template (optional)

3. Extend Email Service with Status Update Function
  depends on: [2]
  ├─ 3.1 Write property test for Email Failure Isolation (optional)
  └─ 3.2 Write unit tests for Email Service Extension (optional)

4. Integrate Email Notification into Synchronization Service
  depends on: [1, 3]
  └─ 4.1 Write property test for Error Isolation (optional)

5. Checkpoint - Ensure synchronization service tests pass
  depends on: [4]

6. Integrate Synchronization into Task Controller
  depends on: [4]
  ├─ 6.1 Write property test for Multi-Employee Task Authority (optional)
  ├─ 6.2 Write property test for Task Retrieval (optional)
  └─ 6.3 Write property test for Graceful No-Op (optional)

7. Add synchronization to updateTask endpoint
  depends on: [6]

8. Add synchronization to updateUserTaskStatus endpoint
  depends on: [6]

9. Add synchronization to other task status endpoints
  depends on: [6]
  ├─ 9.1 Add triggerTicketSync to acceptUserTask endpoint
  ├─ 9.2 Add triggerTicketSync to submitUserTaskForReview endpoint
  ├─ 9.3 Add triggerTicketSync to approveUserTask endpoint
  ├─ 9.4 Add triggerTicketSync to rejectUserTask endpoint
  ├─ 9.5 Add triggerTicketSync to blockUserTask endpoint
  ├─ 9.6 Add triggerTicketSync to unblockUserTask endpoint
  ├─ 9.7 Add triggerTicketSync to closeBlockedUserTask endpoint
  └─ 9.8 Write integration tests for API endpoints (optional)

10. Final checkpoint - Ensure all tests pass
  depends on: [7, 8, 9]
```
