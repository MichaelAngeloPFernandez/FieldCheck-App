# Design Document: Ticket Status Synchronization

## Overview

This document describes the technical design for automatic synchronization of client ticket status based on linked task status changes in the FieldCheck application. The system ensures that when employees update task status through the mobile app, the corresponding client ticket status is automatically updated and clients are notified via email.

## Architecture

### System Components

The ticket status synchronization feature consists of three main components:

1. **Status Synchronization Service** (`ticketStatusSyncService.js`)
   - Standalone JavaScript module that handles the core synchronization logic
   - Monitors task status changes and updates corresponding ticket status
   - Implements 1:1 status mapping between tasks and tickets
   - Handles error cases gracefully without interrupting task operations

2. **Email Notification Service** (extends existing `emailService.js`)
   - Sends status update emails to clients when ticket status changes
   - Uses existing email infrastructure (SMTP, Resend API, Gmail API)
   - Includes ticket tracking links and status-specific content
   - Operates asynchronously to avoid blocking synchronization

3. **API Integration Layer** (modifies `taskController.js`)
   - Integrates synchronization service into existing task update endpoints
   - Calls synchronization asynchronously after successful task updates
   - Ensures synchronization errors don't affect task update responses

### Data Flow

```
Employee updates task status (Mobile App)
    ↓
Task Update API Endpoint (taskController.js)
    ↓
Task status saved to database
    ↓
API response sent to client (non-blocking)
    ↓
Status Synchronization Service called asynchronously (setImmediate)
    ↓
├─→ Retrieve Task and linked ClientTicket
├─→ Check if status mapping exists
├─→ Validate ticket is not in terminal state (closed/expired)
├─→ Update ticket status and updatedAt timestamp
├─→ Save ticket using Mongoose save() method
└─→ Trigger Email Notification Service (non-blocking)
    ↓
Email Notification Service
    ├─→ Generate status update email with tracking link
    ├─→ Send email to client
    └─→ Log success or failure (doesn't block ticket update)
```

## Component Design

### 1. Status Synchronization Service

**Module:** `backend/services/ticketStatusSyncService.js`

**Exports:**
```javascript
module.exports = {
  syncTicketStatus: async (taskId) => Promise<void>
};
```

**Core Function: `syncTicketStatus(taskId)`**

**Purpose:** Synchronize client ticket status based on task status change

**Parameters:**
- `taskId` (String|ObjectId): The ID of the task that was updated

**Returns:** Promise<void> - Resolves when synchronization is complete (or skipped)

**Behavior:**

1. **Retrieve Task and Ticket**
   ```javascript
   const task = await Task.findById(taskId).select('status linkedTaskId');
   if (!task) {
     console.debug('Task not found for synchronization', { taskId });
     return;
   }
   
   if (!task.linkedTaskId) {
     console.debug('Task has no linked ticket, skipping synchronization', { taskId });
     return;
   }
   
   const ticket = await ClientTicket.findById(task.linkedTaskId);
   if (!ticket) {
     console.debug('Linked ticket not found', { taskId, linkedTaskId: task.linkedTaskId });
     return;
   }
   ```

2. **Status Mapping**
   ```javascript
   const STATUS_MAPPING = {
     'in_progress': 'in_progress',
     'pending_review': 'pending_review',
     'completed': 'completed',
     'closed': 'closed'
   };
   
   const newTicketStatus = STATUS_MAPPING[task.status];
   if (!newTicketStatus) {
     console.debug('Task status not mapped to ticket status', { 
       taskId, 
       taskStatus: task.status 
     });
     return;
   }
   ```

3. **Terminal Status Protection**
   ```javascript
   if (['closed', 'expired'].includes(ticket.status)) {
     console.debug('Ticket is in terminal status, skipping update', {
       ticketNumber: ticket.ticketNumber,
       currentStatus: ticket.status
     });
     return;
   }
   ```

4. **Update Ticket Status**
   ```javascript
   const oldStatus = ticket.status;
   ticket.status = newTicketStatus;
   // updatedAt is automatically set by Mongoose pre-save hook
   
   try {
     await ticket.save(); // Use save() to trigger validations and hooks
     console.log('Ticket status synchronized', {
       ticketNumber: ticket.ticketNumber,
       taskId: taskId.toString(),
       oldStatus,
       newStatus: newTicketStatus
     });
   } catch (error) {
     console.error('Failed to update ticket status', {
       ticketNumber: ticket.ticketNumber,
       taskId: taskId.toString(),
       attemptedStatus: newTicketStatus,
       error: error.message
     });
     // Don't throw - let synchronization fail gracefully
     return;
   }
   ```

