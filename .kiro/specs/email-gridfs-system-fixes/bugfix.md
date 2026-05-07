# Bugfix Requirements Document

## Introduction

This document addresses critical issues in the FieldCheck application's email delivery system and GridFS file persistence functionality. The email system is experiencing failures in delivering password reset and account verification emails, while the GridFS file storage system requires verification to ensure files persist correctly across profile pictures, report attachments, and task attachments.

**Impact:**
- Users cannot reset forgotten passwords, blocking account recovery
- Admin-created employee accounts may not receive verification emails, preventing account activation
- File uploads may fail silently or files may not be retrievable after upload
- Profile pictures and attachments may return 404 errors despite successful upload

**Affected Components:**
- Email Service (`backend/utils/emailService.js`)
- Password Reset Flow (`backend/controllers/userController.js`)
- Account Verification Flow (`backend/controllers/userController.js`)
- GridFS Storage Service (`backend/services/storageService.js`)
- Attachment Routes (`backend/routes/attachmentRoutes.js`)
- User Avatar Routes (`backend/routes/userRoutes.js`)
- Report Attachment Routes (`backend/routes/reportRoutes.js`)

---

## Bug Analysis

### Current Behavior (Defect)

#### Email System Issues

1.1 WHEN a user requests password reset via `/api/users/forgot-password` THEN the system may timeout or fail to deliver the email, leaving the user unable to reset their password

1.2 WHEN an admin creates a new employee account THEN the verification email may not be sent, preventing the employee from activating their account

1.3 WHEN the SMTP connection times out (common on Render hosting) THEN the fallback mechanisms (Resend API, Gmail API) may not trigger correctly, resulting in no email delivery

1.4 WHEN the email service is not properly initialized at server startup THEN subsequent email operations fail silently or with unclear error messages

1.5 WHEN the Gmail app password expires or is revoked THEN the system continues attempting SMTP authentication without clear failure indication to administrators

#### GridFS File Persistence Issues

1.6 WHEN a file is uploaded to GridFS via `/api/attachments/upload` THEN the system may return success but the file is not retrievable via its URL

1.7 WHEN the MongoDB connection is not fully established THEN GridFS bucket initialization fails with "Database not ready" error

1.8 WHEN a user uploads a profile picture via `/api/users/avatar` THEN the file may not persist in the `userAvatars` GridFS bucket

1.9 WHEN a user attempts to download a file via `/api/attachments/:storageName/file` THEN the system may return 404 or 500 errors despite the file existing in GridFS

1.10 WHEN multiple GridFS buckets are used (`ticketAttachments`, `userAvatars`, `reportAttachments`) THEN bucket initialization timing issues may cause inconsistent file access

### Expected Behavior (Correct)

#### Email System Fixes

2.1 WHEN a user requests password reset via `/api/users/forgot-password` THEN the system SHALL deliver the password reset email within 30 seconds using the primary provider or fallback to alternative providers

2.2 WHEN an admin creates a new employee account THEN the system SHALL send the account verification email immediately and log the delivery status

2.3 WHEN the SMTP connection times out THEN the system SHALL automatically attempt delivery via Resend API or Gmail API fallback and log the fallback provider used

2.4 WHEN the email service initializes at server startup THEN the system SHALL verify SMTP connectivity (if `EMAIL_VERIFY=true`) and log the configuration mode (SMTP/Resend/Gmail API/disabled)

2.5 WHEN email delivery fails for any reason THEN the system SHALL log detailed error information including provider, error code, and response, and SHALL return a user-friendly error message

#### GridFS File Persistence Fixes

2.6 WHEN a file is uploaded to GridFS via `/api/attachments/upload` THEN the system SHALL persist the file in the `ticketAttachments` bucket and return a valid URL that can retrieve the file

2.7 WHEN the GridFS bucket is accessed THEN the system SHALL verify MongoDB connection is ready and throw a clear error if not, preventing silent failures

2.8 WHEN a user uploads a profile picture via `/api/users/avatar` THEN the system SHALL persist the file in the `userAvatars` bucket and return a URL in the format `/api/users/avatar/:fileId`

2.9 WHEN a user downloads a file via `/api/attachments/:storageName/file` THEN the system SHALL stream the file from GridFS with correct content-type headers and return 404 with clear message if file not found

2.10 WHEN the server starts THEN the system SHALL initialize all GridFS buckets (`ticketAttachments`, `userAvatars`, `reportAttachments`) after MongoDB connection is established

### Unchanged Behavior (Regression Prevention)

#### Email System Preservation

3.1 WHEN email is disabled via `DISABLE_EMAIL=true` THEN the system SHALL CONTINUE TO use JSON transport mode without attempting actual delivery

3.2 WHEN email templates are rendered (accountActivation, passwordReset) THEN the system SHALL CONTINUE TO use the existing template functions with correct parameters

