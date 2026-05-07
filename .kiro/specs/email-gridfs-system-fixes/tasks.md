# Implementation Plan

## Overview

This implementation plan follows the bug condition methodology for fixing critical email delivery and GridFS file persistence issues. The plan is structured in three phases:

1. **Bug Condition Exploration** - Write property-based tests that fail on unfixed code to understand the bugs
2. **Implementation** - Apply fixes to email service and GridFS storage service
3. **Verification** - Ensure fixes work and existing functionality is preserved

---

## Phase 1: Bug Condition Exploration

### 1.1 Email System Bug Condition Exploration

- [x] 1.1.1 Write bug condition exploration test for email delivery
  - **Property 1: Bug Condition** - Email Delivery Failures with SMTP Timeout and Fallback
  - **CRITICAL**: This test MUST FAIL on unfixed code - failure confirms the bug exists
  - **DO NOT attempt to fix the test or the code when it fails**
  - **NOTE**: This test encodes the expected behavior - it will validate the fix when it passes after implementation
  - **GOAL**: Surface counterexamples that demonstrate email delivery failures
  - **Scoped PBT Approach**: Scope the property to concrete failing cases (SMTP timeout, invalid credentials, service not initialized)
  - Test implementation details from Bug Condition in design:
    - Simulate SMTP timeout (ETIMEDOUT error after 30 seconds)
    - Simulate invalid SMTP credentials (authentication failure)
    - Simulate service not initialized (transporter creation fails)
    - Simulate fallback not triggering (Resend API not configured)
  - The test assertions should match the Expected Behavior Properties from design:
    - Email delivered within 30 seconds
    - Fallback to Resend API or Gmail API triggers automatically
    - Delivery status logged with provider and fallback indicator
  - Run test on UNFIXED code
  - **EXPECTED OUTCOME**: Test FAILS (this is correct - it proves the bug exists)
  - Document counterexamples found:
    - SMTP timeout after 30 seconds with no fallback attempt
    - Authentication failure with no fallback to alternative provider
    - "Transporter creation failed" errors
    - Fallback conditions too narrow (only triggers for ETIMEDOUT, not other errors)
  - Mark task complete when test is written, run, and failure is documented
  - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 2.1, 2.2, 2.3, 2.4, 2.5_

### 1.2 GridFS System Bug Condition Exploration

- [x] 1.2.1 Write bug condition exploration test for GridFS file persistence
  - **Property 1: Bug Condition** - GridFS File Upload and Retrieval Failures
  - **CRITICAL**: This test MUST FAIL on unfixed code - failure confirms the bug exists
  - **DO NOT attempt to fix the test or the code when it fails**
  - **NOTE**: This test encodes the expected behavior - it will validate the fix when it passes after implementation
  - **GOAL**: Surface counterexamples that demonstrate GridFS file persistence failures
  - **Scoped PBT Approach**: Scope the property to concrete failing cases (MongoDB not ready, file not retrievable, bucket init failed)
  - Test implementation details from Bug Condition in design:
    - Call getBucket() before MongoDB connection established (readyState !== 1)
    - Upload file and immediately try to retrieve it (may return 404)
    - Access multiple buckets (ticketAttachments, userAvatars) inconsistently
    - Simulate stream error during upload
  - The test assertions should match the Expected Behavior Properties from design:
    - Files uploaded to GridFS are immediately retrievable
    - getBucket() verifies MongoDB connection readiness
    - All buckets initialize properly after MongoDB connection
    - Upload stream completion verified before returning success
  - Run test on UNFIXED code
  - **EXPECTED OUTCOME**: Test FAILS (this is correct - it proves the bug exists)
  - Document counterexamples found:
    - "Database not ready" error when accessing GridFS before connection established
    - File upload returns success but file not retrievable (404 error)
    - Inconsistent behavior across different buckets
    - No readyState check, no post-upload verification
  - Mark task complete when test is written, run, and failure is documented
  - _Requirements: 1.6, 1.7, 1.8, 1.9, 1.10, 2.6, 2.7, 2.8, 2.9, 2.10_

---

## Phase 2: Preservation Property Tests (BEFORE implementing fix)

### 2.1 Email System Preservation Tests

