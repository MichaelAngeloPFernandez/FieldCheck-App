/**
 * Storage Service — abstraction over GridFS for ticket/report/task attachments.
 * Currently uses MongoDB GridFS (durable with Atlas).
 */
const mongoose = require('mongoose');
const { GridFSBucket, ObjectId } = require('mongodb');
const crypto = require('crypto');
const Attachment = require('../models/Attachment');

// Cache bucket instances to avoid recreating them
const bucketCache = new Map();

/**
 * Get (or create) the GridFS bucket with connection readiness check.
 * Supports multiple buckets: ticketAttachments, userAvatars, reportAttachments
 * 
 * @param {string} bucketName - Name of the GridFS bucket (default: 'ticketAttachments')
 * @returns {GridFSBucket} GridFS bucket instance
 * @throws {Error} If MongoDB connection is not ready after timeout
 */
const getBucket = async (bucketName = 'ticketAttachments') => {
  // Check if MongoDB connection exists
  if (!mongoose.connection || !mongoose.connection.db) {
    console.error(`GridFS: MongoDB connection not available (readyState: ${mongoose.connection?.readyState || 'undefined'})`);
    throw new Error('Database not ready');
  }

  // Check if connection is fully established (readyState === 1)
  if (mongoose.connection.readyState !== 1) {
    console.warn(`GridFS: MongoDB connection not ready (readyState: ${mongoose.connection.readyState}), waiting up to 5 seconds...`);
    
    // Wait up to 5 seconds for connection to be ready
    const maxWaitMs = 5000;
    const pollIntervalMs = 100;
    const startTime = Date.now();

    while (mongoose.connection.readyState !== 1) {
      if (Date.now() - startTime > maxWaitMs) {
        console.error(`GridFS: MongoDB connection timeout after 5 seconds (final readyState: ${mongoose.connection.readyState})`);
        throw new Error('Database not ready: Connection timeout after 5 seconds');
      }
      await new Promise(resolve => setTimeout(resolve, pollIntervalMs));
    }
    
    const waitTime = Date.now() - startTime;
    console.log(`GridFS: MongoDB connection ready after ${waitTime}ms wait`);
  }

  // Return cached bucket if exists
  if (bucketCache.has(bucketName)) {
    console.log(`GridFS: Using cached bucket '${bucketName}' (readyState: ${mongoose.connection.readyState})`);
    return bucketCache.get(bucketName);
  }

  // Create new bucket and cache it
  const bucket = new GridFSBucket(mongoose.connection.db, { bucketName });
  bucketCache.set(bucketName, bucket);
  console.log(`GridFS: Created and cached new bucket '${bucketName}' (readyState: ${mongoose.connection.readyState})`);
  
  return bucket;
};

/**
 * Initialize all GridFS buckets at server startup.
 * This ensures buckets are ready before handling requests.
 * 
 * @returns {Promise<Object>} Initialization result with status for each bucket
 */
const initializeGridFSBuckets = async () => {
  const buckets = ['ticketAttachments', 'userAvatars', 'reportAttachments'];
  const results = {};

  try {
    // Verify MongoDB connection is ready
    if (!mongoose.connection || mongoose.connection.readyState !== 1) {
      throw new Error('MongoDB connection not ready for GridFS initialization');
    }

    // Initialize each bucket
    for (const bucketName of buckets) {
      try {
        await getBucket(bucketName);
        results[bucketName] = 'initialized';
        console.log(`GridFS: Bucket '${bucketName}' initialized successfully`);
      } catch (error) {
        results[bucketName] = `failed: ${error.message}`;
        console.error(`GridFS: Failed to initialize bucket '${bucketName}':`, error.message);
      }
    }

    console.log('GridFS: All buckets initialization complete');
    return { success: true, buckets: results };
  } catch (error) {
    console.error('GridFS: Bucket initialization failed:', error.message);
    return { success: false, error: error.message, buckets: results };
  }
};

/**
 * Legacy Interface for attachmentRoutes.js
 * Saves attachment metadata to Attachment collection and file to GridFS.
 */
const saveAttachment = async ({
  resourceType,
  resourceId,
  fileName,
  fileData,
  fileType,
  uploadedBy,
}) => {
  try {
    // 1. Calculate checksum
    const checksum = crypto.createHash('sha256').update(fileData).digest('hex');

    // 2. Check for duplicate
    const existing = await Attachment.findOne({ checksum, isDeleted: false });
    if (existing) return existing;

    // 3. Upload to GridFS
    const result = await uploadBuffer(fileData, fileName, fileType, uploadedBy);

    // 4. Create Attachment record
    const attachment = new Attachment({
      resourceType,
      resourceId,
      fileName,
      fileSize: fileData.length,
      fileType,
      url: result.url,
      storageName: result.fileId, // Use GridFS ID as storageName reference
      provider: 'gridfs',
      checksum,
      uploadedBy,
      uploadedAt: new Date(),
    });

    await attachment.save();
    return attachment;
  } catch (error) {
    console.error('storageService.saveAttachment error:', error);
    throw error;
  }
};