5. **Trigger Email Notification (Non-blocking)**
   ```javascript
   // Send email asynchronously without waiting
   setImmediate(async () => {
     try {
       await sendStatusUpdateEmail(ticket, newTicketStatus);
       console.log('Status update email sent', {
         ticketNumber: ticket.ticketNumber,
         clientEmail: ticket.clientEmail,
         newStatus: newTicketStatus
       });
     } catch (emailError) {
       console.error('Failed to send status update email', {
         ticketNumber: ticket.ticketNumber,
         clientEmail: ticket.clientEmail,
         error: emailError.message
       });
       // Email failure doesn't affect ticket update
     }
   });
   ```

**Error Handling:**
- All errors are caught and logged, never thrown
- Database errors log ticket number, task ID, attempted status, and error message
- Email errors log ticket number, client email, and error message
- Synchronization failures don't interrupt task update operations

### 2. Email Notification Service

**Module:** `backend/utils/emailService.js` (extend existing)

**New Function: `sendStatusUpdateEmail(ticket, newStatus)`**

**Purpose:** Send status update email to client with tracking link

**Parameters:**
- `ticket` (ClientTicket): The ticket object with client information
- `newStatus` (String): The new status value

**Email Template:** `backend/utils/templates/ticketStatusUpdateEmail.js`

**Template Function:**
```javascript
function ticketStatusUpdateEmail(clientName, ticketNumber, newStatus, trackingLink) {
  const statusMessages = {
    'in_progress': {
      title: 'Work Has Started',
      message: 'Our team has begun working on your support request.',
      icon: '🔧'
    },
    'pending_review': {
      title: 'Under Review',
      message: 'Work has been completed and is now under review by our team.',
      icon: '👀'
    },
    'completed': {
      title: 'Work Completed',
      message: 'Your support request has been completed successfully!',
      icon: '✅',
      showRating: true
    },
    'closed': {
      title: 'Ticket Closed',
      message: 'Your support ticket has been closed.',
      icon: '🔒'
    }
  };
  
  const statusInfo = statusMessages[newStatus] || {
    title: 'Status Update',
    message: `Your ticket status has been updated to: ${newStatus}`,
    icon: '📋'
  };
  
  return `
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>Ticket Status Update - ${ticketNumber}</title>
    </head>
    <body style="font-family: Arial, sans-serif; line-height: 1.6; color: #333; max-width: 600px; margin: 0 auto; padding: 20px;">
      <div style="background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); padding: 30px; text-align: center; border-radius: 10px 10px 0 0;">
        <h1 style="color: white; margin: 0; font-size: 28px;">${statusInfo.icon} ${statusInfo.title}</h1>
      </div>
      
      <div style="background: #f9f9f9; padding: 30px; border-radius: 0 0 10px 10px;">
        <p style="font-size: 16px; margin-bottom: 20px;">Hello ${clientName},</p>
        
        <p style="font-size: 16px; margin-bottom: 20px;">${statusInfo.message}</p>
        
        <div style="background: white; padding: 20px; border-radius: 8px; margin: 20px 0; border-left: 4px solid #667eea;">
          <p style="margin: 0; font-size: 14px; color: #666;">Ticket Number</p>
          <p style="margin: 5px 0 0 0; font-size: 20px; font-weight: bold; color: #667eea;">${ticketNumber}</p>
        </div>
        
        ${statusInfo.showRating ? `
        <div style="background: #fff3cd; padding: 20px; border-radius: 8px; margin: 20px 0; border-left: 4px solid #ffc107;">
          <p style="margin: 0 0 10px 0; font-weight: bold; color: #856404;">Rate Your Experience</p>
          <p style="margin: 0; font-size: 14px; color: #856404;">
            We'd love to hear your feedback! Please rate the service you received by visiting your ticket tracking page.
          </p>
        </div>
        ` : ''}
        
        <div style="text-align: center; margin: 30px 0;">
          <a href="${trackingLink}" style="display: inline-block; background: #667eea; color: white; padding: 15px 40px; text-decoration: none; border-radius: 5px; font-weight: bold; font-size: 16px;">
            View Ticket Details
          </a>
        </div>
        
        <p style="font-size: 14px; color: #666; margin-top: 30px;">
          If you have any questions, please reply to this email or visit your ticket tracking page.
        </p>
        
        <p style="font-size: 14px; color: #666; margin-top: 20px;">
          Best regards,<br>
          <strong>FieldCheck Support Team</strong>
        </p>
      </div>
      
      <div style="text-align: center; padding: 20px; font-size: 12px; color: #999;">
        <p>This is an automated notification from FieldCheck.</p>
        <p>Ticket: ${ticketNumber}</p>
      </div>
    </body>
    </html>
  `;
}

module.exports = ticketStatusUpdateEmail;
```

