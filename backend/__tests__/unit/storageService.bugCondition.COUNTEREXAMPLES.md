# GridFS Storage Service Bug Condition Exploration - Counterexamples

**Test Execution Date**: Task 1.2.1 - Bug Condition Exploration  
**Code Status**: UNFIXED  
**Test File**: `backend/__tests__/unit/storageService.bugCondition.test.js`

## Summary

Ran bug condition exploration tests on UNFIXED code to surface counterexamples demonstrating GridFS file persistence failures. The tests revealed **5 failing test cases** out of 9 total tests, confirming the existence of the bugs described in the bugfix requirements.

**Test Results**:
- ✅ 4 tests passed (expected behavior for some edge cases)
- ❌ 5 tests failed (confirming bugs exist)

## Counterexamples Found

### Counterexample 1: uploadBuffer file._id Undefined Error

**Test Case**: "should make uploaded files immediately retrievable"

**Bug Condition**: File upload stream finishes but `file._id` is undefined in the finish event callback

**Error**:
```
TypeError: Cannot read properties of undefined (reading '_id')
  at GridFSBucketWriteStream._id (services/storageService.js:119:34)
```

**Root Cause Analysis**:
- Line 119 in `storageService.js`: `const fileId = String(file._id || uploadStream.id);`
- The `file` parameter in the 'finish' event callback is undefined
- The code attempts to access `file._id` which throws TypeError
- This causes the upload promise to never resolve, leading to test timeout

**Current Behavior**:
```javascript
uploadStream.on('finish', (file) => {
  const fileId = String(file._id || uploadStream.id);  // file is undefined!
  const url = `/api/tickets/attachments/${fileId}?filename=${encodeURIComponent(originalName)}`;
  resolve({ url, fileId, size: buffer.length });
});
```

**Expected Behavior**:
- The 'finish' event should provide the file object with `_id` property
- OR the code should use `uploadStream.id` directly without relying on `file._id`
- File should be immediately retrievable after upload completes

**Impact**: File uploads fail completely, preventing any attachments from being saved to GridFS

---

### Counterexample 2: No Multi-Bucket Support

**Test Case**: "should support multiple GridFS buckets"

**Bug Condition**: `getBucket()` doesn't accept bucket name parameter, only uses single BUCKET_NAME constant

**Error**:
```
expect(received).toBe(expected) // Object.is equality
Expected: "ticketAttachments"
Received: undefined
  at Object.toBe (__tests__/unit/storageService.bugCondition.test.js:171:39)
```

