/**
 * StorageService.js
 * 
 * Manages file storage and retrieval.
 * Currently uses Render ephemeral storage with MongoDB metadata.
 * 
 * Future: Can swap provider (Cloudinary, S3) by changing uploadFile() + getUrl()
 */

const Attachment = require('../models/Attachment');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

// Ephemeral storage directory (exists only until restart)
const UPLOAD_DIR = path.join(__dirname, '../uploads');

class StorageService {
  /**
   * Initialize storage (create directories if needed)
   */
  static async init() {
    if (!fs.existsSync(UPLOAD_DIR)) {
      fs.mkdirSync(UPLOAD_DIR, { recursive: true });
    }
  }

  /**
   * Save attachment metadata to database
   * 
   * @param {Object} options
   * @param {string} options.resourceType - 'report', 'task', 'ticket'
   * @param {string} options.resourceId - MongoDB ObjectId
   * @param {string} options.fileName - Original filename
   * @param {Buffer} options.fileData - File content
   * @param {string} options.fileType - MIME type
   * @param {string} options.uploadedBy - User MongoDB ObjectId
   * @returns {Promise<Object>} - Attachment record with ID and URL
   */
  static async saveAttachment({
    resourceType,
    resourceId,
    fileName,
    fileData,
    fileType,
    uploadedBy,
  }) {
    try {
      // 1. Calculate checksum for integrity
      const checksum = crypto
        .createHash('sha256')
        .update(fileData)
        .digest('hex');

      // 2. Check for duplicate (same file uploaded twice)
      const existing = await Attachment.findOne({
        checksum,
        isDeleted: false,
      });

      if (existing) {
        // Reuse existing file, just create new metadata reference
        return existing;
      }

      // 3. Generate unique filename
      const timestamp = Date.now();
      const randomStr = Math.random().toString(36).substring(7);
      const storageName = `${timestamp}-${randomStr}-${fileName}`;

      // 4. Save file to disk (ephemeral storage on Render)
      const filePath = path.join(UPLOAD_DIR, storageName);
      fs.writeFileSync(filePath, fileData);

      // 5. Generate access URL (via proxy endpoint)
      const url = `/api/attachments/${storageName}`;

      // 6. Create metadata record in database
      const attachment = new Attachment({
        resourceType,
        resourceId,
        fileName,
        fileSize: fileData.length,
        fileType,
        url,
        provider: 'render', // Ephemeral storage
        checksum,
        uploadedBy,
        uploadedAt: new Date(),
      });

      await attachment.save();

      return {
        _id: attachment._id,
        fileName: attachment.fileName,
        url: attachment.url,
        fileSize: attachment.fileSize,
        uploadedAt: attachment.uploadedAt,
      };
    } catch (error) {
      console.error('StorageService.saveAttachment error:', error);
      throw new Error(`Failed to save attachment: ${error.message}`);
    }
  }

  /**
   * Retrieve attachment file by storage name
   * 
   * @param {string} storageName - Filename from attachment record
   * @returns {Promise<Buffer>} - File content
   */
  static async getFile(storageName) {
    try {
      const filePath = path.join(UPLOAD_DIR, storageName);

      // Security: prevent directory traversal
      if (!filePath.startsWith(UPLOAD_DIR)) {
        throw new Error('Invalid file path');
      }

      if (!fs.existsSync(filePath)) {
        throw new Error('File not found');
      }

      return fs.readFileSync(filePath);
    } catch (error) {
      console.error('StorageService.getFile error:', error);
      throw error;
    }
  }

  /**
   * Get all attachments for a resource
   * 
   * @param {string} resourceType - 'report', 'task', 'ticket'
   * @param {string} resourceId - MongoDB ObjectId
   * @returns {Promise<Array>} - Array of attachment records
   */
  static async getAttachmentsForResource(resourceType, resourceId) {
    try {
      return await Attachment.find({
        resourceType,
        resourceId,
        isDeleted: false,
      }).select('fileName fileSize fileType url uploadedAt uploadedBy');
    } catch (error) {
      console.error('StorageService.getAttachmentsForResource error:', error);
      throw error;
    }
  }

  /**
   * Delete attachment (soft delete)
   * 
   * @param {string} attachmentId - Attachment MongoDB ObjectId
   * @param {string} deletedBy - User MongoDB ObjectId
   */
  static async deleteAttachment(attachmentId, deletedBy) {
    try {
      await Attachment.findByIdAndUpdate(attachmentId, {
        isDeleted: true,
        deletedAt: new Date(),
        deletedBy,
      });
    } catch (error) {
      console.error('StorageService.deleteAttachment error:', error);
      throw error;
    }
  }

  /**
   * Migration: Convert existing URL strings to Attachment records
   * Use this when migrating from old string-based attachments
   * 
   * @param {string} resourceType
   * @param {string} resourceId
   * @param {Array<string>} urls
   * @param {string} uploadedBy
   */
  static async migrateUrlsToAttachments(resourceType, resourceId, urls, uploadedBy) {
    try {
      const attachments = [];

      for (const url of urls || []) {
        const attachment = new Attachment({
          resourceType,
          resourceId,
          fileName: url.split('/').pop() || 'unknown',
          fileSize: 0, // Unknown for existing URLs
          fileType: 'application/octet-stream',
          url, // Keep original URL
          provider: 'unknown', // Unknown origin
          checksum: null, // Can't compute for existing URLs
          uploadedBy,
          uploadedAt: new Date(),
        });

        await attachment.save();
        attachments.push(attachment);
      }

      return attachments;
    } catch (error) {
      console.error('StorageService.migrateUrlsToAttachments error:', error);
      throw error;
    }
  }
}

module.exports = StorageService;