**Email Sending:**
```javascript
async function sendStatusUpdateEmail(ticket, newStatus) {
  const { token } = generateEmailToken(); // Reuse existing token or generate new one
  const trackingLink = `${process.env.FRONTEND_URL}/client-ticket/${ticket.ticketNumber}?token=${token}`;
  
  const emailHtml = ticketStatusUpdateEmail(
    ticket.clientName,
    ticket.ticketNumber,
    newStatus,
    trackingLink
  );
  
  await sendEmail({
    email: ticket.clientEmail,
    subject: `Ticket Update: ${ticket.ticketNumber} - Status Changed`,
    html: emailHtml
  });
}
```

### 3. API Integration Layer

**Module:** `backend/controllers/taskController.js` (modify existing)

**Integration Points:**

1. **Task Status Update Endpoint** (`updateTask`)
   ```javascript
   // After successful task.save()
   res.json({ success: true, data: task });
   
   // Trigger synchronization asynchronously (non-blocking)
   setImmediate(async () => {
     try {
       await syncTicketStatus(task._id);
     } catch (error) {
       // Log but don't propagate error
       console.error('Ticket synchronization failed', {
         taskId: task._id.toString(),
         error: error.message
       });
     }
   });
   ```

2. **UserTask Status Update Endpoint** (`updateUserTaskStatus`)
   ```javascript
   // After successful userTask.save() and syncAggregateTaskStatus()
   res.json({ success: true, data: userTask });
   
   // Trigger synchronization asynchronously (non-blocking)
   setImmediate(async () => {
     try {
       await syncTicketStatus(userTask.taskId);
     } catch (error) {
       // Log but don't propagate error
       console.error('Ticket synchronization failed', {
         userTaskId: userTask._id.toString(),
         taskId: userTask.taskId.toString(),
         error: error.message
       });
     }
   });
   ```

3. **Other Task Status Endpoints**
   - `acceptUserTask` - triggers sync after acceptance
   - `submitUserTaskForReview` - triggers sync after submission
   - `approveUserTask` - triggers sync after approval
   - `rejectUserTask` - triggers sync after rejection
   - `blockUserTask` - triggers sync after blocking
   - `unblockUserTask` - triggers sync after unblocking
   - `closeBlockedUserTask` - triggers sync after closing

**Integration Pattern (reusable):**
```javascript
// Add this helper function to taskController.js
function triggerTicketSync(taskId) {
  setImmediate(async () => {
    try {
      const { syncTicketStatus } = require('../services/ticketStatusSyncService');
      await syncTicketStatus(taskId);
    } catch (error) {
      console.error('Ticket synchronization failed', {
        taskId: taskId.toString(),
        error: error.message
      });
    }
  });
}

// Use in all task status update endpoints:
// After successful save and before/after sending response
triggerTicketSync(task._id);
```

## Data Models

### Task Model (existing)
```javascript
{
  _id: ObjectId,
  status: String, // 'pending', 'in_progress', 'completed', 'created', 'assigned', 
                  // 'accepted', 'blocked', 'reviewed', 'closed'
  // ... other fields
}
```

### ClientTicket Model (existing)
```javascript
{
  _id: ObjectId,
  ticketNumber: String, // 'RNG-YYYYMMDD-XXXX'
  clientEmail: String,
  clientName: String,
  status: String, // 'open', 'in_progress', 'pending_review', 'completed', 'closed', 'expired'
  linkedTaskId: ObjectId, // Reference to Task
  updatedAt: Date, // Automatically updated by Mongoose pre-save hook
  // ... other fields
}
```

### UserTask Model (existing)
```javascript
{
  _id: ObjectId,
  userId: ObjectId,
  taskId: ObjectId, // Reference to parent Task
  status: String, // 'pending', 'pending_acceptance', 'accepted', 'in_progress', 
                  // 'pending_review', 'blocked', 'completed', 'reviewed', 'closed'
  // ... other fields
}
```