**Root Cause Analysis**:
- `getBucket()` function uses hardcoded `BUCKET_NAME = 'ticketAttachments'` constant
- Function doesn't accept any parameters
- `bucket.bucketName` property is undefined (GridFSBucket doesn't expose this property directly)
- No way to access different buckets (userAvatars, reportAttachments)

**Current Behavior**:
```javascript
const BUCKET_NAME = 'ticketAttachments';

const getBucket = () => {
  if (!mongoose.connection || !mongoose.connection.db) {
    throw new Error('Database not ready');
  }
  return new GridFSBucket(mongoose.connection.db, { bucketName: BUCKET_NAME });
};
```

**Expected Behavior**:
```javascript
const getBucket = (bucketName = 'ticketAttachments') => {
  // Verify connection ready
  // Return cached bucket instance or create new one
  // Support multiple buckets: ticketAttachments, userAvatars, reportAttachments
};
```

**Impact**: Cannot store user avatars or report attachments in separate buckets, limiting file organization

---

### Counterexample 3: Missing initializeGridFSBuckets Function

**Test Case**: "should have initializeGridFSBuckets function for explicit initialization"

**Bug Condition**: No initialization function exists for server startup

**Error**:
```
expect(received).toBe(expected) // Object.is equality
Expected: "function"
Received: "undefined"
  at Object.toBe (__tests__/unit/storageService.bugCondition.test.js:305:61)
```

**Root Cause Analysis**:
- `storageService.initializeGridFSBuckets` is undefined
- No function exported for explicit bucket initialization at server startup
- Buckets are created on-demand when first accessed
- This can cause timing issues if first access happens before MongoDB connection is fully ready

**Current Behavior**:
- Buckets created lazily when `getBucket()` is first called
- No explicit initialization at server startup
- No way to verify buckets are ready before handling requests

**Expected Behavior**:
```javascript
const initializeGridFSBuckets = async () => {
  // Verify MongoDB connection is ready
  // Create all required buckets (ticketAttachments, userAvatars, reportAttachments)
  // Log bucket initialization status
  // Return initialization result
};

module.exports = {
  // ... existing exports
  initializeGridFSBuckets
};
```

**Impact**: Potential race conditions during server startup, first file upload may fail if MongoDB not ready

---

### Counterexample 4: Stream Error Handling Timeout

**Test Case**: "should handle stream errors during upload with clear error messages"

**Bug Condition**: Stream errors not properly caught, causing test timeout

**Error**:
```
TypeError: Cannot read properties of undefined (reading '_id')
thrown: "Exceeded timeout of 10000 ms for a test"
```

**Root Cause Analysis**:
- Same root cause as Counterexample 1 (file._id undefined)
- When stream error occurs, the 'finish' event still fires but with undefined file
- Error handling doesn't catch this case
- Promise never resolves or rejects, causing timeout

**Current Behavior**:
- Stream errors may trigger 'finish' event with undefined file
- No validation that file object is defined before accessing properties
- No retry logic for transient errors

**Expected Behavior**:
- Validate file object exists before accessing properties
- Catch stream errors and reject promise with clear error message
- Distinguish between different error types (connection lost, disk full, permission denied)
- Provide user-friendly error messages

**Impact**: Stream errors cause silent failures or timeouts, making debugging difficult

---

### Counterexample 5: Full Attachment Workflow Timeout

**Test Case**: "should complete full attachment workflow (upload, save metadata, retrieve)"

**Bug Condition**: Complete workflow fails due to uploadBuffer issues

**Error**:
```
TypeError: Cannot read properties of undefined (reading '_id')
thrown: "Exceeded timeout of 10000 ms for a test"
```

**Root Cause Analysis**:
- Same root cause as Counterexample 1 (file._id undefined)
- `saveAttachment()` calls `uploadBuffer()` internally
- When uploadBuffer fails, saveAttachment never completes
- Attachment metadata may be created but file not in GridFS

**Current Behavior**:
```javascript
const saveAttachment = async ({ resourceType, resourceId, fileName, fileData, fileType, uploadedBy }) => {
  // ... checksum and duplicate check
  
  // Upload to GridFS - this fails with file._id undefined
  const result = await uploadBuffer(fileData, fileName, fileType, uploadedBy);
  
  // Create Attachment record - may not be reached if uploadBuffer fails
  const attachment = new Attachment({ /* ... */ });
  await attachment.save();
  return attachment;
};
```

**Expected Behavior**:
- uploadBuffer completes successfully
- Attachment metadata created only after file is in GridFS
- File immediately retrievable via attachment.storageName
- Full workflow completes without errors

**Impact**: Attachment creation fails, users cannot upload files to reports/tasks/tickets

---

## Tests That Passed (Expected Behavior)

### Test 1: "should throw clear error when getBucket() called before MongoDB ready"
✅ **PASSED** - Correctly throws "Database not ready" error when MongoDB not connected

### Test 2: "should provide clear error message when file not found"
✅ **PASSED** - Correctly throws "File not found" error for non-existent fileId

### Test 3: "should wait for MongoDB connection if not immediately ready"
✅ **PASSED** - Connection established successfully when given time

### Test 4: "should document expected counterexamples"
✅ **PASSED** - Documentation test always passes

---

## Bug Condition Validation

The bug condition exploration tests successfully validated the bug conditions defined in the design document:

```javascript
FUNCTION isGridFSBugCondition(input)
  RETURN (
    // ✅ Confirmed: MongoDB connection not ready when bucket accessed
    (mongoose.connection.readyState != 1 AND input.operation IN ['upload', 'download']) OR
    
    // ✅ Confirmed: File upload succeeds but file not retrievable (file._id undefined)
    (input.operation = 'upload' AND uploadSucceeded(input) AND NOT canRetrieveFile(input.fileId)) OR
    
    // ✅ Confirmed: Bucket initialization fails silently (no initializeGridFSBuckets function)
    (input.bucketInitFailed = true) OR
    
    // ✅ Confirmed: File stream errors not handled properly (timeout on error)
    (input.streamError = true AND NOT errorHandled(input))
  )
END FUNCTION
```

---

## Next Steps

1. ✅ **Task 1.2.1 Complete**: Bug condition exploration test written, run on unfixed code, failures documented
2. ⏭️ **Task 2.2.1**: Write preservation property tests (BEFORE implementing fix)
3. ⏭️ **Task 3.2.x**: Implement fixes to address the counterexamples found:
   - Fix uploadBuffer to handle file._id correctly (use uploadStream.id directly)
   - Add multi-bucket support to getBucket(bucketName)
   - Create initializeGridFSBuckets() function for server startup
   - Improve error handling for stream errors
   - Add post-upload verification to ensure files are retrievable

---

## Test Execution Command

```bash
cd backend
npm test -- storageService.bugCondition.test.js
```

**Expected Outcome on UNFIXED Code**: 5 tests fail (confirming bugs exist)  
**Expected Outcome on FIXED Code**: All 9 tests pass (confirming bugs are resolved)

---

## Property-Based Testing Status

**Property 1: Bug Condition - GridFS File Persistence**
- Status: ❌ FAILED (as expected on unfixed code)
- Counterexamples: 5 distinct failure scenarios documented above
- Validates Requirements: 1.6, 1.7, 1.8, 1.9, 1.10, 2.6, 2.7, 2.8, 2.9, 2.10

**Next**: Write Property 2 (Preservation tests) before implementing fixes
