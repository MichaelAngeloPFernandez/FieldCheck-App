/**
 * Storage Service — abstraction over GridFS for ticket/report/task attachments.
 * Currently uses MongoDB GridFS (durable with Atlas).
 */
const mongoose = require('mongoose');
const { GridFSBucket, ObjectId } = require('mongodb');
const crypto = require('crypto');
const Attachment = require('../models/Attachment');

const BUCKET_NAME = 'ticketAttachments';

/**
 * Get (or create) the GridFS bucket.
 */
const getBucket = () => {
  if (!mongoose.connection || !mongoose.connection.db) {
    throw new Error('Database not ready');
  }
  return new GridFSBucket(mongoose.connection.db, { bucketName: BUCKET_NAME });
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
 */
const getFile = async (storageName) => {
  try {
    const { stream } = await getFileStream(storageName);
    const chunks = [];
    return new Promise((resolve, reject) => {
      stream.on('data', chunk => chunks.push(chunk));
      stream.on('error', reject);
      stream.on('end', () => resolve(Buffer.concat(chunks)));
    });
  } catch (error) {
    console.error('storageService.getFile error:', error);
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
 * New Enterprise Interface: Upload buffer directly to GridFS.
 */
const uploadBuffer = (buffer, originalName, mimeType, uploadedBy = null) => {
  return new Promise((resolve, reject) => {
    const bucket = getBucket();
    const storedName = `${Date.now()}-${originalName.replace(/[^a-zA-Z0-9._-]/g, '_')}`;
    const uploadStream = bucket.openUploadStream(storedName, {
      contentType: mimeType || 'application/octet-stream',
      metadata: { originalName, uploadedBy, provider: 'gridfs' },
    });

    uploadStream.on('error', reject);
    uploadStream.on('finish', (file) => {
      const fileId = String(file._id || uploadStream.id);
      const url = `/api/tickets/attachments/${fileId}?filename=${encodeURIComponent(originalName)}`;
      resolve({ url, fileId, size: buffer.length });
    });
    uploadStream.end(buffer);
  });
};

/**
 * New Enterprise Interface: Get file stream by GridFS ID.
 */
const getFileStream = async (fileId) => {
  const bucket = getBucket();
  const oid = new ObjectId(fileId);
  const files = await bucket.find({ _id: oid }).limit(1).toArray();
  if (!files || files.length === 0) throw new Error('File not found');
  return { stream: bucket.openDownloadStream(oid), file: files[0] };
};

module.exports = {
  saveAttachment,
  getFile,
  getAttachmentsForResource,
  deleteAttachment,
  uploadBuffer,
  getFileStream,
  getBucket
};
