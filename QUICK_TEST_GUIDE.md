# Quick Test Guide: Ticket Status Synchronization

## 🚀 Quick Start (5 Minutes)

### Step 1: Verify Implementation
```bash
cd "C:\Users\Mark_Karevin\Desktop\SCHOOL FILES\FieldCheck-App"
node backend/verify_sync_implementation.js
```

Expected: `✅ Result: 5/5 checks passed`

---

### Step 2: Start Backend Server
```bash
cd backend
npm start
```

Wait for: `Server running on port 5000` (or your configured port)

---

### Step 3: Find a Test Ticket

**Option A**: Use existing ticket with linked task
```javascript
// In MongoDB or your admin panel
db.clientTickets.findOne({ 
  linkedTaskId: { $ne: null },
  status: { $ne: 'closed' }
})
```

**Option B**: Create a new client ticket via your app
1. Go to client ticket submission form
2. Submit a new service request
3. Admin assigns it to an employee (creates linked task)

---

### Step 4: Test the Flow

#### Test 1: Employee Accepts Task
**API Call**:
```bash
POST /api/tasks/user-task/:userTaskId/accept
Authorization: Bearer <employee-token>
```

**Expected Result**:
- ✅ UserTask status → `accepted`
- ✅ Task status → `in_progress`
- ✅ Ticket status → `in_progress`
- ✅ Client receives email: "Your request is in progress"

**Check Logs**:
```
Starting ticket status synchronization { taskId: '...' }
Ticket status synchronized { ticketNumber: 'RNG-...', oldStatus: 'open', newStatus: 'in_progress' }
```

---

#### Test 2: Employee Submits for Review
**API Call**:
```bash
POST /api/tasks/user-task/:userTaskId/submit
Authorization: Bearer <employee-token>
Body: { "notes": "Work completed, ready for review" }
```

**Expected Result**:
- ✅ UserTask status → `pending_review`
- ✅ Task status → `pending_review`
- ✅ Ticket status → `pending_review`
- ✅ Client receives email: "Your request is under review"

---

#### Test 3: Admin Approves Task
**API Call**:
```bash
POST /api/tasks/user-task/:userTaskId/approve
Authorization: Bearer <admin-token>
Body: { "notes": "Great work!" }
```

**Expected Result**:
- ✅ UserTask status → `completed`
- ✅ Task status → `completed`
- ✅ Ticket status → `completed`
- ✅ Client receives email: "Your request is complete! Please rate our service"

---

### Step 5: Verify Results

#### Check Database
```javascript
// Find the ticket
db.clientTickets.findOne({ ticketNumber: 'RNG-...' })

// Verify:
// 1. status: 'completed'
// 2. updatedAt: <recent timestamp>
```

#### Check Email Logs
```bash
# In your terminal where backend is running
# Look for:
Status update email sent { 
  ticketNumber: 'RNG-...', 
  clientEmail: 'client@example.com', 
  newStatus: 'completed' 
}
```

#### Check Client Email
Open the client's email inbox and verify:
- ✅ Email received with correct status message
- ✅ Ticket number displayed correctly
- ✅ "View Ticket Details" button works
- ✅ Rating prompt visible (for completed status)

---

## 🎯 What to Look For

### ✅ Success Indicators
1. **Server Logs**: No errors in console
2. **Ticket Status**: Matches task status
3. **Email Sent**: Client receives notification
4. **Response Time**: API responds quickly (< 200ms)
5. **No Errors**: Task operations complete successfully

### ❌ Failure Indicators
1. **Server Errors**: Exception in logs
2. **Ticket Not Updated**: Status still "open"
3. **No Email**: Client doesn't receive notification
4. **Slow Response**: API takes > 1 second
5. **Task Fails**: UserTask/Task update throws error

---

## 🐛 Quick Troubleshooting

### Problem: Ticket Status Not Updating

**Quick Fix**:
```javascript
// 1. Check if ticket has linkedTaskId
db.clientTickets.findOne({ _id: ObjectId('...') })

// 2. Check if task status is mapped
// Only these trigger sync: in_progress, pending_review, completed, closed

// 3. Check server logs
// Look for: "Starting ticket status synchronization"
```

### Problem: Email Not Sent

**Quick Fix**:
```bash
# 1. Check .env file
cat backend/.env | grep SMTP

# 2. Verify SMTP settings are correct
# SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASS

# 3. Check logs for email errors
# Look for: "Failed to send status update email"
```

### Problem: Server Crashes

**This Should NOT Happen** - sync is fail-safe!

If it does:
```bash
# 1. Check syntax errors
node -c backend/services/ticketStatusSyncService.js
node -c backend/controllers/taskController.js

# 2. Check for missing dependencies
cd backend
npm install

# 3. Restart server
npm start
```

---

## 📊 Test Checklist

Use this checklist for thorough testing:

- [ ] Implementation verified (5/5 checks pass)
- [ ] Backend server starts without errors
- [ ] Found test ticket with linkedTaskId
- [ ] Employee accepts task → ticket status = "in_progress"
- [ ] Employee submits task → ticket status = "pending_review"
- [ ] Admin approves task → ticket status = "completed"
- [ ] Client receives all 3 emails
- [ ] Ticket updatedAt timestamp is recent
- [ ] Server logs show successful sync
- [ ] No errors in console
- [ ] API response time < 200ms
- [ ] Task operations work normally

---

## 🎉 Success!

If all tests pass, the implementation is working correctly!

### Next Steps:
1. **Deploy to Staging**: Test with real users
2. **Monitor Logs**: Watch for sync events and errors
3. **Collect Feedback**: Ask clients if emails are helpful
4. **Optimize**: Add property tests, retry logic, webhooks

---

## 📞 Need Help?

Check these resources:
- Full documentation: `TICKET_SYNC_IMPLEMENTATION.md`
- Requirements: `.kiro/specs/ticket-status-sync/requirements.md`
- Design: `.kiro/specs/ticket-status-sync/design.md`
- Tasks: `.kiro/specs/ticket-status-sync/tasks.md`

---

**Happy Testing! 🚀**

