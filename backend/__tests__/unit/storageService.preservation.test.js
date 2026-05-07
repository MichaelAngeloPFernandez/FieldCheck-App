/**
 * Preservation Property Tests for GridFS Storage Service
 * 
 * **CRITICAL**: These tests MUST PASS on unfixed code - they verify existing functionality
 * **GOAL**: Ensure fixes don't break existing GridFS system behavior
 * **METHODOLOGY**: Observation-first - observe behavior on UNFIXED code, then write tests
 * 
 * **Validates: Requirements 3.5, 3.6, 3.7, 3.8, 3.9, 3.10**
 * 
 * Property 2: Preservation - GridFS System Existing Functionality
 * 
 * For any file operation where the bug condition does NOT hold (MongoDB connected,
 * bucket initialized, no stream errors), the fixed storageService SHALL produce
 * exactly the same behavior as the original service, preserving all existing functionality
 * for deduplication, soft delete, metadata retrieval, caching, and size limits.
 */

const mongoose = require('mongoose');
const { MongoMemoryServer } = require('mongodb-memory-server');
const storageService = require('../../services/storageService');
const Attachment = require('../../models/Attachment');
const crypto = require('crypto');

describe('GridFS Storage Service - Preservation Property Tests', () => {
  let mongoServer;

  beforeAll(async () => {
    // Setup MongoDB connection for all tests
    mongoServer = await MongoMemoryServer.create();
    const mongoUri = mongoServer.getUri();
    await mongoose.connect(mongoUri);

    // Wait for connection to be ready
    await new Promise(resolve => {
      if (mongoose.connection.readyState === 1) {
        resolve();
      } else {
        mongoose.connection.once('connected', resolve);
      }
    });
  });

  afterAll(async () => {
    // Cleanup
    if (mongoose.connection.readyState !== 0) {
      await mongoose.connection.close();
    }
    if (mongoServer) {
      await mongoServer.stop();
    }
  });

  beforeEach(async () => {
    // Clear all collections before each test
    const collections = mongoose.connection.collections;
    for (const key in collections) {
      await collections[key].deleteMany({});
    }
    jest.clearAllMocks();
  });

  describe('Property 3.5: File Deduplication via Checksum', () => {
    /**
     * Preservation Test 1: Upload same file twice returns existing attachment
     * 
     * Observed Behavior on UNFIXED code:
     * - When file with same checksum is uploaded twice, returns existing attachment record
     * - No duplicate file stored in GridFS
     * - Checksum calculated using SHA256 hash of file content
     * 
     * This behavior MUST be preserved after implementing fixes.
     */
    it('should return existing attachment when uploading duplicate file (same checksum)', async () => {
      const testFileData = Buffer.from('Test file content for deduplication test');
      const uploadedBy = new mongoose.Types.ObjectId();
      const resourceId = new mongoose.Types.ObjectId();

      const attachmentData = {
        resourceType: 'report',
        resourceId: resourceId,
        fileName: 'test-file.txt',
        fileData: testFileData,
        fileType: 'text/plain',
        uploadedBy: uploadedBy
      };

      // First upload
      const firstAttachment = await storageService.saveAttachment(attachmentData);

      // Preservation Assertions for first upload:
      expect(firstAttachment).toBeDefined();
      expect(firstAttachment._id).toBeDefined();
      expect(firstAttachment.fileName).toBe('test-file.txt');
      expect(firstAttachment.checksum).toBeDefined();

      // Second upload with same file content (different filename)
      const duplicateData = {
        ...attachmentData,
        fileName: 'duplicate-file.txt', // Different filename
        resourceId: new mongoose.Types.ObjectId() // Different resource
      };

      const secondAttachment = await storageService.saveAttachment(duplicateData);

      // Preservation Assertions for deduplication:
      // 1. Returns existing attachment (same _id)
      expect(secondAttachment._id.toString()).toBe(firstAttachment._id.toString());
      
      // 2. Same checksum
      expect(secondAttachment.checksum).toBe(firstAttachment.checksum);
      
      // 3. Original filename preserved (not the duplicate's filename)
      expect(secondAttachment.fileName).toBe('test-file.txt');
      
      // 4. Only one attachment record in database
      const allAttachments = await Attachment.find({ checksum: firstAttachment.checksum });
      expect(allAttachments).toHaveLength(1);
    });

    /**
     * Preservation Test 2: Different file content creates new attachment
     * 
     * Observed Behavior: Files with different content have different checksums and create separate attachments
     */
    it('should create new attachment when file content is different', async () => {
      const uploadedBy = new mongoose.Types.ObjectId();
      const resourceId = new mongoose.Types.ObjectId();

      // First file
      const firstFileData = Buffer.from('First file content');
      const firstAttachment = await storageService.saveAttachment({
        resourceType: 'report',
        resourceId: resourceId,
        fileName: 'first-file.txt',
        fileData: firstFileData,
        fileType: 'text/plain',
        uploadedBy: uploadedBy
      });

      // Second file with different content
      const secondFileData = Buffer.from('Second file content - different');
      const secondAttachment = await storageService.saveAttachment({
        resourceType: 'report',
        resourceId: resourceId,
        fileName: 'second-file.txt',
        fileData: secondFileData,
        fileType: 'text/plain',
        uploadedBy: uploadedBy
      });

      // Preservation Assertions:
      // 1. Different attachment IDs
      expect(secondAttachment._id.toString()).not.toBe(firstAttachment._id.toString());
      
      // 2. Different checksums
      expect(secondAttachment.checksum).not.toBe(firstAttachment.checksum);
      
      // 3. Two separate attachment records
      const allAttachments = await Attachment.find({ resourceId: resourceId });
      expect(allAttachments).toHaveLength(2);
    });

    /**
     * Preservation Test 3: Checksum calculation uses SHA256
     * 
     * Observed Behavior: Checksum is SHA256 hash of file content
     */
    it('should calculate checksum using SHA256 hash of file content', async () => {
      const testFileData = Buffer.from('Test file for checksum verification');
      const expectedChecksum = crypto.createHash('sha256').update(testFileData).digest('hex');
      
      const uploadedBy = new mongoose.Types.ObjectId();
      const resourceId = new mongoose.Types.ObjectId();

      const attachment = await storageService.saveAttachment({
        resourceType: 'task',
        resourceId: resourceId,
        fileName: 'checksum-test.txt',
        fileData: testFileData,
        fileType: 'text/plain',
        uploadedBy: uploadedBy
      });

      // Preservation Assertions:
      expect(attachment.checksum).toBe(expectedChecksum);
    });
  });

  describe('Property 3.6: Soft Delete Functionality', () => {
    /**
     * Preservation Test 4: Delete attachment marks isDeleted=true without removing file
     * 
     * Observed Behavior on UNFIXED code:
     * - deleteAttachment() marks isDeleted=true
     * - Sets deletedAt timestamp
     * - Sets deletedBy user ID
     * - File remains in GridFS (not physically deleted)
     * 
     * This behavior MUST be preserved after implementing fixes.
     */
    it('should mark isDeleted=true without removing file from GridFS', async () => {
      const testFileData = Buffer.from('Test file for soft delete');
      const uploadedBy = new mongoose.Types.ObjectId();
      const deletedBy = new mongoose.Types.ObjectId();
      const resourceId = new mongoose.Types.ObjectId();

      // Upload file
      const attachment = await storageService.saveAttachment({
        resourceType: 'ticket',
        resourceId: resourceId,
        fileName: 'soft-delete-test.txt',
        fileData: testFileData,
        fileType: 'text/plain',
        uploadedBy: uploadedBy
      });

      const fileId = attachment.storageName;

      // Soft delete
      const deletedAttachment = await storageService.deleteAttachment(attachment._id, deletedBy);

      // Preservation Assertions:
      // 1. isDeleted flag set to true
      expect(deletedAttachment.isDeleted).toBe(true);
      
      // 2. deletedAt timestamp set
      expect(deletedAttachment.deletedAt).toBeDefined();
      expect(deletedAttachment.deletedAt).toBeInstanceOf(Date);
      
      // 3. deletedBy user ID set
      expect(deletedAttachment.deletedBy.toString()).toBe(deletedBy.toString());
      
      // 4. File still exists in GridFS (can be retrieved)
      const retrievedFile = await storageService.getFile(fileId);
      expect(retrievedFile).toBeDefined();
      expect(retrievedFile.toString()).toBe(testFileData.toString());
    });

    /**
     * Preservation Test 5: Soft deleted attachments excluded from resource queries
     * 
     * Observed Behavior: getAttachmentsForResource() excludes soft-deleted attachments
     */
    it('should exclude soft-deleted attachments from getAttachmentsForResource()', async () => {
      const uploadedBy = new mongoose.Types.ObjectId();
      const deletedBy = new mongoose.Types.ObjectId();
      const resourceId = new mongoose.Types.ObjectId();

      // Upload two files
      const attachment1 = await storageService.saveAttachment({
        resourceType: 'report',
        resourceId: resourceId,
        fileName: 'file1.txt',
        fileData: Buffer.from('File 1 content'),
        fileType: 'text/plain',
        uploadedBy: uploadedBy
      });

      const attachment2 = await storageService.saveAttachment({
        resourceType: 'report',
        resourceId: resourceId,
        fileName: 'file2.txt',
        fileData: Buffer.from('File 2 content'),
        fileType: 'text/plain',
        uploadedBy: uploadedBy
      });

      // Get attachments before delete
      const beforeDelete = await storageService.getAttachmentsForResource('report', resourceId);
      expect(beforeDelete).toHaveLength(2);

      // Soft delete one attachment
      await storageService.deleteAttachment(attachment1._id, deletedBy);

      // Get attachments after delete
      const afterDelete = await storageService.getAttachmentsForResource('report', resourceId);

      // Preservation Assertions:
      // 1. Only non-deleted attachment returned
      expect(afterDelete).toHaveLength(1);
      expect(afterDelete[0]._id.toString()).toBe(attachment2._id.toString());
      
      // 2. Deleted attachment not in results
      const deletedIds = afterDelete.map(a => a._id.toString());
      expect(deletedIds).not.toContain(attachment1._id.toString());
    });
  });

  describe('Property 3.7: Attachment Metadata Retrieval', () => {
    /**
     * Preservation Test 6: getAttachmentsForResource returns all expected fields
     * 
     * Observed Behavior on UNFIXED code:
     * - Returns fileName, fileSize, fileType, url, uploadedAt, uploadedBy
     * - Fields are selected explicitly (not all fields returned)
     * 
     * This behavior MUST be preserved after implementing fixes.
     */
    it('should return all expected metadata fields (fileName, fileSize, fileType, url, uploadedAt, uploadedBy)', async () => {
      const testFileData = Buffer.from('Test file for metadata retrieval');
      const uploadedBy = new mongoose.Types.ObjectId();
      const resourceId = new mongoose.Types.ObjectId();

      // Upload file
      await storageService.saveAttachment({
        resourceType: 'task',
        resourceId: resourceId,
        fileName: 'metadata-test.pdf',
        fileData: testFileData,
        fileType: 'application/pdf',
        uploadedBy: uploadedBy
      });

      // Get attachments
      const attachments = await storageService.getAttachmentsForResource('task', resourceId);

      // Preservation Assertions:
      expect(attachments).toHaveLength(1);
      
      const attachment = attachments[0];
      
      // 1. fileName field present
      expect(attachment.fileName).toBe('metadata-test.pdf');
      
      // 2. fileSize field present
      expect(attachment.fileSize).toBe(testFileData.length);
      
      // 3. fileType field present
      expect(attachment.fileType).toBe('application/pdf');
      
      // 4. url field present
      expect(attachment.url).toBeDefined();
      expect(typeof attachment.url).toBe('string');
      
      // 5. uploadedAt field present
      expect(attachment.uploadedAt).toBeDefined();
      expect(attachment.uploadedAt).toBeInstanceOf(Date);
      
      // 6. uploadedBy field present
      expect(attachment.uploadedBy).toBeDefined();
      expect(attachment.uploadedBy.toString()).toBe(uploadedBy.toString());
    });

    /**
     * Preservation Test 7: Attachment metadata includes correct file size
     * 
     * Observed Behavior: fileSize matches actual buffer length
     */
    it('should store correct file size in metadata', async () => {
      const testFileData = Buffer.from('A'.repeat(1024)); // 1KB file
      const uploadedBy = new mongoose.Types.ObjectId();
      const resourceId = new mongoose.Types.ObjectId();

      const attachment = await storageService.saveAttachment({
        resourceType: 'report',
        resourceId: resourceId,
        fileName: 'size-test.txt',
        fileData: testFileData,
        fileType: 'text/plain',
        uploadedBy: uploadedBy
      });

      // Preservation Assertions:
      expect(attachment.fileSize).toBe(1024);
      expect(attachment.fileSize).toBe(testFileData.length);
    });
  });

  describe('Property 3.8: Resource Type Storage', () => {
    /**
     * Preservation Test 8: Files uploaded to different resource types stored in same bucket
     * 
     * Observed Behavior on UNFIXED code:
     * - Files for report, task, ticket all stored in 'ticketAttachments' bucket
     * - resourceType metadata distinguishes them
     * - All use same GridFS bucket (BUCKET_NAME constant)
     * 
     * This behavior MUST be preserved after implementing fixes.
     */
    it('should store files from different resource types (report, task, ticket) in same bucket with metadata', async () => {
      const uploadedBy = new mongoose.Types.ObjectId();

      // Upload to report
      const reportAttachment = await storageService.saveAttachment({
        resourceType: 'report',
        resourceId: new mongoose.Types.ObjectId(),
        fileName: 'report-file.txt',
        fileData: Buffer.from('Report file content'),
        fileType: 'text/plain',
        uploadedBy: uploadedBy
      });

      // Upload to task
      const taskAttachment = await storageService.saveAttachment({
        resourceType: 'task',
        resourceId: new mongoose.Types.ObjectId(),
        fileName: 'task-file.txt',
        fileData: Buffer.from('Task file content'),
        fileType: 'text/plain',
        uploadedBy: uploadedBy
      });

      // Upload to ticket
      const ticketAttachment = await storageService.saveAttachment({
        resourceType: 'ticket',
        resourceId: new mongoose.Types.ObjectId(),
        fileName: 'ticket-file.txt',
        fileData: Buffer.from('Ticket file content'),
        fileType: 'text/plain',
        uploadedBy: uploadedBy
      });

      // Preservation Assertions:
      // 1. All attachments created successfully
      expect(reportAttachment).toBeDefined();
      expect(taskAttachment).toBeDefined();
      expect(ticketAttachment).toBeDefined();
      
      // 2. resourceType metadata preserved
      expect(reportAttachment.resourceType).toBe('report');
      expect(taskAttachment.resourceType).toBe('task');
      expect(ticketAttachment.resourceType).toBe('ticket');
      
      // 3. All files retrievable (stored in same bucket)
      const reportFile = await storageService.getFile(reportAttachment.storageName);
      const taskFile = await storageService.getFile(taskAttachment.storageName);
      const ticketFile = await storageService.getFile(ticketAttachment.storageName);
      
      expect(reportFile.toString()).toBe('Report file content');
      expect(taskFile.toString()).toBe('Task file content');
      expect(ticketFile.toString()).toBe('Ticket file content');
    });

    /**
     * Preservation Test 9: getAttachmentsForResource filters by resourceType and resourceId
     * 
     * Observed Behavior: Only returns attachments matching both resourceType and resourceId
     */
    it('should filter attachments by resourceType and resourceId', async () => {
      const uploadedBy = new mongoose.Types.ObjectId();
      const reportId1 = new mongoose.Types.ObjectId();
      const reportId2 = new mongoose.Types.ObjectId();
      const taskId1 = new mongoose.Types.ObjectId();

      // Upload to report 1
      await storageService.saveAttachment({
        resourceType: 'report',
        resourceId: reportId1,
        fileName: 'report1-file.txt',
        fileData: Buffer.from('Report 1 content'),
        fileType: 'text/plain',
        uploadedBy: uploadedBy
      });

      // Upload to report 2
      await storageService.saveAttachment({
        resourceType: 'report',
        resourceId: reportId2,
        fileName: 'report2-file.txt',
        fileData: Buffer.from('Report 2 content'),
        fileType: 'text/plain',
        uploadedBy: uploadedBy
      });

      // Upload to task 1
      await storageService.saveAttachment({
        resourceType: 'task',
        resourceId: taskId1,
        fileName: 'task1-file.txt',
        fileData: Buffer.from('Task 1 content'),
        fileType: 'text/plain',
        uploadedBy: uploadedBy
      });

      // Get attachments for report 1
      const report1Attachments = await storageService.getAttachmentsForResource('report', reportId1);
      
      // Preservation Assertions:
      // 1. Only report 1 attachments returned
      expect(report1Attachments).toHaveLength(1);
      expect(report1Attachments[0].fileName).toBe('report1-file.txt');
      
      // 2. Get attachments for report 2
      const report2Attachments = await storageService.getAttachmentsForResource('report', reportId2);
      expect(report2Attachments).toHaveLength(1);
      expect(report2Attachments[0].fileName).toBe('report2-file.txt');
      
      // 3. Get attachments for task 1
      const task1Attachments = await storageService.getAttachmentsForResource('task', taskId1);
      expect(task1Attachments).toHaveLength(1);
      expect(task1Attachments[0].fileName).toBe('task1-file.txt');
    });
  });

  describe('Property 3.9: Cache Headers on Download', () => {
    /**
     * Preservation Test 10: File downloads include Cache-Control header
     * 
     * Observed Behavior on UNFIXED code:
     * - getFileStream() returns stream and file metadata
     * - File metadata includes contentType
     * - Routes set Cache-Control: public, max-age=31536000 (1 year)
     * 
     * This behavior MUST be preserved after implementing fixes.
     * 
     * Note: This test verifies the service provides the necessary data for routes to set cache headers.
     * The actual Cache-Control header is set in the route handlers, not in storageService.
     */
    it('should provide file metadata for routes to set cache headers', async () => {
      const testFileData = Buffer.from('Test file for cache headers');
      const uploadedBy = new mongoose.Types.ObjectId();
      const resourceId = new mongoose.Types.ObjectId();

      // Upload file
      const attachment = await storageService.saveAttachment({
        resourceType: 'report',
        resourceId: resourceId,
        fileName: 'cache-test.jpg',
        fileData: testFileData,
        fileType: 'image/jpeg',
        uploadedBy: uploadedBy
      });

      // Get file stream
      const { stream, file } = await storageService.getFileStream(attachment.storageName);

      // Preservation Assertions:
      // 1. Stream is defined
      expect(stream).toBeDefined();
      
      // 2. File metadata is defined
      expect(file).toBeDefined();
      
      // 3. File metadata includes contentType (for Content-Type header)
      expect(file.contentType).toBeDefined();
      expect(file.contentType).toBe('image/jpeg');
      
      // 4. File metadata includes filename (for Content-Disposition header)
      expect(file.filename).toBeDefined();
      
      // Note: Cache-Control header is set in route handlers based on this metadata
      // The service provides the necessary data for routes to implement caching
    });
  });

  describe('Property 3.10: File Size and MIME Type Validation', () => {
    /**
     * Preservation Test 11: File upload size limit (50MB)
     * 
     * Observed Behavior on UNFIXED code:
     * - Files exceeding 50MB are rejected
     * - Clear error message returned
     * - Validation happens before GridFS upload
     * 
     * This behavior MUST be preserved after implementing fixes.
     * 
     * Note: Size limit validation is typically done in route handlers or middleware,
     * not in storageService itself. This test verifies the service can handle large files
     * if they pass validation.
     */
    it('should handle file size validation (service accepts files that pass route validation)', async () => {
      // Create a file just under 50MB limit
      const fileSizeBytes = 49 * 1024 * 1024; // 49MB
      const testFileData = Buffer.alloc(fileSizeBytes, 'A');
      
      const uploadedBy = new mongoose.Types.ObjectId();
      const resourceId = new mongoose.Types.ObjectId();

      // Upload large file (should succeed if under limit)
      const attachment = await storageService.saveAttachment({
        resourceType: 'report',
        resourceId: resourceId,
        fileName: 'large-file.bin',
        fileData: testFileData,
        fileType: 'application/octet-stream',
        uploadedBy: uploadedBy
      });

      // Preservation Assertions:
      // 1. Large file uploaded successfully
      expect(attachment).toBeDefined();
      expect(attachment.fileSize).toBe(fileSizeBytes);
      
      // 2. File is retrievable
      const retrievedFile = await storageService.getFile(attachment.storageName);
      expect(retrievedFile).toBeDefined();
      expect(retrievedFile.length).toBe(fileSizeBytes);
    }, 30000); // Longer timeout for large file

    /**
     * Preservation Test 12: MIME type validation
     * 
     * Observed Behavior: Service stores fileType as provided by route handlers
     * MIME type validation is done in route handlers/middleware, not in storageService
     * 
     * This test verifies the service correctly stores and retrieves fileType metadata.
     */
    it('should store and retrieve correct MIME type metadata', async () => {
      const uploadedBy = new mongoose.Types.ObjectId();
      const resourceId = new mongoose.Types.ObjectId();

      // Upload files with different MIME types
      const pdfAttachment = await storageService.saveAttachment({
        resourceType: 'report',
        resourceId: resourceId,
        fileName: 'document.pdf',
        fileData: Buffer.from('PDF content'),
        fileType: 'application/pdf',
        uploadedBy: uploadedBy
      });

      const imageAttachment = await storageService.saveAttachment({
        resourceType: 'report',
        resourceId: resourceId,
        fileName: 'photo.jpg',
        fileData: Buffer.from('JPEG content'),
        fileType: 'image/jpeg',
        uploadedBy: uploadedBy
      });

      const textAttachment = await storageService.saveAttachment({
        resourceType: 'report',
        resourceId: resourceId,
        fileName: 'notes.txt',
        fileData: Buffer.from('Text content'),
        fileType: 'text/plain',
        uploadedBy: uploadedBy
      });

      // Preservation Assertions:
      // 1. MIME types stored correctly
      expect(pdfAttachment.fileType).toBe('application/pdf');
      expect(imageAttachment.fileType).toBe('image/jpeg');
      expect(textAttachment.fileType).toBe('text/plain');
      
      // 2. MIME types retrievable via getAttachmentsForResource
      const attachments = await storageService.getAttachmentsForResource('report', resourceId);
      expect(attachments).toHaveLength(3);
      
      const mimeTypes = attachments.map(a => a.fileType);
      expect(mimeTypes).toContain('application/pdf');
      expect(mimeTypes).toContain('image/jpeg');
      expect(mimeTypes).toContain('text/plain');
    });
  });

  describe('Property 2: Preservation - Overall Behavior', () => {
    /**
     * Preservation Test 13: Provider field set to 'gridfs'
     * 
     * Observed Behavior: Attachments have provider='gridfs' to indicate storage backend
     */
    it('should set provider field to gridfs for all attachments', async () => {
      const uploadedBy = new mongoose.Types.ObjectId();
      const resourceId = new mongoose.Types.ObjectId();

      const attachment = await storageService.saveAttachment({
        resourceType: 'task',
        resourceId: resourceId,
        fileName: 'provider-test.txt',
        fileData: Buffer.from('Test content'),
        fileType: 'text/plain',
        uploadedBy: uploadedBy
      });

      // Preservation Assertions:
      expect(attachment.provider).toBe('gridfs');
    });

    /**
     * Preservation Test 14: URL format consistency
     * 
     * Observed Behavior: Attachment URLs follow consistent format
     */
    it('should generate consistent URL format for attachments', async () => {
      const uploadedBy = new mongoose.Types.ObjectId();
      const resourceId = new mongoose.Types.ObjectId();

      const attachment = await storageService.saveAttachment({
        resourceType: 'ticket',
        resourceId: resourceId,
        fileName: 'url-test.pdf',
        fileData: Buffer.from('Test content'),
        fileType: 'application/pdf',
        uploadedBy: uploadedBy
      });

      // Preservation Assertions:
      // 1. URL is defined
      expect(attachment.url).toBeDefined();
      expect(typeof attachment.url).toBe('string');
      
      // 2. URL contains storageName (fileId)
      expect(attachment.url).toContain(attachment.storageName);
      
      // 3. URL contains filename parameter
      expect(attachment.url).toContain('filename=');
      expect(attachment.url).toContain(encodeURIComponent('url-test.pdf'));
    });

    /**
     * Preservation Test 15: uploadedAt timestamp immutability
     * 
     * Observed Behavior: uploadedAt timestamp set on creation and never changes
     */
    it('should set uploadedAt timestamp on creation', async () => {
      const uploadedBy = new mongoose.Types.ObjectId();
      const resourceId = new mongoose.Types.ObjectId();

      const beforeUpload = new Date();
      
      const attachment = await storageService.saveAttachment({
        resourceType: 'report',
        resourceId: resourceId,
        fileName: 'timestamp-test.txt',
        fileData: Buffer.from('Test content'),
        fileType: 'text/plain',
        uploadedBy: uploadedBy
      });

      const afterUpload = new Date();

      // Preservation Assertions:
      // 1. uploadedAt is defined
      expect(attachment.uploadedAt).toBeDefined();
      expect(attachment.uploadedAt).toBeInstanceOf(Date);
      
      // 2. uploadedAt is between before and after timestamps
      expect(attachment.uploadedAt.getTime()).toBeGreaterThanOrEqual(beforeUpload.getTime());
      expect(attachment.uploadedAt.getTime()).toBeLessThanOrEqual(afterUpload.getTime());
    });
  });
});