3.3 WHEN email attachments are included in mailOptions THEN the system SHALL CONTINUE TO support the attachments array parameter

3.4 WHEN multiple email providers are configured THEN the system SHALL CONTINUE TO respect the `EMAIL_PROVIDER` environment variable for provider selection

#### GridFS File Persistence Preservation

3.5 WHEN files are uploaded with duplicate checksums THEN the system SHALL CONTINUE TO deduplicate files and return the existing attachment record

3.6 WHEN attachments are soft-deleted via `/api/attachments/:attachmentId` THEN the system SHALL CONTINUE TO mark `isDeleted=true` without removing the file from GridFS

3.7 WHEN file metadata is retrieved via `/api/attachments/:attachmentId` THEN the system SHALL CONTINUE TO return fileName, fileSize, fileType, url, uploadedAt, and uploadedBy

3.8 WHEN files are uploaded to different resource types (report, task, ticket) THEN the system SHALL CONTINUE TO store them in the same `ticketAttachments` bucket with resourceType metadata

3.9 WHEN file downloads include cache headers THEN the system SHALL CONTINUE TO set `Cache-Control: public, max-age=31536000` for optimal performance

3.10 WHEN file uploads exceed size limits (50MB) THEN the system SHALL CONTINUE TO reject the upload with a clear error message

---

## Bug Condition Derivation

### Email Delivery Bug Condition

**Bug Condition Function:**
```pascal
FUNCTION isEmailBugCondition(X)
  INPUT: X of type EmailRequest { email: string, subject: string, templateName: string }
  OUTPUT: boolean
  
  // Email bug occurs when:
  // 1. SMTP times out (ETIMEDOUT error)
  // 2. Email service not initialized properly
  // 3. Fallback mechanisms don't trigger
  // 4. Provider credentials invalid/expired
  
  RETURN (
    X.smtpTimeout = true OR
    X.serviceNotInitialized = true OR
    X.fallbackFailed = true OR
    X.credentialsInvalid = true
  )
END FUNCTION
```

**Property Specification - Fix Checking:**
```pascal
// Property: Email Delivery Fix Checking
FOR ALL X WHERE isEmailBugCondition(X) DO
  result ← sendEmail'(X)
  ASSERT (
    result.delivered = true AND
    result.deliveryTime < 30000 AND // milliseconds
    (result.provider IN ['smtp', 'resend', 'gmail_api']) AND
    result.logged = true
  )
END FOR
```

**Property Specification - Preservation Checking:**
```pascal
// Property: Email System Preservation Checking
FOR ALL X WHERE NOT isEmailBugCondition(X) DO
  ASSERT sendEmail(X) = sendEmail'(X)
END FOR
```

### GridFS File Persistence Bug Condition

**Bug Condition Function:**
```pascal
FUNCTION isGridFSBugCondition(X)
  INPUT: X of type FileOperation { operation: string, fileId: string, bucket: string }
  OUTPUT: boolean
  
  // GridFS bug occurs when:
  // 1. MongoDB connection not ready when bucket accessed
  // 2. File upload succeeds but file not retrievable
  // 3. Bucket initialization fails
  // 4. File stream errors not handled properly
  
  RETURN (
    X.dbNotReady = true OR
    X.fileNotRetrievable = true OR
    X.bucketInitFailed = true OR
    X.streamError = true
  )
END FUNCTION
```

**Property Specification - Fix Checking:**
```pascal
// Property: GridFS File Persistence Fix Checking
FOR ALL X WHERE isGridFSBugCondition(X) DO
  IF X.operation = 'upload' THEN
    result ← uploadFile'(X)
    ASSERT (
      result.success = true AND
      result.fileId EXISTS AND
      result.url VALID AND
      canRetrieveFile(result.fileId) = true
    )
  ELSE IF X.operation = 'download' THEN
    result ← downloadFile'(X)
    ASSERT (
      result.success = true OR
      (result.success = false AND result.error = 'File not found')
    )
  END IF
END FOR
```

**Property Specification - Preservation Checking:**
```pascal
// Property: GridFS System Preservation Checking
FOR ALL X WHERE NOT isGridFSBugCondition(X) DO
  ASSERT fileOperation(X) = fileOperation'(X)
END FOR
```

---

## Counterexamples

### Email System Counterexamples

**Counterexample 1: Password Reset Email Timeout**
```javascript
// Input
const request = {
  email: 'user@example.com',
  subject: 'Reset your FieldCheck password',
  templateName: 'passwordReset',
  templateData: { name: 'John Doe', resetLink: 'https://app.com/reset?token=abc123' }
};

// Current Behavior (F)
sendEmail(request) 
// → throws Error: "sendMail timed out" after 30 seconds
// → User never receives email
// → Password reset fails

// Expected Behavior (F')
sendEmail'(request)
// → SMTP times out after 15 seconds
// → Automatically falls back to Resend API
// → Email delivered within 18 seconds total
// → Returns { provider: 'resend', fallback: true }
```