/**
 * Legacy Interface: Get file content by storageName (which we mapped to GridFS ID).
 * Includes retry logic for transient errors.
 * 
 * @param {string} storageName - GridFS file ID (storageName in Attachment model)
 * @param {string} bucketName - GridFS bucket name (default: 'ticketAttachments')
 * @returns {Promise<Buffer>} File content as buffer
 */
const getFile = async (storageName, bucketName = 'ticketAttachments') => {
  try {
    const { stream } = await getFileStream(storageName, bucketName);
    const chunks = [];
    return new Promise((resolve, reject) => {
      stream.on('data', chunk => chunks.push(chunk));
      stream.on('error', (error) => {
        // Distinguish between different stream error scenarios
        if (error.message.includes('connection') || error.message.includes('topology was destroyed')) {
          console.error(`GridFS: MongoDB connection lost during file stream for ${storageName} from bucket ${bucketName}:`, error.message);
          reject(new Error(`MongoDB connection lost while reading file (fileId: ${storageName}, bucket: ${bucketName})`));
        } else if (error.message.includes('File not found')) {
          console.error(`GridFS: File not found during stream for ${storageName} from bucket ${bucketName}`);
          reject(new Error(`File not found in GridFS (fileId: ${storageName}, bucket: ${bucketName})`));
        } else {
          console.error(`GridFS: Stream error for file ${storageName} from bucket ${bucketName}:`, error.message);
          reject(new Error(`Failed to read file stream: ${error.message} (fileId: ${storageName}, bucket: ${bucketName})`));
        }
      });
      stream.on('end', () => resolve(Buffer.concat(chunks)));
    });
  } catch (error) {
    // Error already has clear message from getFileStream, just log and re-throw
    console.error(`storageService.getFile error for ${storageName} from bucket ${bucketName}:`, error.message);
    throw error;
  }
};

/**
 * Legacy Interface: Get all attachments for a resource.
 */
const getAttachmentsForResource = async (resourceType, resourceId) => {
  return await Attachment.find({ resourceType, resourceId, isDeleted: false })
    .select('fileName fileSize fileType url uploadedAt uploadedBy');
};

/**
 * Legacy Interface: Soft delete.
 */
const deleteAttachment = async (attachmentId, deletedBy) => {
  return await Attachment.findByIdAndUpdate(attachmentId, {
    isDeleted: true,
    deletedAt: new Date(),
    deletedBy,
  });
};

/**
 * Categorize upload error and return user-friendly message.
 * 
 * @param {Error} error - The error object from GridFS
 * @param {string} fileName - Original filename for context
 * @param {string} bucketName - Bucket name for context
 * @param {number} fileSize - File size in bytes for context
 * @returns {Object} Object with errorType and userMessage
 */
const categorizeUploadError = (error, fileName, bucketName, fileSize) => {
  const errorMsg = error.message || '';
  const errorCode = error.code;
  
  // Connection-related errors
  if (errorMsg.includes('connection') || errorMsg.includes('ECONNREFUSED') || 
      errorMsg.includes('ECONNRESET') || errorMsg.includes('ETIMEDOUT') ||
      errorCode === 'ECONNREFUSED' || errorCode === 'ECONNRESET' || errorCode === 'ETIMEDOUT') {
    console.error(`GridFS: Connection lost during upload - file: ${fileName}, bucket: ${bucketName}, size: ${fileSize} bytes, error: ${errorMsg}`);
    return {
      errorType: 'connection_lost',
      userMessage: 'Upload failed due to connection issue. Please check your network and try again.'
    };
  }
  
  // Disk space errors
  if (errorMsg.includes('disk full') || errorMsg.includes('no space') || 
      errorMsg.includes('ENOSPC') || errorCode === 'ENOSPC') {
    console.error(`GridFS: Disk full during upload - file: ${fileName}, bucket: ${bucketName}, size: ${fileSize} bytes, error: ${errorMsg}`);
    return {
      errorType: 'disk_full',
      userMessage: 'Upload failed due to insufficient storage space. Please contact your administrator.'
    };
  }
  
  // Permission errors
  if (errorMsg.includes('permission') || errorMsg.includes('EACCES') || 
      errorMsg.includes('unauthorized') || errorCode === 'EACCES') {
    console.error(`GridFS: Permission denied during upload - file: ${fileName}, bucket: ${bucketName}, size: ${fileSize} bytes, error: ${errorMsg}`);
    return {
      errorType: 'permission_denied',
      userMessage: 'Upload failed due to permission issue. Please contact your administrator.'
    };
  }
  
  // Database not ready
  if (errorMsg.includes('Database not ready') || errorMsg.includes('not ready')) {
    console.error(`GridFS: Database not ready during upload - file: ${fileName}, bucket: ${bucketName}, size: ${fileSize} bytes, error: ${errorMsg}`);
    return {
      errorType: 'database_not_ready',
      userMessage: 'Upload failed because the database is not ready. Please try again in a moment.'
    };
  }
  
  // Generic error with context
  console.error(`GridFS: Upload error - file: ${fileName}, bucket: ${bucketName}, size: ${fileSize} bytes, error: ${errorMsg}`);
  return {
    errorType: 'unknown',
    userMessage: `Upload failed: ${errorMsg || 'Unknown error occurred'}`
  };
};

