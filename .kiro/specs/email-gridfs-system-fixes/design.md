# Email and GridFS System Fixes Design

## Overview

This design addresses critical reliability issues in the FieldCheck application's email delivery and GridFS file storage systems. The email system experiences failures when delivering password reset and account verification emails due to SMTP timeouts (common on Render hosting), improper initialization, and inadequate fallback mechanisms. The GridFS storage system has timing issues with MongoDB connection readiness, causing file uploads to succeed but files to be unretrievable.

**Fix Approach:**
- **Email System**: Implement robust initialization at server startup, improve timeout handling, ensure fallback providers trigger correctly, and enhance error logging
- **GridFS System**: Add MongoDB connection readiness checks, ensure proper bucket initialization timing, improve error handling for file operations, and validate file persistence after upload

**Impact:**
- Users can reliably reset passwords and receive account verification emails
- Files uploaded to GridFS are guaranteed to be retrievable
- System provides clear error messages when operations fail
- Administrators receive detailed logs for troubleshooting

## Glossary

- **Bug_Condition (C)**: The condition that triggers the bug - when email delivery fails due to timeout/initialization issues OR when GridFS file operations fail due to connection timing
- **Property (P)**: The desired behavior - emails delivered within 30 seconds via primary or fallback provider AND files uploaded to GridFS are immediately retrievable
- **Preservation**: Existing email functionality (templates, attachments, provider selection) and GridFS functionality (deduplication, soft delete, metadata, caching) that must remain unchanged
- **SMTP**: Simple Mail Transfer Protocol - primary email delivery method using Gmail SMTP server
- **Resend API**: Fallback email delivery service using HTTPS API
- **Gmail API**: Secondary fallback using OAuth2-authenticated Gmail API
- **GridFS**: MongoDB's specification for storing large files as chunks in the database
- **GridFSBucket**: MongoDB driver class for interacting with GridFS collections
- **storageService**: Backend service (`backend/services/storageService.js`) that abstracts GridFS operations
- **emailService**: Backend utility (`backend/utils/emailService.js`) that handles email delivery with multiple providers
- **mongoose.connection.readyState**: Integer indicating MongoDB connection status (0=disconnected, 1=connected, 2=connecting, 3=disconnecting)

## Bug Details

### Bug Condition

#### Email System Bug Condition

The email delivery bug manifests when the `sendEmail` function in `backend/utils/emailService.js` is called but fails to deliver the email due to SMTP timeout (common on Render hosting where SMTP ports may be blocked), improper service initialization, or fallback mechanisms not triggering correctly.

**Formal Specification:**
```
FUNCTION isEmailBugCondition(input)
  INPUT: input of type EmailRequest { email: string, subject: string, templateName: string, templateData: object }
  OUTPUT: boolean
  
  RETURN (
    // SMTP timeout occurs (ETIMEDOUT error after 30 seconds)
    input.smtpTimeout = true OR
    
    // Email service not initialized at server startup
    input.serviceNotInitialized = true OR
    
    // Fallback to Resend/Gmail API fails or doesn't trigger
    input.fallbackFailed = true OR
    
    // Provider credentials invalid or expired
    input.credentialsInvalid = true
  ) AND
  
  // Email delivery is required (not disabled)
  process.env.DISABLE_EMAIL != 'true' AND
  
  // Email is for critical user flow (password reset or account verification)
  (input.templateName = 'passwordReset' OR input.templateName = 'accountActivation')
END FUNCTION
```

#### GridFS File Persistence Bug Condition

The GridFS bug manifests when file upload operations in `backend/services/storageService.js` appear to succeed but files are not retrievable, or when MongoDB connection is not ready when GridFS bucket is accessed.

**Formal Specification:**
```
FUNCTION isGridFSBugCondition(input)
  INPUT: input of type FileOperation { operation: string, fileId: string, bucket: string, fileData: Buffer }
  OUTPUT: boolean
  
  RETURN (
    // MongoDB connection not ready when bucket accessed
    (mongoose.connection.readyState != 1 AND input.operation IN ['upload', 'download']) OR
    
    // File upload succeeds but file not retrievable
    (input.operation = 'upload' AND uploadSucceeded(input) AND NOT canRetrieveFile(input.fileId)) OR
    
    // Bucket initialization fails silently
    (input.bucketInitFailed = true) OR
    
    // File stream errors not handled properly
    (input.streamError = true AND NOT errorHandled(input))
  )
END FUNCTION
```