## Status Mapping

### Direct 1:1 Mapping

| Task Status | Ticket Status | Triggers Email |
|-------------|---------------|----------------|
| in_progress | in_progress | Yes |
| pending_review | pending_review | Yes |
| completed | completed | Yes (with rating prompt) |
| closed | closed | Yes |

### Unmapped Task Statuses (No Synchronization)

The following task statuses do NOT trigger ticket status updates:
- `pending` - Initial state before assignment
- `created` - Task created but not assigned
- `assigned` - Task assigned but not accepted
- `accepted` - Employee accepted but hasn't started
- `blocked` - Temporary block (internal state)
- `reviewed` - Legacy status (deprecated)

**Rationale:** These statuses represent internal workflow states that are not relevant to clients. Clients only need to know when work starts (in_progress), is under review (pending_review), is completed (completed), or is closed (closed).

## Error Handling

### Principles

1. **Non-Blocking:** Synchronization errors never interrupt task updates
2. **Graceful Degradation:** Email failures don't prevent ticket status updates
3. **Comprehensive Logging:** All errors are logged with context for debugging
4. **Fail-Safe:** Missing data (task, ticket) is handled gracefully

### Error Scenarios

1. **Task Not Found**
   - Log debug message
   - Return without error
   - No ticket update

2. **Ticket Not Found**
   - Log debug message
   - Return without error
   - No ticket update

3. **No Linked Ticket**
   - Log debug message
   - Return without error
   - No ticket update

4. **Database Error on Ticket Save**
   - Log error with ticket number, task ID, attempted status, error message
   - Return without throwing
   - Task update succeeds, ticket update fails

5. **Email Send Failure**
   - Log error with ticket number, client email, error message
   - Don't throw error
   - Ticket update succeeds, email fails

6. **Terminal Status Protection**
   - Log debug message
   - Return without error
   - Ticket remains in terminal state

## Logging Strategy

### Log Levels

1. **Debug Level** (`console.debug` or `console.log` with debug prefix)
   - Task has no linked ticket
   - Task status not in mapping
   - Ticket in terminal status (skipped)
   - Synchronization function entry

2. **Info Level** (`console.log`)
   - Successful ticket status update (with old/new status)
   - Successful email send

3. **Error Level** (`console.error`)
   - Database errors during ticket update
   - Email send failures
   - Unexpected errors

### Log Format

**Success Log:**
```javascript
console.log('Ticket status synchronized', {
  ticketNumber: 'RNG-20250115-A1B2',
  taskId: '507f1f77bcf86cd799439011',
  oldStatus: 'open',
  newStatus: 'in_progress'
});
```

**Error Log:**
```javascript
console.error('Failed to update ticket status', {
  ticketNumber: 'RNG-20250115-A1B2',
  taskId: '507f1f77bcf86cd799439011',
  attemptedStatus: 'in_progress',
  error: 'Connection timeout'
});
```

**Email Error Log:**
```javascript
console.error('Failed to send status update email', {
  ticketNumber: 'RNG-20250115-A1B2',
  clientEmail: 'client@example.com',
  error: 'SMTP connection refused'
});
```

## Performance Considerations

### Asynchronous Execution

- Synchronization runs via `setImmediate()` after API response is sent
- API response time is not affected by synchronization
- Email sending is nested in another `setImmediate()` to avoid blocking ticket update

### Database Queries

- Single query to fetch task (with status and linkedTaskId only)
- Single query to fetch ticket (if linked)
- Single save operation for ticket update
- No N+1 query problems

### Email Delivery

- Email sending is non-blocking
- Uses existing email service with fallback providers (SMTP → Resend → Gmail API)
- Timeout protection (15 seconds for SMTP, 12 seconds for fallbacks)

## Security Considerations

### Email Token Security

- Reuse existing `generateEmailToken()` function for tracking links
- Tokens are hashed before storage in database
- Tokens are validated on ticket access

### Data Validation

- Status values validated against enum before update
- Terminal status protection prevents unauthorized status changes
- Mongoose validations and hooks are executed via `save()` method

### Error Information Disclosure

- Error messages in logs include internal IDs but not sensitive data
- Client-facing API responses don't expose synchronization errors
- Email failures are logged but not exposed to task update callers

## Testing Strategy

### Property-Based Tests

Property-based tests validate universal correctness properties across many generated inputs. Each property should be tested with at least 100 iterations.