- [x] 2.1.1 Write preservation property tests for email system (BEFORE implementing fix)
  - **Property 2: Preservation** - Email System Existing Functionality
  - **IMPORTANT**: Follow observation-first methodology
  - Observe behavior on UNFIXED code for non-buggy inputs:
    - Email with `DISABLE_EMAIL=true` uses JSON transport (no actual delivery)
    - Email with accountActivation template renders correctly
    - Email with attachments array includes attachments
    - Email with `EMAIL_PROVIDER=gmail_api` uses Gmail API directly (not as fallback)
    - Email when SMTP is working delivers via SMTP without fallback
  - Write property-based tests capturing observed behavior patterns from Preservation Requirements:
    - Test email disabled mode (DISABLE_EMAIL=true) → JSON transport
    - Test template rendering (accountActivation, passwordReset) → correct HTML output
    - Test email attachments → attachments included in mailOptions
    - Test provider selection (EMAIL_PROVIDER env var) → correct provider used
    - Test working SMTP → delivers via SMTP without fallback
  - Property-based testing generates many test cases for stronger guarantees
  - Run tests on UNFIXED code
  - **EXPECTED OUTCOME**: Tests PASS (this confirms baseline behavior to preserve)
  - Mark task complete when tests are written, run, and passing on unfixed code
  - _Requirements: 3.1, 3.2, 3.3, 3.4_

### 2.2 GridFS System Preservation Tests

- [x] 2.2.1 Write preservation property tests for GridFS system (BEFORE implementing fix)
  - **Property 2: Preservation** - GridFS System Existing Functionality
  - **IMPORTANT**: Follow observation-first methodology
  - Observe behavior on UNFIXED code for non-buggy inputs:
    - Upload same file twice → returns existing attachment record (deduplication)
    - Delete attachment → marks `isDeleted=true` without removing file
    - Get attachment metadata → returns all expected fields
    - Upload to report, task, ticket → stores in same bucket with metadata
    - Download file → sets `Cache-Control: public, max-age=31536000`
    - Upload 51MB file → rejects with clear error message
    - Upload .exe file → rejects with clear error message
  - Write property-based tests capturing observed behavior patterns from Preservation Requirements:
    - Test file deduplication via checksum
    - Test soft delete functionality
    - Test attachment metadata retrieval
    - Test resource type storage (report, task, ticket)
    - Test cache headers on download
    - Test file size limits (50MB)
    - Test MIME type validation
  - Property-based testing generates many test cases for stronger guarantees
  - Run tests on UNFIXED code
  - **EXPECTED OUTCOME**: Tests PASS (this confirms baseline behavior to preserve)
  - Mark task complete when tests are written, run, and passing on unfixed code
  - _Requirements: 3.5, 3.6, 3.7, 3.8, 3.9, 3.10_

---

## Phase 3: Implementation

### 3.1 Email Service Improvements

