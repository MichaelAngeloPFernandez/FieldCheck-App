const express = require('express');
const router = express.Router();
const asyncHandler = require('express-async-handler');
const appNotificationService = require('../services/appNotificationService');
const emailService = require('../utils/emailService');

/**
 * POST /api/contact
 * Submit a contact inquiry (public endpoint, no auth required)
 * Replacement for email launcher - creates backend record + notification
 */
router.post(
  '/',
  asyncHandler(async (req, res) => {
    const { name, email, subject, message, serviceCategory } = req.body;

    // Input validation
    if (!name || typeof name !== 'string' || name.trim().length < 2) {
      return res.status(400).json({ error: 'Invalid name. Must be at least 2 characters.' });
    }

    if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      return res.status(400).json({ error: 'Invalid email address.' });
    }

    if (!subject || typeof subject !== 'string' || subject.trim().length < 5) {
      return res.status(400).json({ error: 'Subject must be at least 5 characters.' });
    }

    if (!message || typeof message !== 'string' || message.trim().length < 10) {
      return res.status(400).json({ error: 'Message must be at least 10 characters.' });
    }

    if (!serviceCategory || !['billing', 'technical', 'account', 'service', 'other'].includes(serviceCategory)) {
      return res.status(400).json({ error: 'Invalid service category.' });
    }

    try {
      // Create confirmation email to sender
      const confirmationEmailHtml = `
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Contact Message Received</title>
            <style>
                body {
                    font-family: Arial, sans-serif;
                    background-color: #f4f4f4;
                    margin: 0;
                    padding: 0;
                }
                .container {
                    width: 100%;
                    max-width: 600px;
                    margin: 0 auto;
                    background-color: #ffffff;
                    padding: 20px;
                    border-radius: 8px;
                    box-shadow: 0 0 10px rgba(0, 0, 0, 0.1);
                }
                .header {
                    background-color: #2688d4;
                    color: #ffffff;
                    padding: 20px;
                    text-align: center;
                    border-radius: 8px 8px 0 0;
                    margin: -20px -20px 20px -20px;
                }
                .content {
                    padding: 0 20px;
                }
                .footer {
                    text-align: center;
                    padding: 20px;
                    font-size: 12px;
                    color: #888888;
                    border-top: 1px solid #e0e0e0;
                    margin-top: 20px;
                }
            </style>
        </head>
        <body>
            <div class="container">
                <div class="header">
                    <h1>📧 Message Received</h1>
                </div>
                
                <div class="content">
                    <p>Hello ${name},</p>
                    
                    <p>Thank you for reaching out to FieldCheck. We have received your message and will respond as soon as possible.</p>
                    
                    <h3>Your Message Details:</h3>
                    <p><strong>Subject:</strong> ${subject}</p>
                    <p><strong>Category:</strong> ${serviceCategory}</p>
                    <p><strong>Message:</strong></p>
                    <p style="background-color: #f5f5f5; padding: 10px; border-radius: 4px;">
                        ${message}
                    </p>
                    
                    <p>Our team will review your inquiry and get back to you at <strong>${email}</strong> shortly.</p>
                    
                    <p>If you have an urgent issue, please contact us directly at <strong>09945304513</strong></p>
                    
                    <p>Best regards,<br>FieldCheck Support Team</p>
                </div>
                
                <div class="footer">
                    <p>This is an automated confirmation email. Please do not reply directly to this message.</p>
                </div>
            </div>
        </body>
        </html>
      `;

      // Send confirmation to client
      await emailService.sendEmail({
        to: email,
        subject: 'We Received Your Message - FieldCheck',
        html: confirmationEmailHtml,
      });

      // Create notification for admins
      await appNotificationService.createForAdmins({
        scope: 'clientTickets',
        type: 'contact_inquiry',
        title: `New Contact Inquiry: ${subject}`,
        message: `${name} (${email}) submitted a ${serviceCategory} inquiry.`,
        action: 'view_contact',
        payload: {
          senderName: name,
          senderEmail: email,
          category: serviceCategory,
          subject,
          message,
        },
      });

      // Emit real-time notification
      if (global.io) {
        global.io.emit('contact_inquiry_submitted', {
          name,
          email,
          category: serviceCategory,
          subject,
        });
      }

      res.status(201).json({
        success: true,
        message: 'Your message has been received. We will respond shortly.',
      });
    } catch (error) {
      console.error('Error submitting contact inquiry:', error);
      res.status(500).json({
        error: 'Failed to submit contact inquiry',
        message: process.env.NODE_ENV === 'development' ? error.message : 'Internal error',
      });
    }
  })
);

module.exports = router;