### Examples

#### Email System Examples

**Example 1: Password Reset Email Timeout on Render**
```javascript
// Input
const request = {
  email: 'user@example.com',
  subject: 'Reset your FieldCheck password',
  templateName: 'passwordReset',
  templateData: { 
    name: 'John Doe', 
    resetLink: 'https://fieldcheck-app.onrender.com/reset?token=abc123',
    resetToken: 'abc123'
  }
};

// Current Behavior (F)
await sendEmail(request);
// → SMTP connection times out after 30 seconds (ETIMEDOUT)
// → Fallback to Resend API doesn't trigger (code path not reached)
// → Error logged: "Email: sendMail failed"
// → User never receives password reset email
// → User cannot reset password

// Expected Behavior (F')
await sendEmail(request);
// → SMTP connection times out after 15 seconds
// → Fallback to Resend API triggers automatically
// → Email delivered via Resend within 18 seconds total
// → Logged: "Email: SMTP timed out; delivered via Resend fallback"
// → Returns { fallback: 'resend' }
// → User receives password reset email
```

**Example 2: Account Verification Email Not Sent (Service Not Initialized)**
```javascript
// Input
const newEmployee = {
  name: 'Jane Smith',
  email: 'jane.smith@company.com',
  password: 'SecurePass123!',
  role: 'employee',
  employeeId: 'EMP-0042'
};

// Current Behavior (F)
await registerUser(newEmployee);
// → User created successfully in database
// → sendEmail called with accountActivation template
// → Email service not properly initialized (transporter creation fails)
// → Error thrown but not properly handled
// → No email sent, no clear error message to admin
// → Employee cannot verify account

// Expected Behavior (F')
await registerUser(newEmployee);
// → User created successfully in database
// → sendEmail called with accountActivation template
// → Email service checks initialization status
// → If SMTP fails, automatically tries Resend API
// → Email delivered via available provider
// → Logged: "Email: delivered via Resend to jane.smith@company.com"
// → Employee receives verification link
```

#### GridFS File Persistence Examples

**Example 3: File Upload Success but Not Retrievable**
```javascript
// Input
const fileUpload = {
  resourceType: 'report',
  resourceId: '507f1f77bcf86cd799439011',
  fileName: 'inspection-photo.jpg',
  fileData: Buffer.from([0xFF, 0xD8, 0xFF, ...]), // 2MB JPEG
  fileType: 'image/jpeg',
  uploadedBy: '507f1f77bcf86cd799439012'
};

// Current Behavior (F)
const attachment = await saveAttachment(fileUpload);
// → Returns { _id: '...', url: '/api/attachments/abc123/file', fileName: 'inspection-photo.jpg' }
// → Upload appears successful
// → Later: GET /api/attachments/abc123/file
// → Returns 404 "File not found"
// → File not actually persisted in GridFS (stream finished before write completed)

// Expected Behavior (F')
const attachment = await saveAttachment(fileUpload);
// → Verifies mongoose.connection.readyState === 1
// → Creates GridFSBucket with bucketName 'ticketAttachments'
// → Uploads file to GridFS
// → Waits for uploadStream 'finish' event
// → Verifies file exists in GridFS before returning
// → Returns { _id: '...', url: '/api/attachments/abc123/file', fileName: 'inspection-photo.jpg' }
// → Later: GET /api/attachments/abc123/file
// → Successfully streams file with correct content-type
```

**Example 4: Database Not Ready Error**
```javascript
// Input
const avatarUpload = {
  userId: '507f1f77bcf86cd799439013',
  fileName: 'profile.png',
  fileBuffer: Buffer.from([0x89, 0x50, 0x4E, 0x47, ...]), // PNG file
  mimeType: 'image/png'
};

// Current Behavior (F)
await uploadAvatar(avatarUpload);
// → Calls getBucket() in storageService
// → mongoose.connection.db is undefined (connection not fully established)
// → Throws Error: "Database not ready"
// → Upload fails with unclear error message to user
// → User sees generic "Upload failed" message

// Expected Behavior (F')
await uploadAvatar(avatarUpload);
// → Calls getBucket() in storageService
// → Checks mongoose.connection.readyState === 1
// → If readyState !== 1, waits up to 5 seconds for connection
// → Once ready, creates GridFSBucket
// → Uploads file successfully
// → Returns avatar URL: '/api/users/avatar/507f1f77bcf86cd799439014'
// → User sees success message and avatar displays correctly
```