/**
 * New Enterprise Interface: Upload buffer directly to GridFS.
 * Includes post-upload verification to ensure file is retrievable.
 * 
 * @param {Buffer} buffer - File data buffer
 * @param {string} originalName - Original filename
 * @param {string} mimeType - MIME type of the file
 * @param {ObjectId} uploadedBy - User ID who uploaded the file
 * @param {string} bucketName - GridFS bucket name (default: 'ticketAttachments')
 * @param {number} retryCount - Current retry attempt (internal use)
 * @returns {Promise<Object>} Upload result with url, fileId, and size
 */
const uploadBuffer = async (buffer, originalName, mimeType, uploadedBy = null, bucketName = 'ticketAttachments', retryCount = 0) => {
  return new Promise(async (resolve, reject) => {
    try {
      const bucket = await getBucket(bucketName);
      const storedName = `${Date.now()}-${originalName.replace(/[^a-zA-Z0-9._-]/g, '_')}`;
      const uploadStream = bucket.openUploadStream(storedName, {
        contentType: mimeType || 'application/octet-stream',
        metadata: { originalName, uploadedBy, provider: 'gridfs' },
      });

      uploadStream.on('error', (error) => {
        // Categorize error and provide user-friendly message
        const { errorType, userMessage } = categorizeUploadError(error, originalName, bucketName, buffer.length);
        
        // Create enhanced error with context
        const enhancedError = new Error(userMessage);
        enhancedError.errorType = errorType;
        enhancedError.fileName = originalName;
        enhancedError.bucketName = bucketName;
        enhancedError.fileSize = buffer.length;
        enhancedError.originalError = error.message;
        
        reject(enhancedError);
      });

      uploadStream.on('finish', async () => {
        try {
          // Use uploadStream.id directly (not file._id which is undefined)
          const fileId = String(uploadStream.id);
          
          // Post-upload verification: Ensure file is retrievable
          const files = await bucket.find({ _id: uploadStream.id }).limit(1).toArray();
          if (!files || files.length === 0) {
            const verificationError = new Error(`File upload verification failed: File ${fileId} not found in GridFS after upload`);
            
            // Retry upload once if verification fails
            if (retryCount === 0) {
              console.warn(`GridFS: File verification failed for ${originalName}, retrying upload (attempt 2/2)...`);
              try {
                const retryResult = await uploadBuffer(buffer, originalName, mimeType, uploadedBy, bucketName, retryCount + 1);
                resolve(retryResult);
                return;
              } catch (retryError) {
                console.error(`GridFS: Retry upload failed - file: ${originalName}, bucket: ${bucketName}, size: ${buffer.length} bytes, error: ${retryError.message}`);
                
                // Categorize retry error
                const { errorType, userMessage } = categorizeUploadError(retryError, originalName, bucketName, buffer.length);
                const enhancedRetryError = new Error(`${userMessage} (retry failed)`);
                enhancedRetryError.errorType = errorType;
                enhancedRetryError.fileName = originalName;
                enhancedRetryError.bucketName = bucketName;
                enhancedRetryError.fileSize = buffer.length;
                
                reject(enhancedRetryError);
                return;
              }
            }
            
            throw verificationError;
          }

          const url = `/api/tickets/attachments/${fileId}?filename=${encodeURIComponent(originalName)}`;
          console.log(`GridFS: File uploaded successfully to bucket '${bucketName}': ${fileId} (${buffer.length} bytes)`);
          resolve({ url, fileId, size: buffer.length });
        } catch (verificationError) {
          console.error(`GridFS: Post-upload verification failed - file: ${originalName}, bucket: ${bucketName}, size: ${buffer.length} bytes, error: ${verificationError.message}`);
          
          // Categorize verification error
          const { errorType, userMessage } = categorizeUploadError(verificationError, originalName, bucketName, buffer.length);
          const enhancedError = new Error(userMessage);
          enhancedError.errorType = errorType;
          enhancedError.fileName = originalName;
          enhancedError.bucketName = bucketName;
          enhancedError.fileSize = buffer.length;
          
          reject(enhancedError);
        }
      });

      uploadStream.end(buffer);
    } catch (error) {
      // Categorize initial error (e.g., getBucket failure)
      const { errorType, userMessage } = categorizeUploadError(error, originalName, bucketName, buffer.length);
      const enhancedError = new Error(userMessage);
      enhancedError.errorType = errorType;
      enhancedError.fileName = originalName;
      enhancedError.bucketName = bucketName;
      enhancedError.fileSize = buffer.length;
      enhancedError.originalError = error.message;
      
      reject(enhancedError);
    }
  });
};