- [x] 3.1 Implement email service improvements

  - [x] 3.1.1 Add email service initialization function
    - Create `initializeEmailService()` function in `backend/utils/emailService.js`
    - Check if SMTP credentials are configured
    - Optionally verify SMTP connectivity if `EMAIL_VERIFY=true`
    - Test Resend API key if configured
    - Test Gmail API credentials if configured
    - Log available providers and their status
    - Export function for use in `server.js`
    - _Bug_Condition: isEmailBugCondition(input) where input.serviceNotInitialized = true_
    - _Expected_Behavior: Email service initialized at server startup with provider status logged_
    - _Preservation: Email disabled mode, template rendering, attachments, provider selection preserved_
    - _Requirements: 1.4, 2.4_

  - [x] 3.1.2 Improve timeout handling
    - Reduce SMTP timeout from 30 seconds to 15 seconds
    - Update `socketTimeout` in SMTP config from 30000ms to 15000ms
    - Ensure `withTimeout` wrapper uses consistent timeout values
    - Add timeout detection for all SMTP operations (connect, auth, send)
    - _Bug_Condition: isEmailBugCondition(input) where input.smtpTimeout = true_
    - _Expected_Behavior: SMTP timeout triggers fallback within 15 seconds_
    - _Preservation: Email delivery timing for working SMTP preserved_
    - _Requirements: 1.1, 1.3, 2.1, 2.3_

  - [x] 3.1.3 Enhance fallback logic
    - Ensure fallback triggers for all SMTP failure scenarios (not just timeouts)
    - Catch authentication errors (invalid credentials) and trigger fallback
    - Catch connection refused errors (port blocked) and trigger fallback
    - Catch DNS resolution errors and trigger fallback
    - Log which provider was attempted and why fallback was triggered
    - _Bug_Condition: isEmailBugCondition(input) where input.fallbackFailed = true OR input.credentialsInvalid = true_
    - _Expected_Behavior: Fallback to Resend/Gmail API triggers for all SMTP failures_
    - _Preservation: Fallback behavior for existing timeout scenarios preserved_
    - _Requirements: 1.3, 1.5, 2.3, 2.5_

  - [x] 3.1.4 Improve error logging
    - Add structured logging with all relevant context
    - Log provider attempted (smtp, resend, gmail_api)
    - Log error code, message, and response from provider
    - Log fallback status (triggered, succeeded, failed)
    - Log delivery time for performance monitoring
    - Include email recipient and subject (but not content) for traceability
    - _Bug_Condition: All email operations (buggy and non-buggy)_
    - _Expected_Behavior: Detailed error logs with provider, status, and timing_
    - _Preservation: Existing log format structure preserved_
    - _Requirements: 2.5_

  - [x] 3.1.5 Add startup verification in server.js
    - Import `initializeEmailService` from `emailService.js` in `backend/server.js`
    - Call it after database connection is established (in postDbInitDone block)
    - Log the initialization result
    - Continue server startup even if email initialization fails (non-blocking)
    - _Bug_Condition: isEmailBugCondition(input) where input.serviceNotInitialized = true_
    - _Expected_Behavior: Email service initialized at server startup_
    - _Preservation: Server startup sequence preserved_
    - _Requirements: 2.4_

  - [x] 3.1.6 Verify email system fixes work correctly
    - **Property 1: Expected Behavior** - Email Delivery with Fallback
    - **IMPORTANT**: Re-run the SAME test from task 1.1.1 - do NOT write a new test
    - The test from task 1.1.1 encodes the expected behavior
    - When this test passes, it confirms the expected behavior is satisfied
    - Run bug condition exploration test from step 1.1.1
    - **EXPECTED OUTCOME**: Test PASSES (confirms email delivery bug is fixed)
    - Verify:
      - SMTP timeout triggers fallback to Resend/Gmail API within 18 seconds
      - Invalid credentials trigger fallback to alternative provider
      - Email service initializes at server startup
      - Delivery status logged with provider and fallback indicator
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5_

  - [x] 3.1.7 Verify email system preservation tests still pass
    - **Property 2: Preservation** - Email System Existing Functionality
    - **IMPORTANT**: Re-run the SAME tests from task 2.1.1 - do NOT write new tests
    - Run preservation property tests from step 2.1.1
    - **EXPECTED OUTCOME**: Tests PASS (confirms no regressions)
    - Verify:
      - Email disabled mode still uses JSON transport
      - Template rendering still works correctly
      - Email attachments still supported
      - Provider selection still respects EMAIL_PROVIDER env var
      - Working SMTP still delivers without fallback
    - Confirm all tests still pass after fix (no regressions)

### 3.2 GridFS Storage Service Improvements