## Expected Behavior

### Preservation Requirements

#### Email System Preservation

**Unchanged Behaviors:**
- Email disabled mode (`DISABLE_EMAIL=true`) must continue to use JSON transport without actual delivery
- Email template rendering (accountActivation, passwordReset) must continue to use existing template functions with correct parameters
- Email attachments support must continue to work with the attachments array parameter
- Multiple email provider configuration must continue to respect the `EMAIL_PROVIDER` environment variable
- Email logging format and structure must remain consistent for existing monitoring tools

**Scope:**
All email operations that do NOT involve SMTP timeout or initialization failures should be completely unaffected by this fix. This includes:
- Emails sent when SMTP is working correctly
- Emails sent in disabled mode (JSON transport)
- Email template rendering logic
- Email attachment handling
- Provider selection based on `EMAIL_PROVIDER` env var

#### GridFS File Persistence Preservation

**Unchanged Behaviors:**
- File deduplication via checksum must continue to work (duplicate files return existing attachment record)
- Soft delete functionality must continue to mark `isDeleted=true` without removing files from GridFS
- Attachment metadata retrieval must continue to return all expected fields (fileName, fileSize, fileType, url, uploadedAt, uploadedBy)
- Files uploaded to different resource types (report, task, ticket) must continue to store in the same `ticketAttachments` bucket with resourceType metadata
- File download cache headers must continue to set `Cache-Control: public, max-age=31536000`
- File upload size limits (50MB) must continue to reject oversized uploads with clear error messages
- File type validation must continue to reject disallowed MIME types

**Scope:**
All file operations that do NOT involve MongoDB connection timing issues should be completely unaffected by this fix. This includes:
- File uploads when MongoDB connection is already established
- File downloads for existing files
- Attachment metadata queries
- Soft delete operations
- File deduplication logic

## Hypothesized Root Cause

### Email System Root Causes

Based on the bug description and code analysis, the most likely issues are:

1. **SMTP Port Blocking on Render**: Render hosting platform blocks or throttles SMTP connections on port 587, causing `ETIMEDOUT` errors after 30 seconds. The current code has fallback logic but it may not trigger correctly in all timeout scenarios.

2. **Email Service Initialization Timing**: The email service is not explicitly initialized at server startup. The `sendEmail` function creates a transporter on-demand, which can fail if credentials are invalid or if the first email is sent before the server is fully ready.

3. **Fallback Logic Gaps**: The fallback to Resend API and Gmail API exists but has conditions that may not cover all failure scenarios. For example, the fallback only triggers for `ETIMEDOUT` errors, not for other SMTP failures like authentication errors or connection refused.

4. **Insufficient Error Logging**: When email delivery fails, the error logs don't always include enough context (provider attempted, fallback status, credential validation results) for administrators to diagnose issues quickly.

5. **No Startup Verification**: The code has an optional `EMAIL_VERIFY=true` flag to verify SMTP connectivity at startup, but this is not enabled by default and doesn't test fallback providers.

### GridFS File Persistence Root Causes

Based on the bug description and code analysis, the most likely issues are:

1. **MongoDB Connection Timing**: The `getBucket()` function in `storageService.js` checks if `mongoose.connection.db` exists but doesn't verify the connection is fully ready (`readyState === 1`). If called during server startup before MongoDB connection is established, it throws "Database not ready" error.

2. **GridFS Bucket Initialization**: GridFS buckets are created on-demand when first accessed, not at server startup. If the first file upload happens before MongoDB connection is fully established, bucket creation fails.

3. **Upload Stream Completion**: The `uploadBuffer` function in `storageService.js` uses `uploadStream.end(buffer)` and listens for the 'finish' event, but there's no verification that the file is actually retrievable after the stream finishes. If the stream closes prematurely or the write doesn't complete, the function returns success but the file isn't in GridFS.

