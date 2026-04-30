/**
 * Storage Service — abstraction over GridFS for ticket/report attachments.
 * Currently uses MongoDB GridFS (already proven durable with Atlas).
 * If a future migration to S3/Cloudinary is needed, only this file changes.
 */
const mongoose = require('mongoose');
const { GridFSBucket } = require('mongodb');
const crypto = require('crypto');

const BUCKET_NAME = 'ticketAttachments';

/**
 * Get (or create) the GridFS bucket for ticket attachments.
 */
const getBucket = () => {
  if (!mongoose.connection || !mongoose.connection.db) {
    throw new Error('Database not ready');
  }
  return new GridFSBucket(mongoose.connection.db, { bucketName: BUCKET_NAME });
};

/**
 * Upload a buffer to GridFS and return the access URL + metadata.
 *
 * @param {Buffer} buffer       - File contents
 * @param {string} originalName - Original filename from the client
 * @param {string} mimeType     - MIME type of the file
 * @param {string|null} uploadedBy - User ID of the uploader
 * @returns {Promise<{url: string, fileId: string, checksum: string, size: number}>}
 */
const uploadBuffer = (buffer, originalName, mimeType, uploadedBy = null) => {
  return new Promise((resolve, reject) => {
    const bucket = getBucket();
    const safeName = (originalName || 'attachment').replace(/[^a-zA-Z0-9._-]/g, '_');
    const storedName = `${Date.now()}-${safeName}`;
    const checksum = crypto.createHash('md5').update(buffer).digest('hex');

    const uploadStream = bucket.openUploadStream(storedName, {
      contentType: mimeType || 'application/octet-stream',
      metadata: {
        originalName,
        checksum,
        uploadedBy: uploadedBy || undefined,
        provider: 'gridfs',
      },
    });

    uploadStream.on('error', reject);
    uploadStream.on('finish', (file) => {
      const rawId = (file && file._id) || uploadStream.id;
      const fileId = rawId ? String(rawId) : null;
      if (!fileId) return reject(new Error('Upload succeeded but no file id returned'));

      const qp = new URLSearchParams({ filename: originalName }).toString();
      const url = `/api/tickets/attachments/${fileId}?${qp}`;
      resolve({ url, fileId, checksum, size: buffer.length });
    });

    uploadStream.end(buffer);
  });
};

/**
 * Stream a file from GridFS by its ObjectId.
 * Returns { stream, file } where file contains metadata.
 */
const getFileStream = async (fileId) => {
  const bucket = getBucket();
  const { ObjectId } = require('mongodb');
  const oid = new ObjectId(fileId);

  const files = await bucket.find({ _id: oid }).limit(1).toArray();
  if (!files || files.length === 0) return null;

  const file = files[0];
  const stream = bucket.openDownloadStream(oid);
  return { stream, file };
};

module.exports = { uploadBuffer, getFileStream, getBucket };