**Counterexample 2: Account Verification Email Not Sent**
```javascript
// Input
const newEmployee = {
  email: 'employee@company.com',
  name: 'Jane Smith',
  role: 'employee',
  verificationToken: 'xyz789'
};

// Current Behavior (F)
registerUser(newEmployee)
// → User created successfully
// → Email send fails silently (SMTP not initialized)
// → No error logged
// → Employee cannot verify account

// Expected Behavior (F')
registerUser'(newEmployee)
// → User created successfully
// → Email service checks initialization
// → Sends verification email via available provider
// → Logs: "Email: delivered via Resend to employee@company.com"
// → Employee receives verification link
```

### GridFS File Persistence Counterexamples

**Counterexample 3: File Upload Success but Not Retrievable**
```javascript
// Input
const fileUpload = {
  resourceType: 'report',
  resourceId: '507f1f77bcf86cd799439011',
  fileName: 'inspection-photo.jpg',
  fileData: Buffer.from([...]), // 2MB image
  fileType: 'image/jpeg',
  uploadedBy: '507f1f77bcf86cd799439012'
};

// Current Behavior (F)
saveAttachment(fileUpload)
// → Returns { _id: '...', url: '/api/attachments/abc123/file', ... }
// → File appears to upload successfully
// → Later: GET /api/attachments/abc123/file returns 404
// → File not actually persisted in GridFS

// Expected Behavior (F')
saveAttachment'(fileUpload)
// → Verifies MongoDB connection ready
// → Uploads to GridFS bucket 'ticketAttachments'
// → Waits for upload stream 'finish' event
// → Returns { _id: '...', url: '/api/attachments/abc123/file', ... }
// → GET /api/attachments/abc123/file successfully streams file
```

**Counterexample 4: Database Not Ready Error**
```javascript
// Input
const avatarUpload = {
  userId: '507f1f77bcf86cd799439013',
  fileName: 'profile.png',
  fileBuffer: Buffer.from([...]),
  mimeType: 'image/png'
};

// Current Behavior (F)
uploadAvatar(avatarUpload)
// → Calls getBucket()
// → MongoDB connection not fully established
// → Throws Error: "Database not ready"
// → Upload fails with unclear error to user

// Expected Behavior (F')
uploadAvatar'(avatarUpload)
// → Calls getBucket()
// → Checks mongoose.connection.readyState === 1
// → If not ready, waits up to 5 seconds for connection
// → Once ready, creates GridFSBucket
// → Upload succeeds
// → Returns avatar URL
```

---

## Testing Strategy

### Email System Testing

**Fix Checking Tests:**
1. Test password reset email delivery with SMTP timeout → should fallback to Resend/Gmail API
2. Test account verification email with invalid SMTP credentials → should fallback to alternative provider
3. Test email service initialization logging → should log provider configuration on startup
4. Test email delivery error logging → should log detailed error information

**Preservation Checking Tests:**
1. Test email with `DISABLE_EMAIL=true` → should use JSON transport (no actual delivery)
2. Test email template rendering → should use existing template functions
3. Test email with attachments → should support attachments array
4. Test multiple provider configuration → should respect `EMAIL_PROVIDER` env var

### GridFS File Persistence Testing

**Fix Checking Tests:**
1. Test file upload to GridFS → file should be retrievable immediately after upload
2. Test GridFS bucket initialization → should verify MongoDB connection ready
3. Test profile picture upload → should persist in `userAvatars` bucket
4. Test file download with invalid fileId → should return 404 with clear error message

**Preservation Checking Tests:**
1. Test duplicate file upload → should deduplicate via checksum
2. Test attachment soft delete → should mark `isDeleted=true` without removing file
3. Test attachment metadata retrieval → should return all expected fields
4. Test file upload to different resource types → should store in same bucket with metadata
5. Test file download cache headers → should set correct Cache-Control header
6. Test file upload size limit → should reject files exceeding 50MB

---

## Success Criteria

### Email System
- ✅ Password reset emails delivered within 30 seconds (primary or fallback provider)
- ✅ Account verification emails sent immediately upon employee creation
- ✅ SMTP timeouts trigger automatic fallback to Resend or Gmail API
- ✅ Email service logs configuration mode and delivery status
- ✅ Email failures logged with detailed error information

### GridFS File Persistence
- ✅ Files uploaded to GridFS are immediately retrievable via their URLs
- ✅ GridFS bucket initialization verifies MongoDB connection readiness
- ✅ Profile pictures persist correctly in `userAvatars` bucket
- ✅ File downloads return correct content-type and handle 404 gracefully
- ✅ All GridFS buckets initialize properly after MongoDB connection established

### Regression Prevention
- ✅ All existing email functionality preserved (templates, attachments, provider selection)
- ✅ All existing GridFS functionality preserved (deduplication, soft delete, metadata, caching)