4. **Error Handling Gaps**: The `getFile` and `getFileStream` functions throw generic "File not found" errors without distinguishing between "file never uploaded" vs "file upload incomplete" vs "GridFS bucket not initialized".

5. **Multiple Bucket Support**: The code currently uses a single `BUCKET_NAME = 'ticketAttachments'` constant, but the system needs to support multiple buckets (`userAvatars`, `reportAttachments`) which may have different initialization timing.

## Correctness Properties

Property 1: Bug Condition - Email Delivery with Fallback

_For any_ email request where the bug condition holds (SMTP timeout, service not initialized, or credentials invalid), the fixed sendEmail function SHALL deliver the email within 30 seconds using the primary provider or automatically fallback to Resend API or Gmail API, and SHALL log the delivery status including provider used and fallback indicator.

**Validates: Requirements 2.1, 2.2, 2.3, 2.4, 2.5**

Property 2: Bug Condition - GridFS File Persistence

_For any_ file operation where the bug condition holds (MongoDB not ready, bucket initialization failed, or stream error), the fixed storageService SHALL verify MongoDB connection readiness before proceeding, wait up to 5 seconds for connection if needed, initialize GridFS buckets properly, and ensure uploaded files are immediately retrievable via their URLs.

**Validates: Requirements 2.6, 2.7, 2.8, 2.9, 2.10**

Property 3: Preservation - Email System Behavior

_For any_ email request where the bug condition does NOT hold (SMTP working correctly, service initialized, credentials valid), the fixed sendEmail function SHALL produce exactly the same behavior as the original function, preserving all existing functionality for email templates, attachments, provider selection, and disabled mode.

**Validates: Requirements 3.1, 3.2, 3.3, 3.4**

Property 4: Preservation - GridFS System Behavior

_For any_ file operation where the bug condition does NOT hold (MongoDB connected, bucket initialized, no stream errors), the fixed storageService SHALL produce exactly the same behavior as the original service, preserving all existing functionality for deduplication, soft delete, metadata retrieval, caching, and size limits.

**Validates: Requirements 3.5, 3.6, 3.7, 3.8, 3.9, 3.10**

## Fix Implementation

### Changes Required

Assuming our root cause analysis is correct:

#### Email System Changes

**File**: `backend/utils/emailService.js`

**Function**: `sendEmail`

**Specific Changes**:

1. **Add Email Service Initialization Function**: Create a new `initializeEmailService()` function that verifies email configuration at server startup
   - Check if SMTP credentials are configured
   - Optionally verify SMTP connectivity if `EMAIL_VERIFY=true`
   - Test Resend API key if configured
   - Test Gmail API credentials if configured
   - Log the available providers and their status
   - Export this function for use in `server.js`

2. **Improve Timeout Handling**: Reduce SMTP timeout from 30 seconds to 15 seconds to trigger fallback faster
   - Update `socketTimeout` in SMTP config from 30000ms to 15000ms
   - Ensure `withTimeout` wrapper uses consistent timeout values
   - Add timeout detection for all SMTP operations (connect, auth, send)

3. **Enhance Fallback Logic**: Ensure fallback triggers for all SMTP failure scenarios, not just timeouts
   - Catch authentication errors (invalid credentials) and trigger fallback
   - Catch connection refused errors (port blocked) and trigger fallback
   - Catch DNS resolution errors and trigger fallback
   - Log which provider was attempted and why fallback was triggered

4. **Improve Error Logging**: Add structured logging with all relevant context
   - Log provider attempted (smtp, resend, gmail_api)
   - Log error code, message, and response from provider
   - Log fallback status (triggered, succeeded, failed)
   - Log delivery time for performance monitoring
   - Include email recipient and subject (but not content) for traceability

5. **Add Startup Verification**: Call `initializeEmailService()` from `server.js` after database connection
   - Verify email configuration is valid
   - Log available providers and their status
   - Warn if no providers are configured in production
   - Set a flag indicating email service is ready

**File**: `backend/server.js`

**Function**: Server startup sequence (after `connectDB()`)

**Specific Changes**:

1. **Initialize Email Service at Startup**: Add call to `initializeEmailService()` after database connection is established
   - Import `initializeEmailService` from `emailService.js`
   - Call it in the `postDbInitDone` block after `connectDB()` succeeds
   - Log the initialization result
   - Continue server startup even if email initialization fails (non-blocking)

#### GridFS File Persistence Changes

**File**: `backend/services/storageService.js`

**Function**: `getBucket`

**Specific Changes**:

1. **Add MongoDB Connection Readiness Check**: Verify connection is fully established before creating GridFSBucket
   - Check `mongoose.connection.readyState === 1` (connected)
   - If not ready, wait up to 5 seconds for connection (with 100ms polling)
   - Throw clear error if connection not ready after timeout
   - Log connection status for debugging

2. **Support Multiple Buckets**: Refactor to support multiple GridFS buckets (ticketAttachments, userAvatars, reportAttachments)
   - Change `getBucket()` to `getBucket(bucketName = 'ticketAttachments')`
   - Cache bucket instances by name to avoid recreating
   - Initialize all buckets at server startup (after MongoDB connection)

3. **Add Bucket Initialization Function**: Create `initializeGridFSBuckets()` function for server startup
   - Verify MongoDB connection is ready
   - Create all required buckets (ticketAttachments, userAvatars, reportAttachments)
   - Log bucket initialization status
   - Export this function for use in `server.js`

**Function**: `uploadBuffer`

**Specific Changes**:

1. **Verify File Persistence After Upload**: Add verification that file is retrievable after upload stream finishes
   - After 'finish' event, query GridFS to verify file exists
   - Use `bucket.find({ _id: fileId }).limit(1).toArray()` to check
   - If file not found, throw error and retry upload once
   - Log upload success with file size and bucket name

2. **Improve Error Handling**: Add better error messages for upload failures
   - Catch stream errors and log with context (bucket, filename, size)
   - Distinguish between "connection lost" vs "disk full" vs "permission denied"
   - Return user-friendly error messages

**Function**: `getFile` and `getFileStream`

**Specific Changes**:

1. **Improve Error Messages**: Distinguish between different failure scenarios
   - "File not found in GridFS" (file never uploaded)
   - "GridFS bucket not initialized" (connection timing issue)
   - "MongoDB connection lost" (connection dropped during download)
   - Include fileId and bucket name in error messages for debugging

2. **Add Retry Logic**: Retry file retrieval once if it fails due to transient errors
   - Catch "connection lost" errors and retry after 1 second
   - Don't retry for "file not found" errors (permanent failure)
   - Log retry attempts

**File**: `backend/server.js`

**Function**: Server startup sequence (after `connectDB()`)

**Specific Changes**:

1. **Initialize GridFS Buckets at Startup**: Add call to `initializeGridFSBuckets()` after database connection is established
   - Import `initializeGridFSBuckets` from `storageService.js`
   - Call it in the `postDbInitDone` block after `connectDB()` succeeds
   - Log the initialization result
   - Continue server startup even if GridFS initialization fails (non-blocking)

## Testing Strategy

### Validation Approach

The testing strategy follows a two-phase approach: first, surface counterexamples that demonstrate the bugs on unfixed code, then verify the fixes work correctly and preserve existing behavior.

### Exploratory Bug Condition Checking

#### Email System Exploratory Testing

**Goal**: Surface counterexamples that demonstrate email delivery failures BEFORE implementing the fix. Confirm or refute the root cause analysis. If we refute, we will need to re-hypothesize.

**Test Plan**: Write tests that simulate SMTP timeouts, invalid credentials, and service initialization failures. Run these tests on the UNFIXED code to observe failures and understand the root cause.

**Test Cases**:
1. **SMTP Timeout Test**: Mock SMTP server that delays response for 35 seconds → should timeout and fail on unfixed code
2. **Invalid Credentials Test**: Configure invalid SMTP password → should fail authentication on unfixed code
3. **Service Not Initialized Test**: Call sendEmail before server startup completes → should fail with unclear error on unfixed code
4. **Fallback Not Triggered Test**: Simulate SMTP timeout without Resend API configured → should fail without attempting fallback on unfixed code