- [x] 3.2 Implement GridFS storage service improvements

  - [x] 3.2.1 Add MongoDB connection readiness check to getBucket
    - Modify `getBucket()` function in `backend/services/storageService.js`
    - Check `mongoose.connection.readyState === 1` (connected)
    - If not ready, wait up to 5 seconds for connection (with 100ms polling)
    - Throw clear error if connection not ready after timeout
    - Log connection status for debugging
    - _Bug_Condition: isGridFSBugCondition(input) where input.dbNotReady = true_
    - _Expected_Behavior: getBucket() verifies MongoDB connection readiness_
    - _Preservation: Bucket access when MongoDB is connected preserved_
    - _Requirements: 1.7, 2.7_

  - [x] 3.2.2 Support multiple GridFS buckets
    - Refactor `getBucket()` to `getBucket(bucketName = 'ticketAttachments')`
    - Cache bucket instances by name to avoid recreating
    - Support buckets: ticketAttachments, userAvatars, reportAttachments
    - _Bug_Condition: isGridFSBugCondition(input) where input.bucketInitFailed = true_
    - _Expected_Behavior: Multiple buckets supported with proper initialization_
    - _Preservation: Existing ticketAttachments bucket behavior preserved_
    - _Requirements: 1.10, 2.10_

  - [x] 3.2.3 Add bucket initialization function
    - Create `initializeGridFSBuckets()` function in `backend/services/storageService.js`
    - Verify MongoDB connection is ready
    - Create all required buckets (ticketAttachments, userAvatars, reportAttachments)
    - Log bucket initialization status
    - Export function for use in `server.js`
    - _Bug_Condition: isGridFSBugCondition(input) where input.bucketInitFailed = true_
    - _Expected_Behavior: All GridFS buckets initialized at server startup_
    - _Preservation: Bucket initialization timing preserved_
    - _Requirements: 2.10_

  - [x] 3.2.4 Verify file persistence after upload in uploadBuffer
    - Modify `uploadBuffer()` function in `backend/services/storageService.js`
    - After 'finish' event, query GridFS to verify file exists
    - Use `bucket.find({ _id: fileId }).limit(1).toArray()` to check
    - If file not found, throw error and retry upload once
    - Log upload success with file size and bucket name
    - _Bug_Condition: isGridFSBugCondition(input) where input.fileNotRetrievable = true_
    - _Expected_Behavior: Files uploaded to GridFS are immediately retrievable_
    - _Preservation: Upload behavior for successful uploads preserved_
    - _Requirements: 1.6, 2.6_

  - [x] 3.2.5 Improve error handling in uploadBuffer
    - Add better error messages for upload failures
    - Catch stream errors and log with context (bucket, filename, size)
    - Distinguish between "connection lost" vs "disk full" vs "permission denied"
    - Return user-friendly error messages
    - _Bug_Condition: isGridFSBugCondition(input) where input.streamError = true_
    - _Expected_Behavior: Clear error messages for different failure scenarios_
    - _Preservation: Error handling for existing scenarios preserved_
    - _Requirements: 2.9_

  - [x] 3.2.6 Improve error messages in getFile and getFileStream
    - Modify `getFile()` and `getFileStream()` functions
    - Distinguish between different failure scenarios:
      - "File not found in GridFS" (file never uploaded)
      - "GridFS bucket not initialized" (connection timing issue)
      - "MongoDB connection lost" (connection dropped during download)
    - Include fileId and bucket name in error messages for debugging
    - _Bug_Condition: isGridFSBugCondition(input) where input.operation = 'download'_
    - _Expected_Behavior: Clear error messages for download failures_
    - _Preservation: Download behavior for existing files preserved_
    - _Requirements: 1.9, 2.9_

  - [x] 3.2.7 Add retry logic to getFile and getFileStream
    - Add retry logic for transient errors
    - Catch "connection lost" errors and retry after 1 second
    - Don't retry for "file not found" errors (permanent failure)
    - Log retry attempts
    - _Bug_Condition: isGridFSBugCondition(input) where input.streamError = true_
    - _Expected_Behavior: Transient errors retried automatically_
    - _Preservation: Download behavior for successful downloads preserved_
    - _Requirements: 2.9_

  - [x] 3.2.8 Add startup initialization in server.js
    - Import `initializeGridFSBuckets` from `storageService.js` in `backend/server.js`
    - Call it after database connection is established (in postDbInitDone block)
    - Log the initialization result
    - Continue server startup even if GridFS initialization fails (non-blocking)
    - _Bug_Condition: isGridFSBugCondition(input) where input.bucketInitFailed = true_
    - _Expected_Behavior: GridFS buckets initialized at server startup_
    - _Preservation: Server startup sequence preserved_
    - _Requirements: 2.10_

  - [x] 3.2.9 Verify GridFS system fixes work correctly
    - **Property 1: Expected Behavior** - GridFS File Persistence
    - **IMPORTANT**: Re-run the SAME test from task 1.2.1 - do NOT write a new test
    - The test from task 1.2.1 encodes the expected behavior
    - When this test passes, it confirms the expected behavior is satisfied
    - Run bug condition exploration test from step 1.2.1
    - **EXPECTED OUTCOME**: Test PASSES (confirms GridFS persistence bug is fixed)
    - Verify:
      - getBucket() verifies MongoDB connection readiness
      - Files uploaded to GridFS are immediately retrievable
      - Multiple buckets initialize properly
      - Upload stream completion verified before returning success
    - _Requirements: 2.6, 2.7, 2.8, 2.9, 2.10_

  - [x] 3.2.10 Verify GridFS system preservation tests still pass
    - **Property 2: Preservation** - GridFS System Existing Functionality
    - **IMPORTANT**: Re-run the SAME tests from task 2.2.1 - do NOT write new tests
    - Run preservation property tests from step 2.2.1
    - **EXPECTED OUTCOME**: Tests PASS (confirms no regressions)
    - Verify:
      - File deduplication still works via checksum
      - Soft delete still marks isDeleted=true without removing file
      - Attachment metadata retrieval still returns all expected fields
      - Resource type storage still works correctly
      - Cache headers still set correctly on download
      - File size limits still enforced (50MB)
      - MIME type validation still works
    - Confirm all tests still pass after fix (no regressions)