### Unit Tests

Unit tests validate specific examples, edge cases, and error conditions. These complement property tests by covering specific scenarios.

### Integration Tests

Integration tests validate API endpoints, database interactions, and email service integration. These use mocks for external services.

## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a system—essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*

### Property 1: Status Mapping Correctness

*For any* task with a linked ticket, when the task status changes to a mapped status (in_progress, pending_review, completed, closed), the linked ticket status SHALL be updated to the corresponding mapped status.

**Validates: Requirements 1.1, 1.2, 1.3, 1.4, 4.1, 4.2, 4.3, 4.4**

### Property 2: Unmapped Status Preservation

*For any* task with a linked ticket, when the task status changes to an unmapped status (pending, created, assigned, accepted, blocked, reviewed), the linked ticket status SHALL remain unchanged.

**Validates: Requirements 4.5**

### Property 3: Timestamp Update

*For any* ticket status update performed by the synchronization service, the ticket's updatedAt field SHALL be set to a timestamp equal to or after the synchronization operation start time.

**Validates: Requirements 2.3, 9.3**

### Property 4: Data Preservation

*For any* ticket status update performed by the synchronization service, all ticket fields except status and updatedAt SHALL remain unchanged from their pre-synchronization values.

**Validates: Requirements 2.4, 5.3**

### Property 5: Email Failure Isolation

*For any* ticket status update where the email notification fails, the ticket status update SHALL still be persisted successfully to the database.

**Validates: Requirements 3.3**

### Property 6: Error Isolation

*For any* synchronization operation that encounters an error, the error SHALL NOT propagate to the calling task update operation.

**Validates: Requirements 3.4, 10.5**

### Property 7: Multi-Employee Task Authority

*For any* task with multiple UserTask assignments, the synchronization service SHALL use the parent Task status (not individual UserTask statuses) as the authoritative source for ticket status updates.

**Validates: Requirements 5.1, 5.2**

### Property 8: Email Recipient Correctness

*For any* status update email sent by the notification service, the recipient email address SHALL match the clientEmail field stored in the corresponding ticket record.

**Validates: Requirements 6.5**

### Property 9: Task Retrieval

*For any* valid task ID with a linked ticket, calling the synchronization function SHALL successfully retrieve both the task and the linked ticket from the database.

**Validates: Requirements 7.2**

### Property 10: Graceful No-Op

*For any* task ID that has no linked ticket, calling the synchronization function SHALL return successfully without throwing an error.

**Validates: Requirements 7.3**

### Property 11: Terminal Status Protection

*For any* ticket in a terminal status (closed or expired), synchronization operations SHALL NOT modify the ticket status regardless of the linked task status.

**Validates: Requirements 9.2**

## Implementation Notes

### Module Dependencies

```javascript
// ticketStatusSyncService.js dependencies
const Task = require('../models/Task');
const ClientTicket = require('../models/ClientTicket');
const { generateEmailToken } = require('../utils/emailTokenGenerator');
const sendEmail = require('../utils/emailService');
const ticketStatusUpdateEmail = require('../utils/templates/ticketStatusUpdateEmail');
```

### Configuration

No additional configuration required. The service uses:
- Existing database connection (Mongoose)
- Existing email service configuration
- Existing email token generation utilities
- Environment variables from `.env` (FRONTEND_URL for tracking links)

### Backwards Compatibility

- No changes to existing data models
- No changes to existing API contracts
- Additive changes only (new service module, new email template)
- Existing ticket status update logic remains unchanged

### Deployment Considerations

1. **Zero Downtime:** Service can be deployed without downtime
2. **Rollback Safe:** Can be disabled by removing integration calls
3. **Monitoring:** Use existing logging infrastructure
4. **Testing:** Can be tested in staging with real task updates

## Future Enhancements

### Potential Improvements (Out of Scope)

1. **Retry Mechanism:** Add retry logic for failed email sends
2. **Status History:** Track ticket status change history
3. **Notification Preferences:** Allow clients to opt out of email notifications
4. **Webhook Support:** Add webhook notifications for ticket status changes
5. **Rate Limiting:** Add rate limiting for email sends to prevent spam
6. **Batch Processing:** Batch multiple status updates for efficiency

### Extension Points

The design supports future extensions:
- Additional status mappings can be added to `STATUS_MAPPING`
- Custom email templates for different service types
- Additional notification channels (SMS, push notifications)
- Status change webhooks for third-party integrations