**Expected Counterexamples**:
- SMTP timeout after 30 seconds with no fallback attempt
- Authentication failure with no fallback to alternative provider
- "Database not ready" or "Transporter creation failed" errors
- Possible causes: timeout too long, fallback conditions too narrow, initialization not explicit

#### GridFS System Exploratory Testing

**Goal**: Surface counterexamples that demonstrate GridFS file persistence failures BEFORE implementing the fix. Confirm or refute the root cause analysis.

**Test Plan**: Write tests that simulate MongoDB connection timing issues, bucket initialization failures, and file upload/retrieval scenarios. Run these tests on the UNFIXED code to observe failures.

**Test Cases**:
1. **Connection Not Ready Test**: Call getBucket() before MongoDB connection established → should throw "Database not ready" on unfixed code
2. **File Upload Not Retrievable Test**: Upload file and immediately try to retrieve it → may return 404 on unfixed code
3. **Bucket Initialization Test**: Access multiple buckets (ticketAttachments, userAvatars) → may fail inconsistently on unfixed code
4. **Stream Error Test**: Simulate stream error during upload → should fail with unclear error on unfixed code

**Expected Counterexamples**:
- "Database not ready" error when accessing GridFS before connection established
- File upload returns success but file not retrievable (404 error)
- Inconsistent behavior across different buckets
- Possible causes: no readyState check, no post-upload verification, bucket initialization timing

### Fix Checking

#### Email System Fix Checking

**Goal**: Verify that for all inputs where the email bug condition holds, the fixed function delivers the email successfully using primary or fallback provider.

**Pseudocode:**
```
FOR ALL input WHERE isEmailBugCondition(input) DO
  result := sendEmail'(input)
  ASSERT (
    result.delivered = true AND
    result.deliveryTime < 30000 AND // milliseconds
    (result.provider IN ['smtp', 'resend', 'gmail_api']) AND
    result.logged = true AND
    (result.fallback = true IMPLIES result.fallbackProvider IN ['resend', 'gmail_api'])
  )
END FOR
```

**Test Cases**:
1. **SMTP Timeout with Resend Fallback**: Simulate SMTP timeout → should deliver via Resend within 18 seconds
2. **Invalid Credentials with Gmail API Fallback**: Configure invalid SMTP credentials → should deliver via Gmail API
3. **Service Initialization**: Call sendEmail after initializeEmailService() → should deliver successfully
4. **Error Logging**: Verify all delivery attempts are logged with provider, status, and timing

#### GridFS System Fix Checking

**Goal**: Verify that for all inputs where the GridFS bug condition holds, the fixed function uploads files successfully and ensures they are retrievable.

**Pseudocode:**
```
FOR ALL input WHERE isGridFSBugCondition(input) DO
  IF input.operation = 'upload' THEN
    result := uploadFile'(input)
    ASSERT (
      result.success = true AND
      result.fileId EXISTS AND
      result.url VALID AND
      canRetrieveFile(result.fileId) = true AND
      fileSize(result.fileId) = input.fileData.length
    )
  ELSE IF input.operation = 'download' THEN
    result := downloadFile'(input)
    ASSERT (
      result.success = true OR
      (result.success = false AND result.error IN ['File not found', 'GridFS bucket not initialized'])
    )
  END IF
END FOR
```

**Test Cases**:
1. **Connection Not Ready**: Call getBucket() before MongoDB ready → should wait and succeed
2. **File Upload and Retrieval**: Upload file and immediately retrieve it → should succeed
3. **Multiple Buckets**: Upload to ticketAttachments, userAvatars, reportAttachments → all should succeed
4. **Post-Upload Verification**: Upload file → should verify file exists in GridFS before returning

### Preservation Checking

#### Email System Preservation Checking

**Goal**: Verify that for all inputs where the email bug condition does NOT hold, the fixed function produces the same result as the original function.

**Pseudocode:**
```
FOR ALL input WHERE NOT isEmailBugCondition(input) DO
  ASSERT sendEmail(input) = sendEmail'(input)
END FOR
```

**Testing Approach**: Property-based testing is recommended for preservation checking because:
- It generates many test cases automatically across the input domain
- It catches edge cases that manual unit tests might miss
- It provides strong guarantees that behavior is unchanged for all non-buggy inputs