---

## Phase 4: Final Verification

- [x] 4. Checkpoint - Ensure all tests pass
  - Run all bug condition exploration tests (should now PASS)
  - Run all preservation property tests (should still PASS)
  - Run unit tests for email service and GridFS storage service
  - Run integration tests for full email and file upload flows
  - Verify no regressions in existing functionality
  - Ask the user if questions arise

---

## Testing Notes

### Property-Based Testing Approach

This implementation uses property-based testing (PBT) for both bug condition exploration and preservation checking:

**Bug Condition Exploration (Property 1)**:
- Scoped PBT generates test cases for specific failing scenarios (SMTP timeout, MongoDB not ready)
- Tests run on UNFIXED code and are expected to FAIL
- Failures surface counterexamples that demonstrate the bugs
- After fix, same tests should PASS, confirming bugs are resolved

**Preservation Checking (Property 2)**:
- PBT generates many test cases across the input domain for non-buggy scenarios
- Tests run on UNFIXED code and are expected to PASS
- Tests capture baseline behavior that must be preserved
- After fix, same tests should still PASS, confirming no regressions

### Test Execution Order

1. **Phase 1**: Write and run bug condition exploration tests on UNFIXED code → expect FAILURES
2. **Phase 2**: Write and run preservation tests on UNFIXED code → expect PASSES
3. **Phase 3**: Implement fixes
4. **Phase 3 Verification**: Re-run bug condition tests → expect PASSES (bugs fixed)
5. **Phase 3 Verification**: Re-run preservation tests → expect PASSES (no regressions)
6. **Phase 4**: Run all tests together → all should PASS

### Test Files

Create test files in `backend/tests/`:
- `backend/tests/emailService.bugCondition.test.js` - Bug condition exploration for email system
- `backend/tests/emailService.preservation.test.js` - Preservation tests for email system
- `backend/tests/storageService.bugCondition.test.js` - Bug condition exploration for GridFS system
- `backend/tests/storageService.preservation.test.js` - Preservation tests for GridFS system

### Running Tests

```bash
# Run all tests
npm test

# Run specific test file
npm test -- emailService.bugCondition.test.js

# Run with coverage
npm test -- --coverage
```

---

## Success Criteria

### Email System
- ✅ Password reset emails delivered within 30 seconds (primary or fallback provider)
- ✅ Account verification emails sent immediately upon employee creation
- ✅ SMTP timeouts trigger automatic fallback to Resend or Gmail API
- ✅ Email service logs configuration mode and delivery status
- ✅ Email failures logged with detailed error information
- ✅ All existing email functionality preserved (templates, attachments, provider selection)

### GridFS File Persistence
- ✅ Files uploaded to GridFS are immediately retrievable via their URLs
- ✅ GridFS bucket initialization verifies MongoDB connection readiness
- ✅ Profile pictures persist correctly in `userAvatars` bucket
- ✅ File downloads return correct content-type and handle 404 gracefully
- ✅ All GridFS buckets initialize properly after MongoDB connection established
- ✅ All existing GridFS functionality preserved (deduplication, soft delete, metadata, caching)

### Regression Prevention
- ✅ All preservation property tests pass after implementation
- ✅ No changes to existing email or file handling behavior for non-buggy scenarios
- ✅ Server startup sequence unchanged (email and GridFS initialization non-blocking)