/**
 * New Enterprise Interface: Get file stream by GridFS ID.
 * Includes retry logic for transient errors and improved error messages.
 * 
 * @param {string} fileId - GridFS file ID
 * @param {string} bucketName - GridFS bucket name (default: 'ticketAttachments')
 * @param {number} retryCount - Current retry attempt (internal use)
 * @returns {Promise<Object>} Object with stream and file metadata
 */
const getFileStream = async (fileId, bucketName = 'ticketAttachments', retryCount = 0) => {
  try {
    const bucket = await getBucket(bucketName);
    const oid = new ObjectId(fileId);
    const files = await bucket.find({ _id: oid }).limit(1).toArray();
    
    if (!files || files.length === 0) {
      // Clear error: file never uploaded or was deleted from GridFS
      throw new Error(`File not found in GridFS (fileId: ${fileId}, bucket: ${bucketName})`);
    }
    
    return { stream: bucket.openDownloadStream(oid), file: files[0] };
  } catch (error) {
    // Distinguish between different failure scenarios
    
    // 1. GridFS bucket not initialized (connection timing issue)
    if (error.message.includes('Database not ready') || error.message.includes('bucket not initialized')) {
      console.error(`GridFS: Bucket initialization error for ${bucketName} when retrieving file ${fileId}:`, error.message);
      throw new Error(`GridFS bucket not initialized (fileId: ${fileId}, bucket: ${bucketName}). Please try again.`);
    }
    
    // 2. MongoDB connection lost (connection dropped during download)
    const isConnectionError = error.message.includes('connection') || 
                             error.message.includes('ECONNREFUSED') ||
                             error.message.includes('ENOTFOUND') ||
                             error.message.includes('topology was destroyed');
    
    if (isConnectionError && retryCount === 0) {
      console.warn(`GridFS: MongoDB connection lost while retrieving file ${fileId} from bucket ${bucketName}, retrying...`);
      await new Promise(resolve => setTimeout(resolve, 1000));
      return getFileStream(fileId, bucketName, retryCount + 1);
    }
    
    if (isConnectionError) {
      console.error(`GridFS: MongoDB connection lost for file ${fileId} from bucket ${bucketName} after retry`);
      throw new Error(`MongoDB connection lost (fileId: ${fileId}, bucket: ${bucketName}). Please check your connection and try again.`);
    }
    
    // 3. File not found in GridFS (file never uploaded)
    if (error.message.includes('File not found in GridFS')) {
      throw error; // Already has clear message with fileId and bucket
    }
    
    // 4. Timeout errors
    if (error.message.includes('timeout')) {
      console.warn(`GridFS: Timeout retrieving file ${fileId} from bucket ${bucketName}`);
      if (retryCount === 0) {
        await new Promise(resolve => setTimeout(resolve, 1000));
        return getFileStream(fileId, bucketName, retryCount + 1);
      }
      throw new Error(`Request timeout while retrieving file (fileId: ${fileId}, bucket: ${bucketName}). Please try again.`);
    }
    
    // 5. Generic error with context
    console.error(`GridFS: Error retrieving file stream for ${fileId} from bucket ${bucketName}:`, error.message);
    throw new Error(`Failed to retrieve file: ${error.message} (fileId: ${fileId}, bucket: ${bucketName})`);
  }
};

module.exports = {
  saveAttachment,
  getFile,
  getAttachmentsForResource,
  deleteAttachment,
  uploadBuffer,
  getFileStream,
  getBucket,
  initializeGridFSBuckets
};