**Test Plan**: Observe behavior on UNFIXED code first for working email scenarios, then write property-based tests capturing that behavior.

**Test Cases**:
1. **Email Disabled Mode**: Set `DISABLE_EMAIL=true` → should use JSON transport (no actual delivery)
2. **Template Rendering**: Send email with accountActivation template → should render correctly
3. **Email Attachments**: Send email with attachments array → should include attachments
4. **Provider Selection**: Set `EMAIL_PROVIDER=gmail_api` → should use Gmail API directly (not as fallback)
5. **Working SMTP**: Send email when SMTP is working → should deliver via SMTP without fallback

#### GridFS System Preservation Checking

**Goal**: Verify that for all inputs where the GridFS bug condition does NOT hold, the fixed function produces the same result as the original function.

**Pseudocode:**
```
FOR ALL input WHERE NOT isGridFSBugCondition(input) DO
  ASSERT fileOperation(input) = fileOperation'(input)
END FOR
```

**Testing Approach**: Property-based testing is recommended for preservation checking because:
- It generates many file upload/download scenarios automatically
- It catches edge cases in file handling (size limits, MIME types, checksums)
- It provides strong guarantees that existing functionality is preserved

**Test Plan**: Observe behavior on UNFIXED code first for working file operations, then write property-based tests capturing that behavior.

**Test Cases**:
1. **File Deduplication**: Upload same file twice → should return existing attachment record
2. **Soft Delete**: Delete attachment → should mark `isDeleted=true` without removing file
3. **Metadata Retrieval**: Get attachment metadata → should return all expected fields
4. **Resource Type Storage**: Upload to report, task, ticket → should store in same bucket with metadata
5. **Cache Headers**: Download file → should set `Cache-Control: public, max-age=31536000`
6. **Size Limit**: Upload 51MB file → should reject with clear error message
7. **MIME Type Validation**: Upload .exe file → should reject with clear error message

### Unit Tests

#### Email System Unit Tests

- Test `initializeEmailService()` function with various configurations (SMTP only, Resend only, Gmail API only, all providers)
- Test SMTP timeout detection and fallback trigger
- Test authentication error detection and fallback trigger
- Test error logging format and content
- Test email delivery with each provider (SMTP, Resend, Gmail API)
- Test email disabled mode (JSON transport)

#### GridFS System Unit Tests

- Test `getBucket()` with MongoDB connection ready vs not ready
- Test `initializeGridFSBuckets()` function
- Test file upload with post-upload verification
- Test file retrieval with various error scenarios (not found, connection lost, bucket not initialized)
- Test multiple bucket support (ticketAttachments, userAvatars, reportAttachments)
- Test error message clarity for different failure scenarios

### Property-Based Tests

#### Email System Property-Based Tests

- Generate random email requests (various templates, recipients, subjects) and verify delivery succeeds
- Generate random SMTP failure scenarios (timeout, auth error, connection refused) and verify fallback triggers
- Generate random provider configurations and verify correct provider is used
- Test that all email operations preserve existing behavior when SMTP is working

#### GridFS System Property-Based Tests

- Generate random file uploads (various sizes, MIME types, resource types) and verify files are retrievable
- Generate random MongoDB connection states and verify getBucket() handles all states correctly
- Generate random file download requests and verify correct error messages for failures
- Test that all file operations preserve existing behavior when MongoDB is connected

### Integration Tests

#### Email System Integration Tests

- Test full password reset flow: request reset → email sent → user receives email → user clicks link → password reset succeeds
- Test full account verification flow: admin creates employee → email sent → employee receives email → employee clicks link → account verified
- Test email delivery with real SMTP server (Gmail) in staging environment
- Test email delivery with real Resend API in staging environment
- Test fallback behavior in production-like environment (Render with SMTP blocked)

#### GridFS System Integration Tests

- Test full file upload flow: user uploads file → file stored in GridFS → user downloads file → file content matches original
- Test file upload across all resource types (report, task, ticket) and verify retrieval
- Test profile picture upload and display in user interface
- Test attachment display in report/task/ticket detail views
- Test file persistence across server restarts (files remain accessible after restart)
